from pathlib import Path
import re
import pandas as pd
import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parent.parent   # project root
RAW_DIR = ROOT / "data" / "raw"
OUT_FILE = ROOT / "data" / "source_row_counts.csv"

# e.g. yellow_tripdata_2025-01.parquet
pattern = re.compile(r"(yellow|green)_tripdata_(\d{4})-(\d{2})\.parquet")

rows = []
for f in sorted(RAW_DIR.glob("*.parquet")):
    m = pattern.match(f.name)
    if not m:
        continue
    cab_type, year, month = m.groups()
    rows.append({
        "cab_type": cab_type,
        "year": int(year),
        "month": int(month),
        "row_count": pq.ParquetFile(f).metadata.num_rows,  # metadata only, no data read
    })

df = pd.DataFrame(rows)
df.to_csv(OUT_FILE, index=False)

print(df.groupby("cab_type")["row_count"].sum())     # grand totals to match SQL
print(f"Saved {len(df)} files -> {OUT_FILE}")   