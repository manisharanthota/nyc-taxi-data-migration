-- control_totals.sql : pre-migration answer key (per table, per pickup month)
-- Rerun section 2 after any data load (e.g. 2024). Each run = new snapshot (captured_at).
USE NYCTaxi;
GO

/* ---------- 1. Audit table (safe to rerun) ---------- */
IF SCHEMA_ID('audit') IS NULL EXEC('CREATE SCHEMA audit');
GO
IF OBJECT_ID('audit.control_totals') IS NULL
CREATE TABLE audit.control_totals (
    table_name        VARCHAR(50)    NOT NULL,
    year_month        CHAR(7)        NOT NULL,
    row_count         BIGINT         NOT NULL,
    sum_total_amount  DECIMAL(18,2)  NULL,
    sum_trip_distance DECIMAL(18,2)  NULL,
    min_pickup        DATETIME2      NULL,
    max_pickup        DATETIME2      NULL,
    captured_at       DATETIME2      NOT NULL
        CONSTRAINT DF_control_totals_captured_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_control_totals PRIMARY KEY (table_name, year_month, captured_at)
);
GO

/* ---------- 2. Capture a snapshot ---------- */
DECLARE @captured_at DATETIME2 = SYSUTCDATETIME();

INSERT INTO audit.control_totals
    (table_name, year_month, row_count, sum_total_amount,
     sum_trip_distance, min_pickup, max_pickup, captured_at)
SELECT t.*, @captured_at
FROM (
    SELECT
        'trips.yellow_trip'                       AS table_name,
        CONVERT(CHAR(7), pickup_datetime, 120)    AS year_month,
        COUNT_BIG(*)                              AS row_count,
        SUM(CAST(total_amount  AS DECIMAL(18,2))) AS sum_total_amount,
        SUM(CAST(trip_distance AS DECIMAL(18,2))) AS sum_trip_distance,
        MIN(pickup_datetime)                      AS min_pickup,
        MAX(pickup_datetime)                      AS max_pickup
    FROM trips.yellow_trip
    GROUP BY CONVERT(CHAR(7), pickup_datetime, 120)

    UNION ALL

    SELECT 'trips.green_trip', CONVERT(CHAR(7), pickup_datetime, 120),
           COUNT_BIG(*),
           SUM(CAST(total_amount  AS DECIMAL(18,2))),
           SUM(CAST(trip_distance AS DECIMAL(18,2))),
           MIN(pickup_datetime), MAX(pickup_datetime)
    FROM trips.green_trip
    GROUP BY CONVERT(CHAR(7), pickup_datetime, 120)
) AS t;
GO

/* ---------- 3. Check latest snapshot ---------- */
SELECT table_name, SUM(row_count) AS total_rows, COUNT(*) AS months
FROM audit.control_totals
WHERE captured_at = (SELECT MAX(captured_at) FROM audit.control_totals)
GROUP BY table_name;
