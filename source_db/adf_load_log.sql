-- adf_load_log.sql : ADF run log + logging procs (rerunnable). Run as sa.
USE NYCTaxi;
GO
IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl');
GO

-- 1. Log table: one row per (pipeline run, table, month)
IF OBJECT_ID('etl.adf_load_log') IS NULL
CREATE TABLE etl.adf_load_log (
    log_id           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_adf_load_log PRIMARY KEY,
    pipeline_run_id  VARCHAR(50)    NOT NULL,
    table_name       VARCHAR(50)    NOT NULL,   -- e.g. trips.yellow_trip
    year_month       CHAR(7)        NOT NULL,   -- e.g. 2025-02 (pickup month)
    status           VARCHAR(10)    NOT NULL CONSTRAINT CK_adf_load_log_status
                                    CHECK (status IN ('running','success','failed')),
    rows_read        BIGINT         NULL,
    rows_copied      BIGINT         NULL,
    started_at       DATETIME2(3)   NOT NULL CONSTRAINT DF_adf_load_log_started DEFAULT SYSUTCDATETIME(),
    ended_at         DATETIME2(3)   NULL,
    error_message    NVARCHAR(4000) NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_adf_load_log_table_month')
CREATE INDEX IX_adf_load_log_table_month ON etl.adf_load_log (table_name, year_month, status);
GO

-- 2. Start proc: insert a 'running' row
CREATE OR ALTER PROCEDURE etl.usp_adf_log_start
    @run_id      VARCHAR(50),
    @table_name  VARCHAR(50),
    @year_month  CHAR(7)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO etl.adf_load_log (pipeline_run_id, table_name, year_month, status)
    VALUES (@run_id, @table_name, @year_month, 'running');
END;
GO

-- 3. End proc: close the matching 'running' row
CREATE OR ALTER PROCEDURE etl.usp_adf_log_end
    @run_id       VARCHAR(50),
    @table_name   VARCHAR(50),
    @year_month   CHAR(7),
    @status       VARCHAR(10),          -- success / failed
    @rows_read    BIGINT = NULL,
    @rows_copied  BIGINT = NULL,
    @error        NVARCHAR(4000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE etl.adf_load_log
       SET status        = @status,
           rows_read     = @rows_read,
           rows_copied   = @rows_copied,
           ended_at      = SYSUTCDATETIME(),
           error_message = @error
     WHERE pipeline_run_id = @run_id
       AND table_name      = @table_name
       AND year_month      = @year_month
       AND status          = 'running';
END;
GO

-- 4. Permission: adf_reader can run etl procs only (no direct table writes)
GRANT EXECUTE ON SCHEMA::etl TO adf_reader;
GO

/*
EXEC etl.usp_adf_log_start 'test-run-1', 'trips.yellow_trip', '2025-02';
EXEC etl.usp_adf_log_end   'test-run-1', 'trips.yellow_trip', '2025-02', 'success', 100, 100;
SELECT * FROM etl.adf_load_log WHERE pipeline_run_id = 'test-run-1';
DELETE FROM etl.adf_load_log WHERE pipeline_run_id = 'test-run-1';
*/
