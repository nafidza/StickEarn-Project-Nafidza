----------------------------------------------------------------
-- 01 BILLBOARD DATA CLEANING & VALIDATION
----------------------------------------------------------------

-- 1. Schema
SELECT column_name, data_type
FROM `stickearn-test-502018.stickearn_test`.INFORMATION_SCHEMA.COLUMNS
WHERE table_name = 'billboard_data';

SELECT COUNT(*) AS total_rows
FROM `stickearn_test.billboard_data`;

-- 2. Missing Value
SELECT
  COUNTIF(uuid IS NULL) AS missing_uuid,
  COUNTIF(name IS NULL OR TRIM(name) = '') AS missing_name,
  COUNTIF(latitude IS NULL) AS missing_lat,
  COUNTIF(longitude IS NULL) AS missing_long,
  COUNTIF(latitude IS NULL AND longitude IS NULL) AS missing_both_coord
FROM `stickearn_test.billboard_data`;

-- 3. Duplicate Data
SELECT
  uuid, 
  name, 
  latitude, 
  longitude, 
  COUNT(*) AS cnt_dup
FROM `stickearn_test.billboard_data`
GROUP BY uuid, name, latitude, longitude
HAVING COUNT(*) > 1;

-- 4. Duplicate Data 'uuid'
SELECT
  uuid,
  COUNT(*) AS row_count,
  COUNT(DISTINCT CONCAT(CAST(latitude AS STRING), '_', CAST(longitude AS STRING))) AS distinct_coord_count
FROM `stickearn_test.billboard_data`
GROUP BY uuid
HAVING COUNT(*) > 1;

-- 5. Coordinate Cheking
WITH cte AS (
  SELECT
    uuid,
    name,
    latitude,
    longitude,
    CASE
      WHEN latitude IS NULL OR longitude IS NULL THEN 'missing'
      WHEN latitude = 0 AND longitude = 0 THEN 'zero_coordinate'
      WHEN latitude NOT BETWEEN -11 AND 6 OR longitude NOT BETWEEN 95 AND 141 THEN 'outside_indonesia'
      WHEN latitude BETWEEN -6.3983 AND -5.32 AND longitude BETWEEN 106.3783 AND 106.9717 THEN 'valid_jakarta'
      ELSE 'valid_but_outside_jakarta'
    END AS coordinate_status
  FROM `stickearn_test.billboard_data`
)
SELECT
  coordinate_status,
  COUNT(*) AS cnt
FROM cte
GROUP BY 1;

-- 6. Quick check on billboard naming conventions
SELECT 
  name
FROM `stickearn_test.billboard_data`
WHERE name IS NOT NULL
LIMIT 30;


----------------------------------------------------------------
-- 02 MOBILITY DATA CLEANING & VALIDATION
-----------------------------------------------------------------------

-- 1. Schema
SELECT column_name, data_type, is_nullable
FROM `stickearn-test-502018.stickearn_test.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'mobility_data';

SELECT COUNT(*) AS total_rows
FROM `stickearn_test.mobility_data`;

-- 2. Missing Value
SELECT
  COUNTIF(id IS NULL) AS missing_id,
  COUNTIF(latitude IS NULL) AS missing_lat,
  COUNTIF(longitude IS NULL) AS missing_long,
  COUNTIF(datetime IS NULL) AS missing_datetime,
  COUNTIF(device_os IS NULL) AS missing_device_os
FROM `stickearn_test.mobility_data`;

-- 3. Duplicate Data Checking
SELECT
  id,
  datetime,
  latitude,
  longitude,
  COUNT(*) AS cnt_duplicate
FROM `stickearn_test.mobility_data`
GROUP BY id, datetime, latitude, longitude
HAVING COUNT(*) > 1
ORDER BY cnt_duplicate;

-- 4. Duplicate Data Checking (id + datetime)
SELECT
  id, 
  datetime,
  COUNT(*) AS row_count,
  COUNT(DISTINCT CONCAT(CAST(latitude AS STRING), '_', CAST(longitude AS STRING))) AS distinct_coord_count
FROM `stickearn_test.mobility_data`
GROUP BY id, datetime
HAVING COUNT(*) > 1;

-- 5. Check the distance variation between duplicates (in degrees, just to see the scale)
WITH dup_groups AS (
  SELECT
    id,
    datetime,
    MAX(latitude) - MIN(latitude) AS lat_range,
    MAX(longitude) - MIN(longitude) AS long_range
  FROM `stickearn_test.mobility_data`
  GROUP BY id, datetime
  HAVING COUNT(*) > 1
)
SELECT
  CASE
    WHEN lat_range < 0.001 AND long_range < 0.001 THEN 'small_diff'
    WHEN lat_range < 0.01 AND long_range < 0.01 THEN 'medium_diff'
    ELSE 'large_diff'
  END AS diff_category,
  COUNT(*) AS total_groups
FROM dup_groups
GROUP BY diff_category
ORDER BY total_groups DESC;

-- 6. Coordinate Range Validation
SELECT
  CASE
    WHEN latitude IS NULL OR longitude IS NULL THEN 'missing'
    WHEN latitude = 0 AND longitude = 0 THEN 'zero_coordinate'
    WHEN latitude NOT BETWEEN -11 AND 6 OR longitude NOT BETWEEN 95 AND 141 THEN 'outside_indonesia'
    WHEN latitude BETWEEN -6.3983 AND -5.32 AND longitude BETWEEN 106.3783 AND 106.9717 THEN 'valid_jakarta'
    ELSE 'valid_but_outside_jakarta'
  END AS coordinate_status,
  COUNT(*) AS total
FROM `stickearn_test.mobility_data`
GROUP BY coordinate_status
ORDER BY total DESC;

-- 7. Analyze Device OS distribution and detect anomalies
SELECT
  device_os,
  COUNT(*) AS total_record
FROM `stickearn_test.mobility_data`
GROUP BY device_os
ORDER BY device_os;

-- 8. Inspect unique datetime formats
SELECT 
  DISTINCT datetime
FROM `stickearn_test.mobility_data`;

-- 9. Identify the dataset's date range
SELECT
  MIN(datetime) AS earliest,
  MAX(datetime) AS latest,
  COUNT(DISTINCT DATE(datetime)) AS distinct_days
FROM `stickearn_test.mobility_data`;


-- 10. CLEANING MOBILITY DATA PROCESS
CREATE OR REPLACE TABLE `stickearn-test-502018.stickearn_test.master_mobility` AS
WITH dedup_exact AS (
  SELECT 
    DISTINCT id, datetime, latitude, longitude, device_os
  FROM `stickearn-test-502018.stickearn_test.mobility_data`
),
dup_diff_check AS (
  SELECT
    id, 
    datetime,
    MAX(latitude) - MIN(latitude) AS lat_range,
    MAX(longitude) - MIN(longitude) AS long_range
  FROM dedup_exact
  GROUP BY id, datetime
),
large_diff_keys AS (
  SELECT 
    id, 
    datetime
  FROM dup_diff_check
  WHERE lat_range >= 0.01 OR long_range >= 0.01
),
cleaned_base AS (
  SELECT 
    d.*
  FROM dedup_exact d
  LEFT JOIN large_diff_keys l
    ON d.id = l.id AND d.datetime = l.datetime
  WHERE l.id IS NULL
)
SELECT
  id,
  datetime,
  AVG(latitude) AS latitude,
  AVG(longitude) AS longitude,
  ANY_VALUE(device_os) AS device_os
FROM cleaned_base
GROUP BY id, datetime;
