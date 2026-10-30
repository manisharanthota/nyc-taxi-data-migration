# NYC Taxi Data Migration (on-prem → Azure)

Simulates a real on-prem → cloud migration using NYC TLC yellow + green taxi trips.

**Stack:** SQL Server 2022 (Docker, "on-prem") → Azure Data Factory (self-hosted IR) → ADLS Gen2 → Databricks (Delta, bronze/silver/gold)

## Status
| Phase | Status |
|---|---|
| 1. Source DB (schema, load, profiling) | ✅ Done (2025-01 → 2026-08; 2024 pending) |
| Pre-migration checklist | 🔄 Control totals ✅ · created_at index ✅ · read-only login ✅ · insert simulator ⏳ · source assessment ⏳ |
| 2. Migration (ADF full + incremental) | ⏳ |
| 3. Databricks medallion | ⏳ |
| 4. Validation | ⏳ |
| 5. Orchestration + docs | ⏳ |

## Repo layout
```
source_db/
  docker-compose.yml     SQL Server container (MSSQLServer, port 1433)
  .env.example           copy to .env and set passwords
  schema.sql             ref + trips schemas, tables, created_at indexes
  seed_lookups.sql       lookup codes (run once after schema.sql)
  control_totals.sql     audit.control_totals snapshot (migration answer key)
  security.sql           adf_reader read-only login for ADF
  profiling/01-08_*.sql  data profiling steps
scripts/
  download_trips.ps1     download TLC parquet → data/raw/
  load_parquet.py        load parquet → SQL Server
  source_counts.py       row counts from parquet metadata
data/                    (gitignored) raw parquet + CSVs
```

## Setup (run order)
1. `cp source_db/.env.example source_db/.env` and set passwords
2. `docker compose -f source_db/docker-compose.yml up -d`
3. Create DB `NYCTaxi`, run `schema.sql`, then `seed_lookups.sql`
4. `scripts/download_trips.ps1`, then `python scripts/load_parquet.py`
5. Run `control_totals.sql`, then `security.sql`

> `schema.sql` is idempotent: it only creates missing objects and never drops data.

Connect: `tcp:127.0.0.1,1433` · DB `NYCTaxi` · logins `sa` (admin), `adf_reader` (read-only)

## Source assessment (from profiling)
- Volume: yellow ~78.4M, green ~928K rows (Jan 2025 – Aug 2026); parquet counts = SQL counts exactly
- Stray dates (2001–2009, late 2024): ~30 rows → quarantine in silver
- Flex Fare (payment_type 0): ~25% of yellow; trust `total_amount` only
- Reversal pairs (~866K yellow) flagged, not deleted
- Source stays raw; all cleaning happens in silver

Full findings: Notion "NYC Taxi Data Quality Findings & Silver Fixes".

## Key design decisions
- Incremental loads use a `created_at` watermark (indexed: 1.44M → 4 logical reads)
- ADF connects as `adf_reader` (db_datareader only)
- Validation compares every layer against `audit.control_totals`
