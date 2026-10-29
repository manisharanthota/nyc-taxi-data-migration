"""
Load NYC TLC parquet files (data/raw) into SQL Server tables from source_db/schema.sql:
    yellow_tripdata_*.parquet -> trips.yellow_trip
    green_tripdata_*.parquet  -> trips.green_trip

- Streams each file in batches (pyarrow) -> constant memory
- Batched inserts with pyodbc fast_executemany, commit per batch
- Rows that would break FK / CHECK / type rules go to data/rejects/<file>.parquet
- etl.load_log tracks each file: re-runs skip finished files, and a file that
  failed or crashed mid-way is cleaned up and reloaded (no duplicates)
- Progress bars (files + rows) and a log line per finished file (logs/load.log)

Run from anywhere:  python scripts/load_parquet.py
Prereqs: schema.sql + seed_lookups.sql already run on database NYCTaxi.
"""
import logging
import os
import time
from datetime import datetime
from pathlib import Path

import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq
import pyodbc
from tqdm import tqdm

# ---------- paths & config ----------
ROOT = Path(__file__).parent.parent
RAW_DIR = ROOT / "data" / "raw"
REJECT_DIR = ROOT / "data" / "rejects"
LOG_DIR = ROOT / "logs"
BATCH_SIZE = int(os.getenv("BATCH_SIZE", 50_000))


def read_env_file(path: Path) -> dict:
    env = {}
    if path.exists():
        for line in path.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    return env


_env = read_env_file(ROOT / "source_db" / ".env")
CONN_STR = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    f"SERVER={os.getenv('SQL_SERVER', 'localhost,1433')};"
    f"DATABASE={os.getenv('SQL_DB', 'NYCTaxi')};"
    f"UID={os.getenv('SQL_USER', 'sa')};"
    f"PWD={os.getenv('MSSQL_SA_PASSWORD', _env.get('MSSQL_SA_PASSWORD', ''))};"
    "TrustServerCertificate=yes;"
)

# parquet column (lower-cased) -> table column
RENAME = {
    "vendorid": "vendor_id",
    "tpep_pickup_datetime": "pickup_datetime",
    "tpep_dropoff_datetime": "dropoff_datetime",
    "lpep_pickup_datetime": "pickup_datetime",
    "lpep_dropoff_datetime": "dropoff_datetime",
    "ratecodeid": "rate_code_id",
    "pulocationid": "pu_location_id",
    "dolocationid": "do_location_id",
    "payment_type": "payment_type_id",
    "trip_type": "trip_type_id",
}

MONEY = pa.decimal128(10, 2)
TARGETS = {
    "yellow": ("trips.yellow_trip", {
        "vendor_id": pa.int16(), "pickup_datetime": pa.timestamp("us"),
        "dropoff_datetime": pa.timestamp("us"), "passenger_count": pa.int16(),
        "trip_distance": MONEY, "rate_code_id": pa.int16(), "store_and_fwd_flag": pa.string(),
        "pu_location_id": pa.int32(), "do_location_id": pa.int32(), "payment_type_id": pa.int16(),
        "fare_amount": MONEY, "extra": MONEY, "mta_tax": MONEY, "tip_amount": MONEY,
        "tolls_amount": MONEY, "improvement_surcharge": MONEY, "total_amount": MONEY,
        "congestion_surcharge": MONEY, "airport_fee": MONEY, "cbd_congestion_fee": MONEY,
    }),
    "green": ("trips.green_trip", {
        "vendor_id": pa.int16(), "pickup_datetime": pa.timestamp("us"),
        "dropoff_datetime": pa.timestamp("us"), "store_and_fwd_flag": pa.string(),
        "rate_code_id": pa.int16(), "pu_location_id": pa.int32(), "do_location_id": pa.int32(),
        "passenger_count": pa.int16(), "trip_distance": MONEY, "fare_amount": MONEY,
        "extra": MONEY, "mta_tax": MONEY, "tip_amount": MONEY, "tolls_amount": MONEY,
        "ehail_fee": MONEY, "improvement_surcharge": MONEY, "total_amount": MONEY,
        "payment_type_id": pa.int16(), "trip_type_id": pa.int16(),
        "congestion_surcharge": MONEY, "cbd_congestion_fee": MONEY,
    }),
}
NOT_NULL = ["vendor_id", "pickup_datetime", "dropoff_datetime", "pu_location_id", "do_location_id"]
FK = {  # column -> lookup key
    "vendor_id": "vendor", "rate_code_id": "rate_code", "payment_type_id": "payment_type",
    "trip_type_id": "trip_type", "pu_location_id": "zone", "do_location_id": "zone",
}
MONEY_MAX = 99_999_999.99


# ---------- logging (plays nicely with progress bars) ----------
class TqdmHandler(logging.Handler):
    def emit(self, record):
        tqdm.write(self.format(record))


LOG_DIR.mkdir(exist_ok=True)
_fmt = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
_fh = logging.FileHandler(LOG_DIR / "load.log")
_th = TqdmHandler()
for h in (_fh, _th):
    h.setFormatter(_fmt)
log = logging.getLogger("loader")
log.setLevel(logging.INFO)
log.addHandler(_fh)
log.addHandler(_th)


# ---------- database helpers ----------
def setup_load_log(cur):
    cur.execute("IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl')")
    cur.execute("""
        IF OBJECT_ID('etl.load_log') IS NULL
        CREATE TABLE etl.load_log (
            file_name      VARCHAR(200) NOT NULL PRIMARY KEY,
            target_table   VARCHAR(100) NOT NULL,
            status         VARCHAR(20)  NOT NULL,   -- started | done | failed
            start_trip_id  BIGINT       NOT NULL,   -- rows > this belong to the file
            rows_loaded    BIGINT       NULL,
            rows_rejected  BIGINT       NULL,
            started_at     DATETIME2(0) NOT NULL,
            finished_at    DATETIME2(0) NULL,
            error          NVARCHAR(4000) NULL
        )""")


def load_lookups(cur) -> dict:
    q = {
        "vendor": "SELECT vendor_id FROM ref.vendor",
        "rate_code": "SELECT rate_code_id FROM ref.rate_code",
        "payment_type": "SELECT payment_type_id FROM ref.payment_type",
        "trip_type": "SELECT trip_type_id FROM ref.trip_type",
        "zone": "SELECT location_id FROM ref.taxi_zone",
    }
    out = {}
    for k, sql in q.items():
        vals = [r[0] for r in cur.execute(sql).fetchall()]
        if not vals:
            raise RuntimeError(f"Lookup '{k}' is empty - run seed_lookups.sql first")
        out[k] = pa.array(vals, pa.int32())
    return out


def delete_partial(conn, table: str, start_id: int):
    """Remove rows a failed/crashed load left behind (in chunks to keep the log small)."""
    cur = conn.cursor()
    while True:
        cur.execute(f"DELETE TOP (100000) FROM {table} WHERE trip_id > ?", start_id)
        n = cur.rowcount
        conn.commit()
        if n <= 0:
            break


# ---------- transform & validate ----------
def shape_batch(batch: pa.RecordBatch, cols: dict) -> pa.Table:
    """Rename parquet columns, add missing ones as NULL, drop extras."""
    src = {}
    for name, arr in zip(batch.schema.names, batch.columns):
        key = name.lower()
        src[RENAME.get(key, key)] = arr
    n = batch.num_rows
    out = {}
    for col, typ in cols.items():
        arr = src.get(col)
        if arr is None:
            out[col] = pa.nulls(n, typ)
        elif typ == MONEY:
            out[col] = pc.round(pc.cast(arr, pa.float64()), 2)   # cast to decimal after validation
        elif pa.types.is_string(typ):
            out[col] = pc.cast(arr, pa.string())
        else:
            out[col] = pc.cast(arr, typ, safe=False) if pa.types.is_timestamp(typ) else pc.cast(arr, pa.int64())
    return pa.table(out)


def valid_mask(t: pa.Table, cols: dict, lookups: dict) -> pa.ChunkedArray:
    ok = pa.chunked_array([pa.array([True] * t.num_rows)])
    for c in NOT_NULL:
        ok = pc.and_kleene(ok, pc.is_valid(t[c]))
    for c, key in FK.items():
        if c in cols:
            ok = pc.and_kleene(ok, pc.or_kleene(pc.is_null(t[c]), pc.is_in(pc.cast(t[c], pa.int32()), value_set=lookups[key])))
    flag = t["store_and_fwd_flag"]
    ok = pc.and_kleene(ok, pc.or_kleene(pc.is_null(flag), pc.is_in(flag, value_set=pa.array(["Y", "N"]))))
    pc_ = t["passenger_count"]
    ok = pc.and_kleene(ok, pc.or_kleene(pc.is_null(pc_), pc.and_kleene(pc.greater_equal(pc_, 0), pc.less_equal(pc_, 255))))
    for c, typ in cols.items():
        if typ == MONEY:
            ok = pc.and_kleene(ok, pc.or_kleene(pc.is_null(t[c]), pc.less_equal(pc.abs(t[c]), MONEY_MAX)))
    return pc.fill_null(ok, False)


def to_rows(t: pa.Table, cols: dict) -> list:
    arrays = []
    for c, typ in cols.items():
        arr = t[c]
        if typ == MONEY:
            arr = pc.cast(arr, MONEY)          # -> Python Decimal, binds cleanly to DECIMAL(10,2)
        arrays.append(arr.to_pylist())
    return list(zip(*arrays))


# ---------- load one file ----------
def load_file(conn, path: Path, lookups: dict, files_bar: tqdm):
    kind = path.name.split("_")[0]
    table, cols = TARGETS[kind]
    cur = conn.cursor()
    cur.fast_executemany = True

    row = cur.execute("SELECT status, start_trip_id FROM etl.load_log WHERE file_name = ?", path.name).fetchone()
    if row and row.status == "done":
        log.info("SKIP %s (already loaded)", path.name)
        return
    if row:  # started (crashed) or failed earlier -> clean up its rows, then reload
        log.warning("CLEANUP %s (previous status: %s)", path.name, row.status)
        delete_partial(conn, table, row.start_trip_id)
        cur.execute("DELETE FROM etl.load_log WHERE file_name = ?", path.name)
        conn.commit()

    start_id = cur.execute(f"SELECT ISNULL(MAX(trip_id), 0) FROM {table}").fetchval()
    cur.execute("INSERT INTO etl.load_log (file_name, target_table, status, start_trip_id, started_at) "
                "VALUES (?, ?, 'started', ?, ?)", path.name, table, start_id, datetime.now())
    conn.commit()

    col_list = ", ".join(cols)
    insert = f"INSERT INTO {table} ({col_list}) VALUES ({', '.join('?' * len(cols))})"
    pf = pq.ParquetFile(path)
    loaded = rejected = 0
    reject_writer = None
    t0 = time.time()

    try:
        with tqdm(total=pf.metadata.num_rows, desc=f"  {path.name}", unit="rows",
                  unit_scale=True, leave=False, position=1) as bar:
            for batch in pf.iter_batches(batch_size=BATCH_SIZE):
                t = shape_batch(batch, cols)
                mask = valid_mask(t, cols, lookups)
                good, bad = t.filter(mask), t.filter(pc.invert(mask))

                if bad.num_rows:
                    if reject_writer is None:
                        REJECT_DIR.mkdir(parents=True, exist_ok=True)
                        reject_writer = pq.ParquetWriter(REJECT_DIR / path.name, bad.schema)
                    reject_writer.write_table(bad)
                    rejected += bad.num_rows

                if good.num_rows:
                    cur.executemany(insert, to_rows(good, cols))
                    conn.commit()
                    loaded += good.num_rows
                bar.update(batch.num_rows)
    except Exception as e:
        conn.rollback()
        log.exception("FAILED %s - removing its partial rows", path.name)
        delete_partial(conn, table, start_id)
        cur.execute("UPDATE etl.load_log SET status='failed', finished_at=?, error=? WHERE file_name=?",
                    datetime.now(), str(e)[:4000], path.name)
        conn.commit()
        raise
    finally:
        if reject_writer:
            reject_writer.close()

    cur.execute("UPDATE etl.load_log SET status='done', rows_loaded=?, rows_rejected=?, finished_at=? "
                "WHERE file_name=?", loaded, rejected, datetime.now(), path.name)
    conn.commit()
    secs = time.time() - t0
    log.info("DONE %s -> %s | %s loaded | %s rejected | %.0fs (%s rows/s)",
             path.name, table, f"{loaded:,}", f"{rejected:,}", secs, f"{loaded / max(secs, 1):,.0f}")


# ---------- main ----------
def main():
    files = sorted(p for p in RAW_DIR.glob("*.parquet") if p.name.split("_")[0] in TARGETS)
    if not files:
        log.warning("No yellow/green parquet files in %s", RAW_DIR)
        return
    log.info("Found %d file(s) in %s", len(files), RAW_DIR)

    failed = []
    with pyodbc.connect(CONN_STR, autocommit=False) as conn:
        cur = conn.cursor()
        setup_load_log(cur)
        conn.commit()
        lookups = load_lookups(cur)

        with tqdm(total=len(files), desc="Files", unit="file", position=0) as files_bar:
            for f in files:
                try:
                    load_file(conn, f, lookups, files_bar)
                except Exception:
                    failed.append(f.name)
                files_bar.update(1)

    if failed:
        log.error("Finished with %d failed file(s): %s", len(failed), ", ".join(failed))
    else:
        log.info("All files loaded")


if __name__ == "__main__":
    main()
