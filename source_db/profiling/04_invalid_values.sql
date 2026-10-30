/* =========================================================
   Step 4: Invalid / suspicious values  (DB: NYCTaxi)
   One scan per table. Run blocks one at a time.
   Thresholds are starting points; adjust after you see results.
   ========================================================= */
USE NYCTaxi;
GO
 
/* ---------- 4a. Yellow: count + % per rule ---------- */
WITH t AS (
    SELECT *, DATEDIFF(SECOND, pickup_datetime, dropoff_datetime) AS dur_sec
    FROM trips.yellow_trip
), agg AS (
    SELECT
        COUNT_BIG(*) AS total_rows,
        SUM(CASE WHEN fare_amount  < 0 THEN 1 ELSE 0 END) AS negative_fare,
        SUM(CASE WHEN total_amount < 0 THEN 1 ELSE 0 END) AS negative_total,
        SUM(CASE WHEN total_amount = 0 THEN 1 ELSE 0 END) AS zero_total,
        SUM(CASE WHEN fare_amount  > 1000 THEN 1 ELSE 0 END) AS fare_over_1000,
        SUM(CASE WHEN trip_distance > 100 THEN 1 ELSE 0 END) AS distance_over_100mi,
        SUM(CASE WHEN dur_sec < 0 THEN 1 ELSE 0 END) AS dropoff_before_pickup,
        SUM(CASE WHEN dur_sec = 0 THEN 1 ELSE 0 END) AS zero_duration,
        SUM(CASE WHEN dur_sec > 86400 THEN 1 ELSE 0 END) AS duration_over_24h,
        SUM(CASE WHEN passenger_count > 6 THEN 1 ELSE 0 END) AS passengers_over_6,
        SUM(CASE WHEN tip_amount < 0 THEN 1 ELSE 0 END) AS negative_tip,
        SUM(CASE WHEN dur_sec > 0 AND trip_distance / (dur_sec / 3600.0) > 100
                 THEN 1 ELSE 0 END) AS speed_over_100mph
    FROM t
)
SELECT 'yellow' AS cab_type, v.rule_name, v.bad_rows,
       CAST(100.0 * v.bad_rows / a.total_rows AS DECIMAL(6,3)) AS bad_pct
FROM agg a
CROSS APPLY (VALUES
    ('negative_fare', a.negative_fare), ('negative_total', a.negative_total),
    ('zero_total', a.zero_total), ('fare_over_1000', a.fare_over_1000),
    ('distance_over_100mi', a.distance_over_100mi),
    ('dropoff_before_pickup', a.dropoff_before_pickup),
    ('zero_duration', a.zero_duration), ('duration_over_24h', a.duration_over_24h),
    ('passengers_over_6', a.passengers_over_6), ('negative_tip', a.negative_tip),
    ('speed_over_100mph', a.speed_over_100mph)
) v(rule_name, bad_rows)
ORDER BY v.bad_rows DESC;
GO
 
/* ---------- 4b. Green: same rules ---------- */
WITH t AS (
    SELECT *, DATEDIFF(SECOND, pickup_datetime, dropoff_datetime) AS dur_sec
    FROM trips.green_trip
), agg AS (
    SELECT
        COUNT_BIG(*) AS total_rows,
        SUM(CASE WHEN fare_amount  < 0 THEN 1 ELSE 0 END) AS negative_fare,
        SUM(CASE WHEN total_amount < 0 THEN 1 ELSE 0 END) AS negative_total,
        SUM(CASE WHEN total_amount = 0 THEN 1 ELSE 0 END) AS zero_total,
        SUM(CASE WHEN fare_amount  > 1000 THEN 1 ELSE 0 END) AS fare_over_1000,
        SUM(CASE WHEN trip_distance > 100 THEN 1 ELSE 0 END) AS distance_over_100mi,
        SUM(CASE WHEN dur_sec < 0 THEN 1 ELSE 0 END) AS dropoff_before_pickup,
        SUM(CASE WHEN dur_sec = 0 THEN 1 ELSE 0 END) AS zero_duration,
        SUM(CASE WHEN dur_sec > 86400 THEN 1 ELSE 0 END) AS duration_over_24h,
        SUM(CASE WHEN passenger_count > 6 THEN 1 ELSE 0 END) AS passengers_over_6,
        SUM(CASE WHEN tip_amount < 0 THEN 1 ELSE 0 END) AS negative_tip,
        SUM(CASE WHEN dur_sec > 0 AND trip_distance / (dur_sec / 3600.0) > 100
                 THEN 1 ELSE 0 END) AS speed_over_100mph
    FROM t
)
SELECT 'green' AS cab_type, v.rule_name, v.bad_rows,
       CAST(100.0 * v.bad_rows / a.total_rows AS DECIMAL(6,3)) AS bad_pct
FROM agg a
CROSS APPLY (VALUES
    ('negative_fare', a.negative_fare), ('negative_total', a.negative_total),
    ('zero_total', a.zero_total), ('fare_over_1000', a.fare_over_1000),
    ('distance_over_100mi', a.distance_over_100mi),
    ('dropoff_before_pickup', a.dropoff_before_pickup),
    ('zero_duration', a.zero_duration), ('duration_over_24h', a.duration_over_24h),
    ('passengers_over_6', a.passengers_over_6), ('negative_tip', a.negative_tip),
    ('speed_over_100mph', a.speed_over_100mph)
) v(rule_name, bad_rows)
ORDER BY v.bad_rows DESC;
GO
 
/* ---------- 4c. Are negative amounts refunds/voids? ----------
   Negative rows by payment type (3 = No charge, 4 = Dispute, 6 = Voided). */
SELECT 'yellow' AS cab_type, payment_type_id, COUNT_BIG(*) AS negative_rows
FROM trips.yellow_trip WHERE total_amount < 0
GROUP BY payment_type_id
UNION ALL
SELECT 'green', payment_type_id, COUNT_BIG(*)
FROM trips.green_trip WHERE total_amount < 0
GROUP BY payment_type_id
ORDER BY cab_type, negative_rows DESC;
GO
 
/* ---------- 4d. Look at a few extreme rows (sanity check) ---------- */
SELECT TOP 20 trip_id, vendor_id, pickup_datetime, dropoff_datetime,
       trip_distance, fare_amount, total_amount, payment_type_id
FROM trips.yellow_trip
WHERE trip_distance > 100 OR fare_amount > 1000
ORDER BY trip_distance DESC;
GO
 