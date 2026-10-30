/* =========================================================
   Step 5: Duplicates  (DB: NYCTaxi)
   No natural key in TLC data, so we test two definitions:
     - EXACT: every business column identical (true copies)
     - TRIP KEY: same vendor + pickup + dropoff + zones (same ride)
   GROUP BY on ~78M rows is heavy (uses tempdb). If it is slow,
   uncomment the month filter and run month by month.
   ========================================================= */
USE NYCTaxi;
GO

/* ---------- 5a. Exact duplicates (yellow) ---------- */
WITH grp AS (
    SELECT COUNT_BIG(*) AS cnt
    FROM trips.yellow_trip
    -- WHERE pickup_datetime >= '2025-01-01' AND pickup_datetime < '2025-02-01'
    GROUP BY vendor_id, pickup_datetime, dropoff_datetime, passenger_count,
             trip_distance, rate_code_id, store_and_fwd_flag, pu_location_id,
             do_location_id, payment_type_id, fare_amount, extra, mta_tax,
             tip_amount, tolls_amount, improvement_surcharge, total_amount,
             congestion_surcharge, airport_fee, cbd_congestion_fee
    HAVING COUNT_BIG(*) > 1
)
SELECT 'yellow' AS cab_type,
       COUNT_BIG(*)     AS dup_groups,
       SUM(cnt)         AS rows_in_dup_groups,
       SUM(cnt - 1)     AS extra_copies      -- rows you would remove
FROM grp;
GO

/* ---------- 5b. Exact duplicates (green) ---------- */
WITH grp AS (
    SELECT COUNT_BIG(*) AS cnt
    FROM trips.green_trip
    GROUP BY vendor_id, pickup_datetime, dropoff_datetime, store_and_fwd_flag,
             rate_code_id, pu_location_id, do_location_id, passenger_count,
             trip_distance, fare_amount, extra, mta_tax, tip_amount,
             tolls_amount, improvement_surcharge, total_amount,
             payment_type_id, trip_type_id, congestion_surcharge,
             cbd_congestion_fee
    HAVING COUNT_BIG(*) > 1
)
SELECT 'green' AS cab_type,
       COUNT_BIG(*) AS dup_groups, SUM(cnt) AS rows_in_dup_groups,
       SUM(cnt - 1) AS extra_copies
FROM grp;
GO

/* ---------- 5c. Same ride, different rows: what kind? (yellow) ----------
   reversal  = group contains a negative total (charge + cancel pair)
   identical = all amounts the same (copy, overlaps 5a)
   different = same ride, different amounts (corrections?)          */
WITH grp AS (
    SELECT vendor_id, pickup_datetime, dropoff_datetime,
           pu_location_id, do_location_id,
           COUNT_BIG(*)                 AS cnt,
           MIN(total_amount)            AS min_total,
           MAX(total_amount)            AS max_total
    FROM trips.yellow_trip
    GROUP BY vendor_id, pickup_datetime, dropoff_datetime,
             pu_location_id, do_location_id
    HAVING COUNT_BIG(*) > 1
)
SELECT CASE WHEN min_total < 0          THEN 'reversal'
            WHEN min_total = max_total  THEN 'identical'
            ELSE 'different' END        AS dup_kind,
       COUNT_BIG(*)                     AS groups,
       SUM(cnt)                         AS rows_involved
FROM grp
GROUP BY CASE WHEN min_total < 0          THEN 'reversal'
              WHEN min_total = max_total  THEN 'identical'
              ELSE 'different' END
ORDER BY rows_involved DESC;
GO
-- Repeat 5c with trips.green_trip

/* ---------- 5d. Look at a few example groups ---------- */
WITH grp AS (
    SELECT TOP 5 vendor_id, pickup_datetime, dropoff_datetime,
           pu_location_id, do_location_id
    FROM trips.yellow_trip
    WHERE pickup_datetime >= '2025-03-01' AND pickup_datetime < '2025-03-02'
    GROUP BY vendor_id, pickup_datetime, dropoff_datetime,
             pu_location_id, do_location_id
    HAVING COUNT_BIG(*) > 1
)
SELECT t.trip_id, t.vendor_id, t.pickup_datetime, t.dropoff_datetime,
       t.pu_location_id, t.do_location_id, t.trip_distance,
       t.fare_amount, t.total_amount, t.payment_type_id
FROM trips.yellow_trip t
JOIN grp g
  ON  t.vendor_id = g.vendor_id
  AND t.pickup_datetime = g.pickup_datetime
  AND t.dropoff_datetime = g.dropoff_datetime
  AND t.pu_location_id = g.pu_location_id
  AND t.do_location_id = g.do_location_id
ORDER BY t.pickup_datetime, t.trip_id;
GO
