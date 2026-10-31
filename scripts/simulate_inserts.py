"""simulate_inserts.py : trickle new trips from the held-out parquet into the source DB.

Each run inserts the next batch of rows (by file position) and logs it in etl.sim_progress.
created_at is filled by the table default, so the incremental pipeline sees new rows.

Usage:
    python scripts/simulate_inserts.py --table yellow
    python scripts/simulate_inserts.py --table green --rows 100000
"""
import argparse
import os
from pathlib import Path

import pandas as pd
import pyodbc
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
HOLDOUT = ROOT / "data" / "holdout"
load_dotenv(ROOT / "source_db" / ".env")

# parquet column -> SQL column, per table
COLUMNS = {
    "yellow_trip": {
        "file": "yellow_tripdata_2026-09.parquet",
        "map": {
            "VendorID": "vendor_id",
            "tpep_pickup_datetime": "pickup_datetime",
            "tpep_dropoff_datetime": "dropoff_datetime",
            "passenger_count": "passenger_count",
            "trip_distance": "trip_distance",
            "RatecodeID": "rate_code_id",
            "store_and_fwd_flag": "store_and_fwd_flag",
            "PULocationID": "pu_location_id",
            "DOLocationID": "do_location_id",
            "payment_type": "payment_type_id",
            "fare_amount": "fare_amount",
            "extra": "extra",
            "mta_tax": "mta_tax",
            "tip_amount": "tip_amount",
            "tolls_amount": "tolls_amount",
            "improvement_surcharge": "improvement_surcharge",
            "total_amount": "total_amount",
            "congestion_surcharge": "congestion_surcharge",
            "Airport_fee": "airport_fee",
            "cbd_congestion_fee": "cbd_congestion_fee",
        },
    },
    "green_trip": {
        "file": "green_tripdata_2026-09.parquet",
        "map": {
            "VendorID": "vendor_id",
            "lpep_pickup_datetime": "pickup_datetime",
            "lpep_dropoff_datetime": "dropoff_datetime",
            "store_and_fwd_flag": "store_and_fwd_flag",
            "RatecodeID": "rate_code_id",
            "PULocationID": "pu_location_id",
            "DOLocationID": "do_location_id",
            "passenger_count": "passenger_count",
            "trip_distance": "trip_distance",
            "fare_amount": "fare_amount",
            "extra": "extra",
            "mta_tax": "mta_tax",
            "tip_amount": "tip_amount",
            "tolls_amount": "tolls_amount",
            "ehail_fee": "ehail_fee",
            "improvement_surcharge": "improvement_surcharge",
            "total_amount": "total_amount",
            "payment_type": "payment_type_id",
            "trip_type": "trip_type_id",
            "congestion_surcharge": "congestion_surcharge",
            "cbd_congestion_fee": "cbd_congestion_fee",
        },
    },
}
INT_COLS = {"vendor_id", "passenger_count", "rate_code_id", "pu_location_id",
            "do_location_id", "payment_type_id", "trip_type_id"}

NEXT_OFFSET_SQL = """
SELECT ISNULL((
    SELECT TOP 1 start_offset + rows_inserted
    FROM etl.sim_progress
    WHERE file_name = ? AND status = 'success'
    ORDER BY run_id DESC
), 0)
"""


def connect():
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        "SERVER=tcp:127.0.0.1,1433;DATABASE=NYCTaxi;"
        f"UID=sa;PWD={os.environ['MSSQL_SA_PASSWORD']};TrustServerCertificate=yes;"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", choices=["yellow", "green"], required=True)
    ap.add_argument("--rows", type=int, default=30000)
    args = ap.parse_args()

    table = f"{args.table}_trip"
    cfg = COLUMNS[table]
    file_name = cfg["file"]

    conn = connect()
    cur = conn.cursor()

    # 1. where did the last successful run stop?
    offset = cur.execute(NEXT_OFFSET_SQL, file_name).fetchval()

    # 2. read the file and take the next slice by position
    df = pd.read_parquet(HOLDOUT / file_name, columns=list(cfg["map"]))
    batch = df.iloc[offset: offset + args.rows].rename(columns=cfg["map"])
    if batch.empty:
        print(f"{file_name}: fully simulated ({offset:,} rows). Nothing to insert.")
        return

    for col in INT_COLS & set(batch.columns):
        batch[col] = batch[col].astype("Int64")       # 1.0 -> 1, NaN stays null
    batch = batch.astype(object).where(batch.notna(), None)

    # 3. log the run as 'running' (committed on its own, so a crash still leaves a trace)
    run_id = cur.execute(
        "INSERT INTO etl.sim_progress (table_name, file_name, start_offset) "
        "OUTPUT inserted.run_id VALUES (?, ?, ?)",
        table, file_name, offset,
    ).fetchval()
    conn.commit()

    # 4. insert trips + mark success in one transaction
    try:
        before = cur.execute(f"SELECT ISNULL(MAX(trip_id), 0) FROM trips.{table}").fetchval()

        cols = list(batch.columns)
        sql = (f"INSERT INTO trips.{table} ({', '.join(cols)}) "
               f"VALUES ({', '.join('?' * len(cols))})")
        cur.fast_executemany = True
        cur.executemany(sql, batch.values.tolist())
        

        min_id, max_id = cur.execute(
            f"SELECT MIN(trip_id), MAX(trip_id) FROM trips.{table} WHERE trip_id > ?", before
        ).fetchone()
        cur.execute(
            "UPDATE etl.sim_progress SET rows_inserted = ?, min_trip_id = ?, max_trip_id = ?, "
            "finished_at = SYSUTCDATETIME(), status = 'success' WHERE run_id = ?",
            len(batch), min_id, max_id, run_id,
        )
        conn.commit()
        print(f"run {run_id}: {len(batch):,} rows into trips.{table} "
              f"(offset {offset:,}, trip_id {min_id}..{max_id})")
    except Exception:
        conn.rollback()
        cur.execute(
            "UPDATE etl.sim_progress SET finished_at = SYSUTCDATETIME(), status = 'failed' "
            "WHERE run_id = ?", run_id,
        )
        conn.commit()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
