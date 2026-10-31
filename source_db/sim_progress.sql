USE NYCTaxi;
GO
IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl');
GO
IF OBJECT_ID('etl.sim_progress', 'U') IS NULL
CREATE TABLE etl.sim_progress (
    run_id         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_sim_progress PRIMARY KEY,
    table_name     VARCHAR(20)   NOT NULL CONSTRAINT CK_sim_progress_table  CHECK (table_name IN ('yellow_trip','green_trip')),
    file_name      VARCHAR(200)  NOT NULL,
    start_offset   INT           NOT NULL,
    rows_inserted  INT           NOT NULL CONSTRAINT DF_sim_progress_rows   DEFAULT 0,
    min_trip_id    BIGINT        NULL,
    max_trip_id    BIGINT        NULL,
    started_at     DATETIME2(3)  NOT NULL CONSTRAINT DF_sim_progress_started DEFAULT SYSUTCDATETIME(),
    finished_at    DATETIME2(3)  NULL,
    status         VARCHAR(10)   NOT NULL CONSTRAINT DF_sim_progress_status DEFAULT 'running'
                                 CONSTRAINT CK_sim_progress_status CHECK (status IN ('running','success','failed'))
);
GO

SELECT ISNULL((
    SELECT TOP 1 start_offset + rows_inserted
    FROM etl.sim_progress
    WHERE file_name = 'yellow_tripdata_2026-09.parquet'
      AND status = 'success'
    ORDER BY run_id DESC
), 0) AS next_offset;