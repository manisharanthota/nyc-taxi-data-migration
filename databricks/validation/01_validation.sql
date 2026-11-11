-- Databricks notebook source
-- 01_validation: end-to-end checks source (SQL Server) -> ADF -> bronze -> silver(+quarantine) -> gold.
-- Prereqs: 1) new snapshot in SQL Server (source_db/control_totals.sql INSERT)
--          2) ADF pl_load_audit (copies audit.control_totals + etl.adf_load_log to bronze)
-- Run: set t below ('green' or 'yellow'), run all cells. Every check must be PASS.

-- COMMAND ----------

-- Setup (idempotent)
CREATE SCHEMA IF NOT EXISTS nyctaxi.audit
  MANAGED LOCATION 'abfss://gold@stnyctaxidev01.dfs.core.windows.net/nyctaxi/audit';

-- Latest source snapshot only
CREATE OR REPLACE VIEW nyctaxi.audit.src_control_totals AS
WITH f AS (SELECT * FROM read_files('abfss://bronze@stnyctaxidev01.dfs.core.windows.net/nyctaxi/ref_audit_control_totals/'))
SELECT * FROM f WHERE captured_at = (SELECT MAX(captured_at) FROM f);

-- year_month is CHAR(7) in SQL Server: 'INCR' arrives padded, so trim
CREATE OR REPLACE VIEW nyctaxi.audit.src_adf_load_log AS
SELECT * EXCEPT (year_month), trim(year_month) AS year_month
FROM read_files('abfss://bronze@stnyctaxidev01.dfs.core.windows.net/nyctaxi/ref_etl_adf_load_log/');

CREATE TABLE IF NOT EXISTS nyctaxi.audit.validation_results (
  run_id STRING, checked_at TIMESTAMP, check_name STRING, taxi_type STRING,
  expected DECIMAL(20,2), actual DECIMAL(20,2), diff DECIMAL(20,2), status STRING);

-- Latest run per taxi type = sign-off report
CREATE OR REPLACE VIEW nyctaxi.audit.v_validation_summary AS
SELECT r.taxi_type, r.run_id, MIN(r.checked_at) AS run_at, COUNT(*) AS checks,
       COUNT_IF(r.status = 'FAIL') AS failed,
       IF(COUNT_IF(r.status = 'FAIL') = 0, 'PASS', 'FAIL') AS result
FROM nyctaxi.audit.validation_results r
JOIN (SELECT taxi_type, max_by(run_id, checked_at) AS run_id
      FROM nyctaxi.audit.validation_results GROUP BY taxi_type) l USING (taxi_type, run_id)
GROUP BY ALL;

-- COMMAND ----------

DECLARE OR REPLACE VARIABLE t STRING DEFAULT 'green';   -- 'green' | 'yellow'
DECLARE OR REPLACE VARIABLE run_id STRING DEFAULT uuid();

-- COMMAND ----------

-- Layer checks: rows + amount checksum
INSERT INTO nyctaxi.audit.validation_results
WITH src AS (
  SELECT SUM(row_count) AS rows, SUM(sum_total_amount) AS amt
  FROM nyctaxi.audit.src_control_totals WHERE table_name = 'trips.' || t || '_trip'),
b AS (  -- distinct trips, amount cast per row like SQL Server
  SELECT COUNT(*) AS rows, SUM(amt) AS amt FROM (
    SELECT trip_id, MAX(CAST(total_amount AS DECIMAL(18,2))) AS amt
    FROM IDENTIFIER('nyctaxi.bronze.' || t || '_trip') GROUP BY trip_id)),
s AS (SELECT COUNT(*) AS rows FROM IDENTIFIER('nyctaxi.silver.' || t || '_trip')),
q AS (SELECT COUNT(*) AS rows FROM nyctaxi.silver.trip_quarantine WHERE taxi_type = t),
g AS (SELECT SUM(trip_count + adjustment_count + reversal_count) AS rows
      FROM nyctaxi.gold.daily_trip_summary WHERE taxi_type = t),
c AS (
  SELECT 'source_vs_bronze_rows' AS check_name, src.rows AS expected, b.rows AS actual FROM src, b
  UNION ALL SELECT 'source_vs_bronze_amount', src.amt, b.amt FROM src, b
  UNION ALL SELECT 'bronze_vs_silver_quarantine_rows', b.rows, s.rows + q.rows FROM b, s, q
  UNION ALL SELECT 'silver_vs_gold_rows', s.rows, g.rows FROM s, g)
SELECT session.run_id, current_timestamp(), check_name, t, expected, actual,
       actual - expected, CASE WHEN actual = expected THEN 'PASS' ELSE 'FAIL' END
FROM c;

-- COMMAND ----------

-- Run-log checks: latest attempt per month/run succeeded; ADF rows copied = bronze rows
INSERT INTO nyctaxi.audit.validation_results
WITH l AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY year_month, IF(year_month = 'INCR', pipeline_run_id, '')
                               ORDER BY started_at DESC) AS rn
  FROM nyctaxi.audit.src_adf_load_log WHERE table_name = 'trips.' || t || '_trip'),
last_full AS (SELECT * FROM l WHERE year_month <> 'INCR' AND rn = 1),
ok_incr  AS (SELECT * FROM l WHERE year_month = 'INCR' AND status = 'success'),
adf AS (SELECT (SELECT SUM(rows_copied) FROM last_full WHERE status = 'success')
             + (SELECT COALESCE(SUM(rows_copied), 0) FROM ok_incr) AS rows),
b AS (SELECT COUNT(*) AS rows FROM IDENTIFIER('nyctaxi.bronze.' || t || '_trip')
      WHERE _source_file NOT LIKE '%/incremental/%'
         OR regexp_extract(_source_file, 'load_id=([^/]+)', 1) IN (SELECT pipeline_run_id FROM ok_incr)),
c AS (
  SELECT 'adf_months_not_success' AS check_name, 0 AS expected,
         (SELECT COUNT(*) FROM last_full WHERE status <> 'success') AS actual
  UNION ALL SELECT 'adf_stuck_running', 0, (SELECT COUNT(*) FROM l WHERE status = 'running' AND rn = 1)
  UNION ALL SELECT 'adf_rows_vs_bronze_rows', adf.rows, b.rows FROM adf, b)
SELECT session.run_id, current_timestamp(), check_name, t, expected, actual,
       actual - expected, CASE WHEN actual = expected THEN 'PASS' ELSE 'FAIL' END
FROM c;

-- COMMAND ----------

-- This run
SELECT check_name, expected, actual, diff, status
FROM nyctaxi.audit.validation_results WHERE run_id = session.run_id;

-- COMMAND ----------

SELECT * FROM nyctaxi.audit.v_validation_summary;
