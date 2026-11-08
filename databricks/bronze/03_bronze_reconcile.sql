-- 03_bronze_reconcile.sql: reconcile bronze with SQL Server, per load.
-- Part 1 runs in Databricks, Part 2 in SQL Server (NYCTaxi). Change table name for green.

-- =========================== Part 1: Databricks ===========================
-- A. Rows per load (FULL vs each incremental load_id)
SELECT
  CASE WHEN _source_file LIKE '%/incremental/%'
       THEN regexp_extract(_source_file, 'load_id=([^/]+)', 1)
       ELSE 'FULL' END               AS load_id,
  COUNT(*)                           AS row_count,
  COUNT(DISTINCT _source_file)       AS file_count,
  MIN(_ingested_at)                  AS first_ingested
FROM nyctaxi.bronze.yellow_trip
GROUP BY 1
ORDER BY first_ingested;

-- D. Duplicates (orphan files from failed incremental runs show up here)
SELECT
  COUNT(*)                           AS total_rows,
  COUNT(DISTINCT trip_id)            AS distinct_trips,
  COUNT(*) - COUNT(DISTINCT trip_id) AS duplicate_rows
FROM nyctaxi.bronze.yellow_trip;

-- D2. If duplicates > 0: which loads they come from
WITH d AS (
  SELECT trip_id FROM nyctaxi.bronze.yellow_trip
  GROUP BY trip_id HAVING COUNT(*) > 1)
SELECT regexp_extract(_source_file, 'load_id=([^/]+)', 1) AS load_id, COUNT(*) AS rows
FROM nyctaxi.bronze.yellow_trip
WHERE trip_id IN (SELECT trip_id FROM d)
GROUP BY 1;

-- =========================== Part 2: SQL Server ===========================
/*
DECLARE @t VARCHAR(50) = 'trips.yellow_trip';

-- B1. Full load: latest success per month, summed  (= A 'FULL')
WITH last_ok AS (
  SELECT year_month, rows_copied,
         ROW_NUMBER() OVER (PARTITION BY year_month ORDER BY ended_at DESC) AS rn
  FROM etl.adf_load_log
  WHERE table_name = @t AND status = 'success' AND year_month <> 'INCR')
SELECT 'FULL' AS load_id, SUM(rows_copied) AS rows_copied, COUNT(*) AS months
FROM last_ok WHERE rn = 1;

-- B2. Incremental runs (pipeline_run_id = load_id folder)  (= A per load_id)
SELECT pipeline_run_id AS load_id, status, rows_copied, started_at
FROM etl.adf_load_log
WHERE table_name = @t AND year_month = 'INCR'
ORDER BY started_at;

-- B3. Current source total  (= D distinct_trips)
SELECT COUNT(*) AS source_rows FROM trips.yellow_trip;
*/
