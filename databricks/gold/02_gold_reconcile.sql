-- Databricks notebook source
-- 3.4 Gold reconcile: every diff must be 0 for each taxi_type

-- COMMAND ----------

WITH s AS (  -- silver truth
  SELECT taxi_type, COUNT(*) AS rows,
         COUNT_IF(NOT is_reversal AND NOT is_adjustment) AS trips,
         SUM(CASE WHEN NOT is_reversal THEN total_amount END) AS revenue
  FROM nyctaxi.gold.v_trip GROUP BY taxi_type),
d AS (
  SELECT taxi_type, SUM(trip_count + adjustment_count + reversal_count) AS rows,
         SUM(trip_count) AS trips, SUM(total_revenue) AS revenue
  FROM nyctaxi.gold.daily_trip_summary GROUP BY taxi_type),
z AS (
  SELECT taxi_type, SUM(trip_count) AS trips
  FROM nyctaxi.gold.daily_zone_pickups GROUP BY taxi_type)
SELECT s.taxi_type,
       s.rows    - d.rows    AS diff_rows_summary,
       s.trips   - d.trips   AS diff_trips_summary,
       s.revenue - d.revenue AS diff_revenue_summary,
       s.trips   - z.trips   AS diff_trips_zone
FROM s JOIN d USING (taxi_type) JOIN z USING (taxi_type);
