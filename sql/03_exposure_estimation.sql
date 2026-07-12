------------------------------------------------------------------------
-- 01. SPATIAL JOIN: EXPOSURE PROXIMITY MAPPING
-- Map mobility points to billboards within 50m & 100m radius.
-- Utilizes bounding box pre-filtering for spatial optimization.
------------------------------------------------------------------------
CREATE OR REPLACE TABLE `stickearn-test-502018.stickearn_test.exposure_proximity` AS
WITH billboard_geo AS (
  SELECT
    uuid AS billboard_id,
    name AS billboard_name,
    latitude AS b_lat,
    longitude AS b_long,
    ST_GEOGPOINT(longitude, latitude) AS b_point
  FROM `stickearn-test-502018.stickearn_test.billboard_data`
),
mobility_geo AS (
  SELECT
    id AS device_id,
    datetime,
    latitude AS m_lat,
    longitude AS m_long,
    ST_GEOGPOINT(longitude, latitude) AS m_point
  FROM `stickearn-test-502018.stickearn_test.master_mobility_final`
),
prefiltered_join AS (
  SELECT
    b.billboard_id,
    b.billboard_name,
    m.device_id,
    m.datetime,
    ST_DISTANCE(b.b_point, m.m_point) AS distance_meters
  FROM billboard_geo b
  JOIN mobility_geo m
    ON m.m_lat BETWEEN b.b_lat - 0.002 AND b.b_lat + 0.002
   AND m.m_long BETWEEN b.b_long - 0.002 AND b.b_long + 0.002
  WHERE ST_DWITHIN(b.b_point, m.m_point, 100)
)
SELECT
  billboard_id,
  billboard_name,
  device_id,
  datetime,
  distance_meters,
  CASE WHEN distance_meters <= 50 THEN TRUE ELSE FALSE END AS within_50m,
  CASE WHEN distance_meters <= 100 THEN TRUE ELSE FALSE END AS within_100m
FROM prefiltered_join;

------------------------------------------------------------------------
-- 02. EXPOSURE METRICS AGGREGATION (50m & 100m RADIUS)
-- Calculate core OOH metrics (Impressions, Reach, Frequency) for 
-- each billboard at different proximity thresholds.
------------------------------------------------------------------------

-- 1. Create Summary Table for 50m Radius
CREATE OR REPLACE TABLE `stickearn-test-502018.stickearn_test.exposure_summary_50m` AS
SELECT
  billboard_id,
  billboard_name,
  COUNT(*) AS impressions,
  COUNT(DISTINCT device_id) AS reach,
  ROUND(COUNT(*) / COUNT(DISTINCT device_id), 2) AS frequency
FROM `stickearn-test-502018.stickearn_test.exposure_proximity`
WHERE within_50m = TRUE
GROUP BY billboard_id, billboard_name
ORDER BY impressions DESC;

-- 2 Create Summary Table for 100m Radius
CREATE OR REPLACE TABLE `stickearn-test-502018.stickearn_test.exposure_summary_100m` AS
SELECT
  billboard_id,
  billboard_name,
  COUNT(*) AS impressions,
  COUNT(DISTINCT device_id) AS reach,
  ROUND(COUNT(*) / COUNT(DISTINCT device_id), 2) AS frequency
FROM `stickearn-test-502018.stickearn_test.exposure_proximity`
WHERE within_100m = TRUE
GROUP BY billboard_id, billboard_name
ORDER BY impressions DESC;

------------------------------------------------------------------------
-- 03. RADIUS SENSITIVITY ANALYSIS (50m vs 100m)
-- Objective: Compare overall market exposure across different spatial boundaries.
------------------------------------------------------------------------
SELECT
  '50m' AS radius,
  COUNT(*) AS total_impressions,
  COUNT(DISTINCT device_id) AS total_unique_devices_exposed,
  COUNT(DISTINCT billboard_id) AS billboards_with_exposure
FROM `stickearn-test-502018.stickearn_test.exposure_proximity`
WHERE within_50m = TRUE

UNION ALL

SELECT
  '100m' AS radius,
  COUNT(*) AS total_impressions,
  COUNT(DISTINCT device_id) AS total_unique_devices_exposed,
  COUNT(DISTINCT billboard_id) AS billboards_with_exposure
FROM `stickearn-test-502018.stickearn_test.exposure_proximity`
WHERE within_100m = TRUE;

------------------------------------------------------------------------
-- 04. BILLBOARD PERFORMANCE RANKING (100m RADIUS)
------------------------------------------------------------------------

-- 1. Top 10 Ranking by Impressions
SELECT
  billboard_id,
  billboard_name,
  impressions,
  reach,
  frequency
FROM `stickearn-test-502018.stickearn_test.exposure_summary_100m`
ORDER BY impressions DESC
LIMIT 10;

-- 2. Top 10 Ranking by Reach
SELECT
  billboard_id,
  billboard_name,
  impressions,
  reach,
  frequency
FROM `stickearn-test-502018.stickearn_test.exposure_summary_100m`
ORDER BY reach DESC
LIMIT 10;

-- 3. Top 10 Ranking by Raw Frequency (Unfiltered)
SELECT
  billboard_id,
  billboard_name,
  impressions,
  reach,
  frequency
FROM `stickearn-test-502018.stickearn_test.exposure_summary_100m`
ORDER BY frequency DESC
LIMIT 10;

------------------------------------------------------------------------
-- 05. STATISTICAL RELIABILITY FILTER & FINAL FREQUENCY RANKING
------------------------------------------------------------------------

-- 1. Determine the Reach Threshold (Median / 50th Percentile)
SELECT
  APPROX_QUANTILES(reach, 100)[OFFSET(50)] AS median_reach,
  APPROX_QUANTILES(reach, 100)[OFFSET(25)] AS p25_reach
FROM (
  SELECT billboard_id, reach
  FROM `stickearn-test-502018.stickearn_test.exposure_summary_100m`
);

-- 2. Top 10 Ranking by Frequency (Applying >= 37 Median Reach Filter)
SELECT
  billboard_id,
  billboard_name,
  impressions,
  reach,
  frequency
FROM `stickearn-test-502018.stickearn_test.exposure_summary_100m`
WHERE reach >= 37
ORDER BY frequency DESC
LIMIT 10;
