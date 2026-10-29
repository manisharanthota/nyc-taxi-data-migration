-- seed_lookups.sql : run once, right after schema.sql
USE NYCTaxi;
GO

INSERT INTO ref.vendor (vendor_id, description) VALUES
(1,'Creative Mobile Technologies, LLC'),
(2,'Curb Mobility, LLC'),
(6,'Myle Technologies Inc'),
(7,'Helix');

INSERT INTO ref.rate_code (rate_code_id, description) VALUES
(1,'Standard rate'),(2,'JFK'),(3,'Newark'),
(4,'Nassau or Westchester'),(5,'Negotiated fare'),
(6,'Group ride'),(99,'Null/unknown');

INSERT INTO ref.payment_type (payment_type_id, description) VALUES
(0,'Flex Fare trip'),(1,'Credit card'),(2,'Cash'),(3,'No charge'),
(4,'Dispute'),(5,'Unknown'),(6,'Voided trip');

INSERT INTO ref.trip_type (trip_type_id, description) VALUES
(1,'Street-hail'),(2,'Dispatch');
GO
BULK INSERT ref.taxi_zone
FROM '/tmp/taxi_zone_lookup.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, ROWTERMINATOR = '0x0d0a');