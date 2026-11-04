USE NYCTaxi;
GO
IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl');
GO


IF OBJECT_ID('etl.watermark') IS NULL
BEGIN
    CREATE TABLE etl.watermark (
        table_name VARCHAR(50) NOT NULL CONSTRAINT PK_watermark PRIMARY KEY,
        watermark_column VARCHAR(50) NOT NULL,
        last_value DATETIME2(3) NOT NULL,
        updated_at DATETIME2(3) CONSTRAINT DF_watermark_updated_at DEFAULT SYSUTCDATETIME() NOT NULL,
        last_run_id VARCHAR(50) NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM etl.watermark WHERE table_name = 'trips.yellow_trip')
    INSERT INTO etl.watermark (table_name, watermark_column, last_value)
    SELECT 'trips.yellow_trip', 'created_at', MAX(created_at) FROM trips.yellow_trip;

IF NOT EXISTS (SELECT 1 FROM etl.watermark WHERE table_name = 'trips.green_trip')
    INSERT INTO etl.watermark (table_name, watermark_column, last_value)
    SELECT 'trips.green_trip', 'created_at', MAX(created_at) FROM trips.green_trip;

SELECT * FROM etl.watermark;