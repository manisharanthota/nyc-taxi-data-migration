/* ---------- 3a. Yellow: null count + % per column ---------- */
WITH agg AS (
    SELECT
        COUNT_BIG(*) AS total_rows,
        SUM(CASE WHEN passenger_count       IS NULL THEN 1 ELSE 0 END) AS passenger_count,
        SUM(CASE WHEN trip_distance         IS NULL THEN 1 ELSE 0 END) AS trip_distance,
        SUM(CASE WHEN rate_code_id          IS NULL THEN 1 ELSE 0 END) AS rate_code_id,
        SUM(CASE WHEN store_and_fwd_flag    IS NULL THEN 1 ELSE 0 END) AS store_and_fwd_flag,
        SUM(CASE WHEN payment_type_id       IS NULL THEN 1 ELSE 0 END) AS payment_type_id,
        SUM(CASE WHEN fare_amount           IS NULL THEN 1 ELSE 0 END) AS fare_amount,
        SUM(CASE WHEN extra                 IS NULL THEN 1 ELSE 0 END) AS extra,
        SUM(CASE WHEN mta_tax               IS NULL THEN 1 ELSE 0 END) AS mta_tax,
        SUM(CASE WHEN tip_amount            IS NULL THEN 1 ELSE 0 END) AS tip_amount,
        SUM(CASE WHEN tolls_amount          IS NULL THEN 1 ELSE 0 END) AS tolls_amount,
        SUM(CASE WHEN improvement_surcharge IS NULL THEN 1 ELSE 0 END) AS improvement_surcharge,
        SUM(CASE WHEN total_amount          IS NULL THEN 1 ELSE 0 END) AS total_amount,
        SUM(CASE WHEN congestion_surcharge  IS NULL THEN 1 ELSE 0 END) AS congestion_surcharge,
        SUM(CASE WHEN airport_fee           IS NULL THEN 1 ELSE 0 END) AS airport_fee,
        SUM(CASE WHEN cbd_congestion_fee    IS NULL THEN 1 ELSE 0 END) AS cbd_congestion_fee
    FROM trips.yellow_trip
)
SELECT 'yellow' AS cab_type, v.column_name, v.null_count,
       CAST(100.0 * v.null_count / a.total_rows AS DECIMAL(6,2)) AS null_pct
FROM agg a
CROSS APPLY (VALUES
    ('passenger_count', a.passenger_count), ('trip_distance', a.trip_distance),
    ('rate_code_id', a.rate_code_id), ('store_and_fwd_flag', a.store_and_fwd_flag),
    ('payment_type_id', a.payment_type_id), ('fare_amount', a.fare_amount),
    ('extra', a.extra), ('mta_tax', a.mta_tax), ('tip_amount', a.tip_amount),
    ('tolls_amount', a.tolls_amount), ('improvement_surcharge', a.improvement_surcharge),
    ('total_amount', a.total_amount), ('congestion_surcharge', a.congestion_surcharge),
    ('airport_fee', a.airport_fee), ('cbd_congestion_fee', a.cbd_congestion_fee)
) v(column_name, null_count)
ORDER BY v.null_count DESC;
GO

/* ---------- 3b. Green: null count + % per column ---------- */
WITH agg AS (
    SELECT
        COUNT_BIG(*) AS total_rows,
        SUM(CASE WHEN store_and_fwd_flag    IS NULL THEN 1 ELSE 0 END) AS store_and_fwd_flag,
        SUM(CASE WHEN rate_code_id          IS NULL THEN 1 ELSE 0 END) AS rate_code_id,
        SUM(CASE WHEN passenger_count       IS NULL THEN 1 ELSE 0 END) AS passenger_count,
        SUM(CASE WHEN trip_distance         IS NULL THEN 1 ELSE 0 END) AS trip_distance,
        SUM(CASE WHEN fare_amount           IS NULL THEN 1 ELSE 0 END) AS fare_amount,
        SUM(CASE WHEN extra                 IS NULL THEN 1 ELSE 0 END) AS extra,
        SUM(CASE WHEN mta_tax               IS NULL THEN 1 ELSE 0 END) AS mta_tax,
        SUM(CASE WHEN tip_amount            IS NULL THEN 1 ELSE 0 END) AS tip_amount,
        SUM(CASE WHEN tolls_amount          IS NULL THEN 1 ELSE 0 END) AS tolls_amount,
        SUM(CASE WHEN ehail_fee             IS NULL THEN 1 ELSE 0 END) AS ehail_fee,
        SUM(CASE WHEN improvement_surcharge IS NULL THEN 1 ELSE 0 END) AS improvement_surcharge,
        SUM(CASE WHEN total_amount          IS NULL THEN 1 ELSE 0 END) AS total_amount,
        SUM(CASE WHEN payment_type_id       IS NULL THEN 1 ELSE 0 END) AS payment_type_id,
        SUM(CASE WHEN trip_type_id          IS NULL THEN 1 ELSE 0 END) AS trip_type_id,
        SUM(CASE WHEN congestion_surcharge  IS NULL THEN 1 ELSE 0 END) AS congestion_surcharge,
        SUM(CASE WHEN cbd_congestion_fee    IS NULL THEN 1 ELSE 0 END) AS cbd_congestion_fee
    FROM trips.green_trip
)
SELECT 'green' AS cab_type, v.column_name, v.null_count,
       CAST(100.0 * v.null_count / a.total_rows AS DECIMAL(6,2)) AS null_pct
FROM agg a
CROSS APPLY (VALUES
    ('store_and_fwd_flag', a.store_and_fwd_flag), ('rate_code_id', a.rate_code_id),
    ('passenger_count', a.passenger_count), ('trip_distance', a.trip_distance),
    ('fare_amount', a.fare_amount), ('extra', a.extra), ('mta_tax', a.mta_tax),
    ('tip_amount', a.tip_amount), ('tolls_amount', a.tolls_amount),
    ('ehail_fee', a.ehail_fee), ('improvement_surcharge', a.improvement_surcharge),
    ('total_amount', a.total_amount), ('payment_type_id', a.payment_type_id),
    ('trip_type_id', a.trip_type_id), ('congestion_surcharge', a.congestion_surcharge),
    ('cbd_congestion_fee', a.cbd_congestion_fee)
) v(column_name, null_count)
ORDER BY v.null_count DESC;
GO

/* ---------- 3c. Do nulls cluster in the same rows? ----------
   If all_four_null ~= passenger_count_null, they are the same trips. */
SELECT 'yellow' AS cab_type,
    SUM(CASE WHEN passenger_count IS NULL THEN 1 ELSE 0 END) AS passenger_count_null,
    SUM(CASE WHEN passenger_count IS NULL AND rate_code_id IS NULL
              AND store_and_fwd_flag IS NULL AND congestion_surcharge IS NULL
             THEN 1 ELSE 0 END) AS all_four_null
FROM trips.yellow_trip
UNION ALL
SELECT 'green',
    SUM(CASE WHEN passenger_count IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN passenger_count IS NULL AND rate_code_id IS NULL
              AND store_and_fwd_flag IS NULL AND congestion_surcharge IS NULL
             THEN 1 ELSE 0 END)
FROM trips.green_trip;
GO

/* ---------- 3d. Null rows by month and vendor (where do they come from?) ---------- */
SELECT YEAR(pickup_datetime) AS yr, MONTH(pickup_datetime) AS mth, vendor_id,
       COUNT_BIG(*) AS null_rows
FROM trips.yellow_trip
WHERE passenger_count IS NULL
GROUP BY YEAR(pickup_datetime), MONTH(pickup_datetime), vendor_id
ORDER BY yr, mth, vendor_id;
GO
-- Repeat with trips.green_trip

/* ---------- 3e. "Fake nulls" (values that mean missing) ---------- */
SELECT 'yellow' AS cab_type,
    SUM(CASE WHEN passenger_count = 0 THEN 1 ELSE 0 END) AS passenger_zero,
    SUM(CASE WHEN trip_distance   = 0 THEN 1 ELSE 0 END) AS distance_zero,
    SUM(CASE WHEN rate_code_id    = 99 THEN 1 ELSE 0 END) AS rate_code_99_unknown,
    SUM(CASE WHEN payment_type_id = 0 THEN 1 ELSE 0 END) AS payment_type_0,
    SUM(CASE WHEN pu_location_id IN (264,265) THEN 1 ELSE 0 END) AS pu_zone_unknown
FROM trips.yellow_trip
UNION ALL
SELECT 'green',
    SUM(CASE WHEN passenger_count = 0 THEN 1 ELSE 0 END),
    SUM(CASE WHEN trip_distance   = 0 THEN 1 ELSE 0 END),
    SUM(CASE WHEN rate_code_id    = 99 THEN 1 ELSE 0 END),
    SUM(CASE WHEN payment_type_id = 0 THEN 1 ELSE 0 END),
    SUM(CASE WHEN pu_location_id IN (264,265) THEN 1 ELSE 0 END)
FROM trips.green_trip;
GO