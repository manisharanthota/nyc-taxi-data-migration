-- schema.sql : NYCTaxi source DB
USE NYCTaxi;
GO
IF SCHEMA_ID('ref')   IS NULL EXEC('CREATE SCHEMA ref');
IF SCHEMA_ID('trips') IS NULL EXEC('CREATE SCHEMA trips');
GO

-- Idempotent: each object is created only if missing. Never drops data.

-- Lookups
IF OBJECT_ID('ref.vendor') IS NULL
CREATE TABLE ref.vendor (
    vendor_id        TINYINT     NOT NULL CONSTRAINT PK_vendor PRIMARY KEY,
    description      VARCHAR(50) NOT NULL
);
IF OBJECT_ID('ref.rate_code') IS NULL
CREATE TABLE ref.rate_code (
    rate_code_id     TINYINT     NOT NULL CONSTRAINT PK_rate_code PRIMARY KEY,
    description      VARCHAR(50) NOT NULL
);
IF OBJECT_ID('ref.payment_type') IS NULL
CREATE TABLE ref.payment_type (
    payment_type_id  TINYINT     NOT NULL CONSTRAINT PK_payment_type PRIMARY KEY,
    description      VARCHAR(50) NOT NULL
);
IF OBJECT_ID('ref.trip_type') IS NULL
CREATE TABLE ref.trip_type (
    trip_type_id     TINYINT     NOT NULL CONSTRAINT PK_trip_type PRIMARY KEY,
    description      VARCHAR(50) NOT NULL
);
IF OBJECT_ID('ref.taxi_zone') IS NULL
CREATE TABLE ref.taxi_zone (
    location_id      SMALLINT    NOT NULL CONSTRAINT PK_taxi_zone PRIMARY KEY,
    borough          VARCHAR(50) NULL,
    zone             VARCHAR(50) NULL,
    service_zone     VARCHAR(50) NULL
);
GO

-- Facts
IF OBJECT_ID('trips.yellow_trip') IS NULL
CREATE TABLE trips.yellow_trip (
    trip_id                BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_yellow_trip PRIMARY KEY,
    vendor_id              TINYINT       NOT NULL,
    pickup_datetime        DATETIME2(0)  NOT NULL,
    dropoff_datetime       DATETIME2(0)  NOT NULL,
    passenger_count        TINYINT       NULL,
    trip_distance          DECIMAL(10,2) NULL,
    rate_code_id           TINYINT       NULL,
    store_and_fwd_flag     CHAR(1)       NULL,
    pu_location_id         SMALLINT      NOT NULL,
    do_location_id         SMALLINT      NOT NULL,
    payment_type_id        TINYINT       NULL,
    fare_amount            DECIMAL(10,2) NULL,
    extra                  DECIMAL(10,2) NULL,
    mta_tax                DECIMAL(10,2) NULL,
    tip_amount             DECIMAL(10,2) NULL,
    tolls_amount           DECIMAL(10,2) NULL,
    improvement_surcharge  DECIMAL(10,2) NULL,
    total_amount           DECIMAL(10,2) NULL,
    congestion_surcharge   DECIMAL(10,2) NULL,
    airport_fee            DECIMAL(10,2) NULL,
    cbd_congestion_fee     DECIMAL(10,2) NULL,
    created_at             DATETIME2(3)  NOT NULL CONSTRAINT DF_yellow_trip_created_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_yellow_trip_vendor       FOREIGN KEY (vendor_id)       REFERENCES ref.vendor(vendor_id),
    CONSTRAINT FK_yellow_trip_rate_code    FOREIGN KEY (rate_code_id)    REFERENCES ref.rate_code(rate_code_id),
    CONSTRAINT FK_yellow_trip_payment_type FOREIGN KEY (payment_type_id) REFERENCES ref.payment_type(payment_type_id),
    CONSTRAINT FK_yellow_trip_pu_zone      FOREIGN KEY (pu_location_id)  REFERENCES ref.taxi_zone(location_id),
    CONSTRAINT FK_yellow_trip_do_zone      FOREIGN KEY (do_location_id)  REFERENCES ref.taxi_zone(location_id),
    CONSTRAINT CK_yellow_trip_sf_flag      CHECK (store_and_fwd_flag IN ('Y','N'))
);

IF OBJECT_ID('trips.green_trip') IS NULL
CREATE TABLE trips.green_trip (
    trip_id                BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_green_trip PRIMARY KEY,
    vendor_id              TINYINT       NOT NULL,
    pickup_datetime        DATETIME2(0)  NOT NULL,
    dropoff_datetime       DATETIME2(0)  NOT NULL,
    store_and_fwd_flag     CHAR(1)       NULL,
    rate_code_id           TINYINT       NULL,
    pu_location_id         SMALLINT      NOT NULL,
    do_location_id         SMALLINT      NOT NULL,
    passenger_count        TINYINT       NULL,
    trip_distance          DECIMAL(10,2) NULL,
    fare_amount            DECIMAL(10,2) NULL,
    extra                  DECIMAL(10,2) NULL,
    mta_tax                DECIMAL(10,2) NULL,
    tip_amount             DECIMAL(10,2) NULL,
    tolls_amount           DECIMAL(10,2) NULL,
    ehail_fee              DECIMAL(10,2) NULL,   -- in the parquet files, not in the PDF; always null
    improvement_surcharge  DECIMAL(10,2) NULL,
    total_amount           DECIMAL(10,2) NULL,
    payment_type_id        TINYINT       NULL,
    trip_type_id           TINYINT       NULL,
    congestion_surcharge   DECIMAL(10,2) NULL,
    cbd_congestion_fee     DECIMAL(10,2) NULL,
    created_at             DATETIME2(3)  NOT NULL CONSTRAINT DF_green_trip_created_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT FK_green_trip_vendor       FOREIGN KEY (vendor_id)       REFERENCES ref.vendor(vendor_id),
    CONSTRAINT FK_green_trip_rate_code    FOREIGN KEY (rate_code_id)    REFERENCES ref.rate_code(rate_code_id),
    CONSTRAINT FK_green_trip_payment_type FOREIGN KEY (payment_type_id) REFERENCES ref.payment_type(payment_type_id),
    CONSTRAINT FK_green_trip_trip_type    FOREIGN KEY (trip_type_id)    REFERENCES ref.trip_type(trip_type_id),
    CONSTRAINT FK_green_trip_pu_zone      FOREIGN KEY (pu_location_id)  REFERENCES ref.taxi_zone(location_id),
    CONSTRAINT FK_green_trip_do_zone      FOREIGN KEY (do_location_id)  REFERENCES ref.taxi_zone(location_id),
    CONSTRAINT CK_green_trip_sf_flag      CHECK (store_and_fwd_flag IN ('Y','N'))
);
GO

-- Watermark indexes for incremental loads
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_yellow_trip_created_at')
CREATE NONCLUSTERED INDEX IX_yellow_trip_created_at
    ON trips.yellow_trip (created_at);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_green_trip_created_at')
CREATE NONCLUSTERED INDEX IX_green_trip_created_at
    ON trips.green_trip (created_at);
GO

