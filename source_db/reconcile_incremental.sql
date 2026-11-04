WITH seed AS (
    SELECT 'trips.yellow_trip' AS table_name, CAST('2026-10-30 23:52:30.032' AS DATETIME2(3)) AS seed_value
    UNION ALL
    SELECT 'trips.green_trip', CAST('2026-10-30 18:24:26.932' AS DATETIME2(3))
),
src AS (
    SELECT 'trips.yellow_trip' AS table_name, COUNT_BIG(*) AS source_rows
    FROM trips.yellow_trip y
    WHERE y.created_at >  (SELECT seed_value FROM seed WHERE table_name = 'trips.yellow_trip')
      AND y.created_at <= (SELECT last_value FROM etl.watermark WHERE table_name = 'trips.yellow_trip')
    UNION ALL
    SELECT 'trips.green_trip', COUNT_BIG(*)
    FROM trips.green_trip g
    WHERE g.created_at >  (SELECT seed_value FROM seed WHERE table_name = 'trips.green_trip')
      AND g.created_at <= (SELECT last_value FROM etl.watermark WHERE table_name = 'trips.green_trip')
),
lg AS (
    SELECT table_name, SUM(rows_copied) AS copied_rows, COUNT(*) AS success_runs
    FROM etl.adf_load_log
    WHERE year_month = 'INCR' AND status = 'success'
    GROUP BY table_name
)
SELECT s.table_name, s.source_rows, l.copied_rows, l.success_runs,
       CASE WHEN s.source_rows = l.copied_rows THEN 'MATCH' ELSE 'MISMATCH' END AS result
FROM src s
LEFT JOIN lg l ON l.table_name = s.table_name;