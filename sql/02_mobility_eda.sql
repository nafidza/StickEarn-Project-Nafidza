------------------------------------------------------------------------
-- 01. DISTRIBUTION OF USER ACTIVITY
-- Objective: Analyze mobility traffic by hour and device OS.
------------------------------------------------------------------------

-- 1. Distribution by Hour
SELECT
  EXTRACT(HOUR FROM datetime) AS hour_of_day,
  COUNT(*) AS total_records,
  COUNT(DISTINCT id) AS unique_devices
FROM `stickearn-test-502018.stickearn_test.master_mobility`
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- 2. Distribution by Device OS per Hour
SELECT
  EXTRACT(HOUR FROM datetime) AS hour_of_day,
  device_os,
  COUNT(*) AS total_records,
  COUNT(DISTINCT id) AS unique_devices
FROM `stickearn-test-502018.stickearn_test.master_mobility`
GROUP BY hour_of_day, device_os
ORDER BY hour_of_day, device_os;


------------------------------------------------------------------------
-- 02. SPATIAL AGGREGATION: MOBILITY GRID DENSITY MAPPING
-- Create a spatial grid base to analyze point density 
-- and unique device concentration.
------------------------------------------------------------------------
CREATE OR REPLACE TABLE `stickearn-test-502018.stickearn_test.mobility_grid_density` AS
SELECT
  ROUND(latitude, 3) AS grid_lat,
  ROUND(longitude, 3) AS grid_long,
  COUNT(*) AS point_count,
  COUNT(DISTINCT id) AS unique_devices
FROM `stickearn-test-502018.stickearn_test.master_mobility`
GROUP BY grid_lat, grid_long
ORDER BY point_count DESC;

------------------------------------------------------------------------
-- 03. OUTLIER DETECTION: RECORD FREQUENCY PER DEVICE
-- Identify extreme users or bot-like behavior by evaluating 
-- the distribution of records per device.
------------------------------------------------------------------------

-- 1. Grouping devices by their total record count
SELECT
  record_count,
  COUNT(*) AS num_devices
FROM (
  SELECT id, COUNT(*) AS record_count
  FROM `stickearn-test-502018.stickearn_test.master_mobility`
  GROUP BY id
)
GROUP BY record_count
ORDER BY record_count DESC;

-- 2. Statistical summary of record distribution (Min, Max, Avg, Percentiles)
SELECT
  MIN(record_count) AS min_record,
  MAX(record_count) AS max_record,
  AVG(record_count) AS avg_record,
  APPROX_QUANTILES(record_count, 100)[OFFSET(50)] AS median_p50,
  APPROX_QUANTILES(record_count, 100)[OFFSET(95)] AS p95,
  APPROX_QUANTILES(record_count, 100)[OFFSET(99)] AS p99
FROM (
  SELECT id, COUNT(*) AS record_count
  FROM `stickearn-test-502018.stickearn_test.master_mobility`
  GROUP BY id
);

------------------------------------------------------------------------
-- 04. OUTLIER DETECTION: IMPLIED SPEED CHECK (MOVEMENT PLAUSIBILITY)
-- Calculate implied travel speed between consecutive points to detect 
-- GPS anomalies (e.g., jumping coordinates).
------------------------------------------------------------------------

-- 1. Check top 100 highest speeds to inspect anomalies visually
WITH ordered_points AS (
  SELECT
    id,
    datetime,
    latitude,
    longitude,
    LAG(datetime) OVER (PARTITION BY id ORDER BY datetime) AS prev_datetime,
    LAG(latitude) OVER (PARTITION BY id ORDER BY datetime) AS prev_lat,
    LAG(longitude) OVER (PARTITION BY id ORDER BY datetime) AS prev_long
  FROM `stickearn-test-502018.stickearn_test.master_mobility`
),
distance_calc AS (
  SELECT
    id,
    datetime,
    prev_datetime,
    ST_DISTANCE(
      ST_GEOGPOINT(longitude, latitude),
      ST_GEOGPOINT(prev_long, prev_lat)
    ) AS distance_meters,
    TIMESTAMP_DIFF(datetime, prev_datetime, SECOND) AS time_diff_seconds
  FROM ordered_points
  WHERE prev_datetime IS NOT NULL
)
SELECT
  id,
  datetime,
  prev_datetime,
  distance_meters,
  time_diff_seconds,
  SAFE_DIVIDE(distance_meters / 1000, time_diff_seconds / 3600) AS implied_speed_kmh
FROM distance_calc
WHERE time_diff_seconds > 0
ORDER BY implied_speed_kmh DESC
LIMIT 100;

-- 2. Aggregate anomalous transitions (>110 km/h threshold)
WITH ordered_points AS (
  SELECT
    id, datetime, latitude, longitude,
    LAG(datetime) OVER (PARTITION BY id ORDER BY datetime) AS prev_datetime,
    LAG(latitude) OVER (PARTITION BY id ORDER BY datetime) AS prev_lat,
    LAG(longitude) OVER (PARTITION BY id ORDER BY datetime) AS prev_long
  FROM `stickearn-test-502018.stickearn_test.master_mobility`
),
distance_calc AS (
  SELECT
    id,
    datetime,
    prev_datetime,
    ST_DISTANCE(
      ST_GEOGPOINT(longitude, latitude),
      ST_GEOGPOINT(prev_long, prev_lat)) AS distance_meters,
    TIMESTAMP_DIFF(datetime, prev_datetime, SECOND) AS time_diff_seconds
  FROM ordered_points
  WHERE prev_datetime IS NOT NULL AND TIMESTAMP_DIFF(datetime, prev_datetime, SECOND) > 0
)
SELECT
  COUNTIF(SAFE_DIVIDE(distance_meters/1000, time_diff_seconds/3600) > 110) AS anomalous_transitions,
  COUNT(DISTINCT id) AS total_device_with_multirecord,
  COUNT(*) AS total_transitions
FROM distance_calc;

------------------------------------------------------------------------
-- 05. DATA CLEANSING: FINAL MASTER TABLE CREATION
-- Create the final cleaned dataset by excluding specific 
-- anomalous points where implied speed > 110 km/h.
------------------------------------------------------------------------
CREATE OR REPLACE TABLE `stickearn-test-502018.stickearn_test.master_mobility_final` AS
WITH ordered_points AS (
  SELECT
    id, 
    datetime,
    latitude,
    longitude,
    device_os,
    LAG(datetime) OVER (PARTITION BY id ORDER BY datetime) AS prev_datetime,
    LAG(latitude) OVER (PARTITION BY id ORDER BY datetime) AS prev_lat,
    LAG(longitude) OVER (PARTITION BY id ORDER BY datetime) AS prev_long
  FROM `stickearn-test-502018.stickearn_test.master_mobility`
),
flagged AS (
  SELECT
    *,
    CASE
      WHEN prev_datetime IS NOT NULL
       AND TIMESTAMP_DIFF(datetime, prev_datetime, SECOND) > 0
       AND SAFE_DIVIDE(
             ST_DISTANCE(ST_GEOGPOINT(longitude, latitude), ST_GEOGPOINT(prev_long, prev_lat)) / 1000,
             TIMESTAMP_DIFF(datetime, prev_datetime, SECOND) / 3600
           ) > 110
      THEN TRUE
      ELSE FALSE
    END AS is_anomalous_point
  FROM ordered_points
)
SELECT 
  id,
  datetime, 
  latitude, 
  longitude, 
  device_os
FROM flagged
WHERE is_anomalous_point = FALSE;

------------------------------------------------------------------------
-- 06. CLEANSING VALIDATION: BEFORE VS AFTER
-- Verify the number of rows successfully excluded.
------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM `stickearn-test-502018.stickearn_test.master_mobility`) AS before_count,
  (SELECT COUNT(*) FROM `stickearn-test-502018.stickearn_test.master_mobility_final`) AS after_count;
