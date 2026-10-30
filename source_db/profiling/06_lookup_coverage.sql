/* =========================================================
   Step 6: Lookup coverage  (DB: NYCTaxi)
   Does every code in the trip tables exist in the ref tables,
   and what does each code's volume look like?
   ========================================================= */
USE NYCTaxi;
GO

/* ---------- 6a. Are the FKs enforced and trusted? ----------
   is_disabled = 1    -> FK is off, orphans are possible
   is_not_trusted = 1 -> load bypassed the check (e.g. bulk insert
                         without CHECK_CONSTRAINTS), orphans possible
   All zeros = SQL Server guarantees no orphans; 6b will return 0. */
SELECT OBJECT_SCHEMA_NAME(parent_object_id) + '.' + OBJECT_NAME(parent_object_id) AS table_name,
       name AS fk_name, is_disabled, is_not_trusted
FROM sys.foreign_keys
WHERE OBJECT_SCHEMA_NAME(parent_object_id) = 'trips'
ORDER BY table_name, fk_name;
GO

/* ---------- 6b. Orphan codes (codes missing from ref tables) ---------- */
SELECT 'yellow' AS cab_type, 'vendor_id' AS column_name, t.vendor_id AS code, COUNT_BIG(*) AS rows
FROM trips.yellow_trip t LEFT JOIN ref.vendor r ON r.vendor_id = t.vendor_id
WHERE r.vendor_id IS NULL GROUP BY t.vendor_id
UNION ALL
SELECT 'yellow', 'rate_code_id', t.rate_code_id, COUNT_BIG(*)
FROM trips.yellow_trip t LEFT JOIN ref.rate_code r ON r.rate_code_id = t.rate_code_id
WHERE t.rate_code_id IS NOT NULL AND r.rate_code_id IS NULL GROUP BY t.rate_code_id
UNION ALL
SELECT 'yellow', 'payment_type_id', t.payment_type_id, COUNT_BIG(*)
FROM trips.yellow_trip t LEFT JOIN ref.payment_type r ON r.payment_type_id = t.payment_type_id
WHERE t.payment_type_id IS NOT NULL AND r.payment_type_id IS NULL GROUP BY t.payment_type_id
UNION ALL
SELECT 'yellow', 'pu_location_id', t.pu_location_id, COUNT_BIG(*)
FROM trips.yellow_trip t LEFT JOIN ref.taxi_zone r ON r.location_id = t.pu_location_id
WHERE r.location_id IS NULL GROUP BY t.pu_location_id
UNION ALL
SELECT 'yellow', 'do_location_id', t.do_location_id, COUNT_BIG(*)
FROM trips.yellow_trip t LEFT JOIN ref.taxi_zone r ON r.location_id = t.do_location_id
WHERE r.location_id IS NULL GROUP BY t.do_location_id
UNION ALL
SELECT 'green', 'trip_type_id', t.trip_type_id, COUNT_BIG(*)
FROM trips.green_trip t LEFT JOIN ref.trip_type r ON r.trip_type_id = t.trip_type_id
WHERE t.trip_type_id IS NOT NULL AND r.trip_type_id IS NULL GROUP BY t.trip_type_id;
GO
-- Expect 0 rows. Skip this block if 6a shows all FKs trusted.

/* ---------- 6c. Code distribution with descriptions ---------- */
-- Vendor
SELECT 'yellow' AS cab_type, t.vendor_id, r.description, COUNT_BIG(*) AS rows,
       CAST(100.0 * COUNT_BIG(*) / SUM(COUNT_BIG(*)) OVER () AS DECIMAL(6,2)) AS pct
FROM trips.yellow_trip t JOIN ref.vendor r ON r.vendor_id = t.vendor_id
GROUP BY t.vendor_id, r.description
ORDER BY rows DESC;
GO
-- Rate code (NULL = the no-meter rows from Step 3)
SELECT 'yellow' AS cab_type, t.rate_code_id, r.description, COUNT_BIG(*) AS rows,
       CAST(100.0 * COUNT_BIG(*) / SUM(COUNT_BIG(*)) OVER () AS DECIMAL(6,2)) AS pct
FROM trips.yellow_trip t LEFT JOIN ref.rate_code r ON r.rate_code_id = t.rate_code_id
GROUP BY t.rate_code_id, r.description
ORDER BY rows DESC;
GO
-- Payment type
SELECT 'yellow' AS cab_type, t.payment_type_id, r.description, COUNT_BIG(*) AS rows,
       CAST(100.0 * COUNT_BIG(*) / SUM(COUNT_BIG(*)) OVER () AS DECIMAL(6,2)) AS pct
FROM trips.yellow_trip t LEFT JOIN ref.payment_type r ON r.payment_type_id = t.payment_type_id
GROUP BY t.payment_type_id, r.description
ORDER BY rows DESC;
GO
-- Repeat the three queries above with trips.green_trip, plus trip_type_id for green

/* ---------- 6d. Zones: unknown zones and unused zones ---------- */
-- Pickups by borough (Unknown / N/A = zones 264, 265)
SELECT 'yellow' AS cab_type, r.borough, COUNT_BIG(*) AS pickups,
       CAST(100.0 * COUNT_BIG(*) / SUM(COUNT_BIG(*)) OVER () AS DECIMAL(6,2)) AS pct
FROM trips.yellow_trip t JOIN ref.taxi_zone r ON r.location_id = t.pu_location_id
GROUP BY r.borough
ORDER BY pickups DESC;
GO
-- Zones in the ref table that never appear as a pickup or dropoff
SELECT z.location_id, z.borough, z.zone
FROM ref.taxi_zone z
WHERE NOT EXISTS (SELECT 1 FROM trips.yellow_trip t WHERE t.pu_location_id = z.location_id)
  AND NOT EXISTS (SELECT 1 FROM trips.yellow_trip t WHERE t.do_location_id = z.location_id)
  AND NOT EXISTS (SELECT 1 FROM trips.green_trip  t WHERE t.pu_location_id = z.location_id)
  AND NOT EXISTS (SELECT 1 FROM trips.green_trip  t WHERE t.do_location_id = z.location_id)
ORDER BY z.location_id;
GO
