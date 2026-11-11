-- Databricks notebook source
-- 3.4 Gold tables (full rebuild; rerunnable)
-- Prereq: ADF pl_load_ref has copied ref.* to bronze/nyctaxi/ref_<table>/

-- COMMAND ----------

-- Zone dimension (265 rows)
CREATE OR REPLACE TABLE nyctaxi.gold.dim_zone AS
SELECT CAST(location_id AS INT) AS location_id,
       borough, zone, service_zone
FROM read_files(
  'abfss://bronze@stnyctaxidev01.dfs.core.windows.net/nyctaxi/ref_taxi_zone/',
  format => 'parquet');

-- COMMAND ----------

-- Union of yellow + green silver trips (view: stores nothing)
CREATE OR REPLACE VIEW nyctaxi.gold.v_trip AS
SELECT 'yellow' AS taxi_type, trip_id, pickup_date, pu_location_id, pricing_type,
       trip_distance, trip_duration_min, total_amount,
       COALESCE(is_reversal, false) AS is_reversal,
       COALESCE(is_adjustment, false) AS is_adjustment
FROM nyctaxi.silver.yellow_trip
UNION ALL
SELECT 'green', trip_id, pickup_date, pu_location_id, pricing_type,
       trip_distance, trip_duration_min, total_amount,
       COALESCE(is_reversal, false), COALESCE(is_adjustment, false)
FROM nyctaxi.silver.green_trip;

-- COMMAND ----------

-- Daily summary: date x taxi_type x pricing_type
-- Tip: add WHERE taxi_type = 'green' to test cheaply
CREATE OR REPLACE TABLE nyctaxi.gold.daily_trip_summary AS
SELECT pickup_date, taxi_type, pricing_type,
       COUNT_IF(NOT is_reversal AND NOT is_adjustment) AS trip_count,
       COUNT_IF(is_adjustment AND NOT is_reversal)     AS adjustment_count,
       COUNT_IF(is_reversal)                           AS reversal_count,
       SUM(CASE WHEN NOT is_reversal THEN total_amount END) AS total_revenue,
       ROUND(AVG(CASE WHEN NOT is_reversal AND NOT is_adjustment THEN trip_distance END), 2)     AS avg_distance,
       ROUND(AVG(CASE WHEN NOT is_reversal AND NOT is_adjustment THEN trip_duration_min END), 2) AS avg_duration_min
FROM nyctaxi.gold.v_trip
GROUP BY pickup_date, taxi_type, pricing_type;

-- COMMAND ----------

-- Daily pickups by zone: date x taxi_type x pickup zone (real trips only)
CREATE OR REPLACE TABLE nyctaxi.gold.daily_zone_pickups AS
SELECT t.pickup_date, t.taxi_type, t.pu_location_id,
       COALESCE(z.borough, 'Unknown') AS borough,
       COALESCE(z.zone, 'Unknown')    AS zone,
       COUNT(*)            AS trip_count,
       SUM(t.total_amount) AS total_revenue
FROM nyctaxi.gold.v_trip t
LEFT JOIN nyctaxi.gold.dim_zone z ON z.location_id = t.pu_location_id
WHERE NOT t.is_reversal AND NOT t.is_adjustment
GROUP BY ALL;
