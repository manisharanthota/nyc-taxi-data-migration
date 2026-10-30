/* =========================================================
   Step 7: Distributions  (DB: NYCTaxi, SQL Server 2022)
   APPROX_PERCENTILE_CONT is a 2022 feature: fast percentiles
   on huge tables (exact PERCENTILE_CONT would sort 78M rows).
   ========================================================= */
USE NYCTaxi;
GO

/* ---------- 7a. Numeric profile (yellow), one scan ---------- */
SELECT 'yellow' AS cab_type, v.column_name,
       MIN(v.val)  AS min_val,
       APPROX_PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY v.val) AS p01,
       APPROX_PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY v.val) AS p25,
       APPROX_PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY v.val) AS median,
       APPROX_PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY v.val) AS p75,
       APPROX_PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY v.val) AS p99,
       MAX(v.val)  AS max_val,
       CAST(AVG(v.val) AS DECIMAL(12,2)) AS avg_val
FROM trips.yellow_trip t
CROSS APPLY (VALUES
    ('trip_distance',   CAST(t.trip_distance AS FLOAT)),
    ('duration_min',    DATEDIFF(SECOND, t.pickup_datetime, t.dropoff_datetime) / 60.0),
    ('passenger_count', CAST(t.passenger_count AS FLOAT)),
    ('fare_amount',     CAST(t.fare_amount AS FLOAT)),
    ('tip_amount',      CAST(t.tip_amount AS FLOAT)),
    ('total_amount',    CAST(t.total_amount AS FLOAT))
) v(column_name, val)
WHERE v.val IS NOT NULL
GROUP BY v.column_name
ORDER BY v.column_name;
GO

/* ---------- 7b. Numeric profile (green) ---------- */
SELECT 'green' AS cab_type, v.column_name,
       MIN(v.val)  AS min_val,
       APPROX_PERCENTILE_CONT(0.01) WITHIN GROUP (ORDER BY v.val) AS p01,
       APPROX_PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY v.val) AS p25,
       APPROX_PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY v.val) AS median,
       APPROX_PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY v.val) AS p75,
       APPROX_PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY v.val) AS p99,
       MAX(v.val)  AS max_val,
       CAST(AVG(v.val) AS DECIMAL(12,2)) AS avg_val
FROM trips.green_trip t
CROSS APPLY (VALUES
    ('trip_distance',   CAST(t.trip_distance AS FLOAT)),
    ('duration_min',    DATEDIFF(SECOND, t.pickup_datetime, t.dropoff_datetime) / 60.0),
    ('passenger_count', CAST(t.passenger_count AS FLOAT)),
    ('fare_amount',     CAST(t.fare_amount AS FLOAT)),
    ('tip_amount',      CAST(t.tip_amount AS FLOAT)),
    ('total_amount',    CAST(t.total_amount AS FLOAT))
) v(column_name, val)
WHERE v.val IS NOT NULL
GROUP BY v.column_name
ORDER BY v.column_name;
GO

/* ---------- 7c. Distance histogram (yellow) ---------- */
SELECT CASE
         WHEN trip_distance IS NULL THEN '0. null'
         WHEN trip_distance <= 0    THEN '1. <= 0'
         WHEN trip_distance <  1    THEN '2. 0-1 mi'
         WHEN trip_distance <  3    THEN '3. 1-3 mi'
         WHEN trip_distance <  10   THEN '4. 3-10 mi'
         WHEN trip_distance <  30   THEN '5. 10-30 mi'
         WHEN trip_distance <  100  THEN '6. 30-100 mi'
         ELSE                            '7. 100+ mi' END AS distance_bucket,
       COUNT_BIG(*) AS trips,
       CAST(100.0 * COUNT_BIG(*) / SUM(COUNT_BIG(*)) OVER () AS DECIMAL(6,2)) AS pct
FROM trips.yellow_trip
GROUP BY CASE
         WHEN trip_distance IS NULL THEN '0. null'
         WHEN trip_distance <= 0    THEN '1. <= 0'
         WHEN trip_distance <  1    THEN '2. 0-1 mi'
         WHEN trip_distance <  3    THEN '3. 1-3 mi'
         WHEN trip_distance <  10   THEN '4. 3-10 mi'
         WHEN trip_distance <  30   THEN '5. 10-30 mi'
         WHEN trip_distance <  100  THEN '6. 30-100 mi'
         ELSE                            '7. 100+ mi' END
ORDER BY distance_bucket;
GO

/* ---------- 7d. Time patterns: trips per day (spot outages / gaps) ---------- */
SELECT CAST(pickup_datetime AS DATE) AS trip_date, COUNT_BIG(*) AS trips
FROM trips.yellow_trip
WHERE pickup_datetime >= '2025-01-01' AND pickup_datetime < '2026-10-01'
GROUP BY CAST(pickup_datetime AS DATE)
ORDER BY trip_date;
GO
-- Paste into Excel and make a line chart: dips = holidays/storms/missing data

/* ---------- 7e. Tip by payment type (cash tips are not recorded) ---------- */
SELECT t.payment_type_id, r.description,
       COUNT_BIG(*) AS trips,
       CAST(AVG(CAST(t.tip_amount AS FLOAT)) AS DECIMAL(8,2)) AS avg_tip,
       CAST(100.0 * SUM(CASE WHEN t.tip_amount > 0 THEN 1 ELSE 0 END) / COUNT_BIG(*) AS DECIMAL(6,2)) AS pct_with_tip
FROM trips.yellow_trip t
LEFT JOIN ref.payment_type r ON r.payment_type_id = t.payment_type_id
GROUP BY t.payment_type_id, r.description
ORDER BY trips DESC;
GO
