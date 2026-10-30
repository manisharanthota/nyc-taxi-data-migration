/* =========================================================
   Step 8: Consistency (do columns agree with each other?)
   DB: NYCTaxi. Run blocks one at a time.
   ========================================================= */
USE NYCTaxi;
GO

/* ---------- 8a. Does total = sum of its parts? (yellow) ----------
   Grouped by payment type, because Flex Fare (0) may price differently. */
WITH t AS (
    SELECT payment_type_id,
           total_amount
           - ( ISNULL(fare_amount,0) + ISNULL(extra,0) + ISNULL(mta_tax,0)
             + ISNULL(tip_amount,0) + ISNULL(tolls_amount,0)
             + ISNULL(improvement_surcharge,0) + ISNULL(congestion_surcharge,0)
             + ISNULL(airport_fee,0) + ISNULL(cbd_congestion_fee,0) ) AS diff
    FROM trips.yellow_trip
)
SELECT payment_type_id,
       COUNT_BIG(*) AS trips,
       SUM(CASE WHEN ABS(diff) <= 0.01 THEN 1 ELSE 0 END) AS matches,
       SUM(CASE WHEN ABS(diff) >  0.01 AND ABS(diff) <= 1 THEN 1 ELSE 0 END) AS off_by_up_to_1,
       SUM(CASE WHEN ABS(diff) >  1 THEN 1 ELSE 0 END) AS off_by_more_than_1,
       CAST(100.0 * SUM(CASE WHEN ABS(diff) <= 0.01 THEN 1 ELSE 0 END) / COUNT_BIG(*) AS DECIMAL(6,2)) AS match_pct
FROM t
GROUP BY payment_type_id
ORDER BY trips DESC;
GO

/* ---------- 8b. Same check (green) ---------- */
WITH t AS (
    SELECT payment_type_id,
           total_amount
           - ( ISNULL(fare_amount,0) + ISNULL(extra,0) + ISNULL(mta_tax,0)
             + ISNULL(tip_amount,0) + ISNULL(tolls_amount,0) + ISNULL(ehail_fee,0)
             + ISNULL(improvement_surcharge,0) + ISNULL(congestion_surcharge,0)
             + ISNULL(cbd_congestion_fee,0) ) AS diff
    FROM trips.green_trip
)
SELECT payment_type_id,
       COUNT_BIG(*) AS trips,
       SUM(CASE WHEN ABS(diff) <= 0.01 THEN 1 ELSE 0 END) AS matches,
       SUM(CASE WHEN ABS(diff) >  0.01 AND ABS(diff) <= 1 THEN 1 ELSE 0 END) AS off_by_up_to_1,
       SUM(CASE WHEN ABS(diff) >  1 THEN 1 ELSE 0 END) AS off_by_more_than_1,
       CAST(100.0 * SUM(CASE WHEN ABS(diff) <= 0.01 THEN 1 ELSE 0 END) / COUNT_BIG(*) AS DECIMAL(6,2)) AS match_pct
FROM t
GROUP BY payment_type_id
ORDER BY trips DESC;
GO

/* ---------- 8c. Sign mismatch: fare < 0 but total >= 0 (the ~1.9M from Step 4) ---------- */
SELECT payment_type_id, vendor_id,
       COUNT_BIG(*) AS trips,
       CAST(AVG(CAST(fare_amount  AS FLOAT)) AS DECIMAL(10,2)) AS avg_fare,
       CAST(AVG(CAST(total_amount AS FLOAT)) AS DECIMAL(10,2)) AS avg_total
FROM trips.yellow_trip
WHERE fare_amount < 0 AND total_amount >= 0
GROUP BY payment_type_id, vendor_id
ORDER BY trips DESC;
GO
-- Look at 10 examples
SELECT TOP 10 trip_id, vendor_id, payment_type_id, fare_amount, extra, mta_tax,
       tip_amount, tolls_amount, improvement_surcharge, congestion_surcharge,
       airport_fee, cbd_congestion_fee, total_amount
FROM trips.yellow_trip
WHERE fare_amount < 0 AND total_amount >= 0;
GO

/* ---------- 8d. Business rules between columns (yellow) ----------
   Zones: 1 = Newark (EWR), 132 = JFK, 138 = LaGuardia             */
SELECT
    -- airport fee charged, but pickup not at JFK/LGA
    SUM(CASE WHEN airport_fee > 0 AND pu_location_id NOT IN (132, 138) THEN 1 ELSE 0 END) AS airport_fee_not_airport,
    -- JFK rate code, but neither end of the trip at JFK
    SUM(CASE WHEN rate_code_id = 2 AND 132 NOT IN (pu_location_id, do_location_id) THEN 1 ELSE 0 END) AS jfk_rate_not_jfk,
    -- Newark rate code, but neither end at Newark
    SUM(CASE WHEN rate_code_id = 3 AND 1 NOT IN (pu_location_id, do_location_id) THEN 1 ELSE 0 END) AS newark_rate_not_newark,
    -- CBD congestion fee charged before it started (2025-01-05)
    SUM(CASE WHEN cbd_congestion_fee > 0 AND pickup_datetime < '2025-01-05' THEN 1 ELSE 0 END) AS cbd_fee_before_start,
    -- tip recorded on a cash trip
    SUM(CASE WHEN payment_type_id = 2 AND tip_amount > 0 THEN 1 ELSE 0 END) AS cash_with_tip,
    -- more than 5 miles in under 1 minute
    SUM(CASE WHEN trip_distance > 5
              AND DATEDIFF(SECOND, pickup_datetime, dropoff_datetime) < 60 THEN 1 ELSE 0 END) AS far_but_under_1min
FROM trips.yellow_trip;
GO
