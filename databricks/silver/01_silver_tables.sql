-- Databricks notebook source
-- 3.3.1 Silver tables (run once; idempotent)

CREATE TABLE IF NOT EXISTS nyctaxi.silver.yellow_trip (
  trip_id               BIGINT NOT NULL,
  vendor_id             INT,
  pickup_datetime       TIMESTAMP,
  dropoff_datetime      TIMESTAMP,
  pickup_date           DATE,
  trip_duration_min     DECIMAL(10,2),
  passenger_count       INT,
  trip_distance         DECIMAL(10,2),
  rate_code_id          INT,
  store_and_fwd_flag    STRING,
  pu_location_id        INT,
  do_location_id        INT,
  payment_type_id       INT,
  fare_amount           DECIMAL(10,2),
  extra                 DECIMAL(10,2),
  mta_tax               DECIMAL(10,2),
  tip_amount            DECIMAL(10,2),
  tolls_amount          DECIMAL(10,2),
  improvement_surcharge DECIMAL(10,2),
  total_amount          DECIMAL(10,2),
  congestion_surcharge  DECIMAL(10,2),
  airport_fee           DECIMAL(10,2),
  cbd_congestion_fee    DECIMAL(10,2),
  pricing_type          STRING,   -- 'FLEX' | 'METERED'
  is_reversal           BOOLEAN,
  is_adjustment         BOOLEAN,
  source_created_at     TIMESTAMP,
  _source_file          STRING,
  _ingested_at          TIMESTAMP,
  _silver_updated_at    TIMESTAMP
)
CLUSTER BY (pickup_date);

-- COMMAND ----------

CREATE TABLE IF NOT EXISTS nyctaxi.silver.green_trip (
  trip_id               BIGINT NOT NULL,
  vendor_id             INT,
  pickup_datetime       TIMESTAMP,
  dropoff_datetime      TIMESTAMP,
  pickup_date           DATE,
  trip_duration_min     DECIMAL(10,2),
  passenger_count       INT,
  trip_distance         DECIMAL(10,2),
  rate_code_id          INT,
  store_and_fwd_flag    STRING,
  pu_location_id        INT,
  do_location_id        INT,
  payment_type_id       INT,
  trip_type_id          INT,
  fare_amount           DECIMAL(10,2),
  extra                 DECIMAL(10,2),
  mta_tax               DECIMAL(10,2),
  tip_amount            DECIMAL(10,2),
  tolls_amount          DECIMAL(10,2),
  improvement_surcharge DECIMAL(10,2),
  total_amount          DECIMAL(10,2),
  congestion_surcharge  DECIMAL(10,2),
  cbd_congestion_fee    DECIMAL(10,2),
  pricing_type          STRING,
  is_reversal           BOOLEAN,
  is_adjustment         BOOLEAN,
  source_created_at     TIMESTAMP,
  _source_file          STRING,
  _ingested_at          TIMESTAMP,
  _silver_updated_at    TIMESTAMP
)
CLUSTER BY (pickup_date);

-- COMMAND ----------

CREATE TABLE IF NOT EXISTS nyctaxi.silver.trip_quarantine (
  taxi_type        STRING NOT NULL,   -- 'yellow' | 'green'
  trip_id          BIGINT NOT NULL,
  reason           STRING NOT NULL,   -- e.g. 'DROPOFF_BEFORE_PICKUP'
  pickup_datetime  TIMESTAMP,
  raw_record       STRING,            -- full bronze row as JSON (to_json(struct(*)))
  _source_file     STRING,
  _quarantined_at  TIMESTAMP
);

-- COMMAND ----------

SHOW TABLES IN nyctaxi.silver;
