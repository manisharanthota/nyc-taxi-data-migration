-- security.sql : read-only login for ADF (least privilege)
-- Run as sa. Replace the password placeholder with ADF_READER_PASSWORD from .env.
-- Never commit the real password.

/* ---------- 1. Server level: login ---------- */
USE master;
GO
IF SUSER_ID('adf_reader') IS NULL
    CREATE LOGIN adf_reader WITH PASSWORD = '<ADF_READER_PASSWORD from .env>',
                                 DEFAULT_DATABASE = NYCTaxi;
GO

/* ---------- 2. Database level: user + read-only role ---------- */
USE NYCTaxi;
GO
IF USER_ID('adf_reader') IS NULL
    CREATE USER adf_reader FOR LOGIN adf_reader;
ALTER ROLE db_datareader ADD MEMBER adf_reader;
GO

/* ---------- 3. Test (connect AS adf_reader) ----------
SELECT SUSER_NAME();                   -- adf_reader
SELECT TOP 5 * FROM trips.yellow_trip; -- works
DELETE FROM ref.vendor WHERE 1 = 0;    -- must fail: permission denied
*/
