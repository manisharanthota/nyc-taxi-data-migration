-- Databricks notebook source
-- 03_silver_reconcile: every distinct bronze trip lands in exactly one place (silver OR quarantine).

-- 1. Counts: expect bronze_distinct = silver + quarantine
SELECT 'green' AS t,
  (SELECT COUNT(DISTINCT trip_id) FROM nyctaxi.bronze.green_trip)  AS bronze_distinct,
  (SELECT COUNT(*) FROM nyctaxi.silver.green_trip)                  AS silver,
  (SELECT COUNT(*) FROM nyctaxi.silver.trip_quarantine WHERE taxi_type = 'green') AS quarantine
UNION ALL
SELECT 'yellow',
  (SELECT COUNT(DISTINCT trip_id) FROM nyctaxi.bronze.yellow_trip),
  (SELECT COUNT(*) FROM nyctaxi.silver.yellow_trip),
  (SELECT COUNT(*) FROM nyctaxi.silver.trip_quarantine WHERE taxi_type = 'yellow');

-- COMMAND ----------

-- 2. No duplicates, no row in both silver and quarantine: expect all 0
SELECT 'yellow dup' AS chk, COUNT(*) AS n FROM (SELECT trip_id FROM nyctaxi.silver.yellow_trip GROUP BY trip_id HAVING COUNT(*) > 1)
UNION ALL
SELECT 'green dup', COUNT(*) FROM (SELECT trip_id FROM nyctaxi.silver.green_trip GROUP BY trip_id HAVING COUNT(*) > 1)
UNION ALL
SELECT 'yellow in both', COUNT(*) FROM nyctaxi.silver.yellow_trip s
  JOIN nyctaxi.silver.trip_quarantine q ON q.taxi_type = 'yellow' AND q.trip_id = s.trip_id
UNION ALL
SELECT 'green in both', COUNT(*) FROM nyctaxi.silver.green_trip s
  JOIN nyctaxi.silver.trip_quarantine q ON q.taxi_type = 'green' AND q.trip_id = s.trip_id;

-- COMMAND ----------

-- 3. Breakdowns
SELECT taxi_type, reason, COUNT(*) AS n FROM nyctaxi.silver.trip_quarantine GROUP BY ALL ORDER BY ALL;

-- COMMAND ----------

SELECT 'green' AS t, pricing_type, is_reversal, is_adjustment, COUNT(*) AS n FROM nyctaxi.silver.green_trip GROUP BY ALL
UNION ALL
SELECT 'yellow', pricing_type, is_reversal, is_adjustment, COUNT(*) FROM nyctaxi.silver.yellow_trip GROUP BY ALL
ORDER BY ALL;
