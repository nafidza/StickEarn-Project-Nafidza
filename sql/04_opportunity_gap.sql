------------------------------------------------------------------------
-- 01. SPATIAL OPPORTUNITY GAP ANALYSIS (WHITESPACE MAPPING)
-- Identify high-density mobility grids that are more than 500m 
-- away from any existing billboard (Network Expansion Strategy).
------------------------------------------------------------------------

-- 1. Create Opportunity Gap Base Table
CREATE OR REPLACE TABLE `stickearn-test-502018.stickearn_test.opportunity_gap` AS
WITH grid_points AS (
  SELECT
    grid_lat, 
    grid_long, 
    point_count, 
    unique_devices,
    ST_GEOGPOINT(grid_long, grid_lat) AS grid_point
  FROM `stickearn-test-502018.stickearn_test.mobility_grid_density`
),
billboard_points AS (
  SELECT
    uuid AS billboard_id,
    ST_GEOGPOINT(longitude, latitude) AS b_point
  FROM `stickearn-test-502018.stickearn_test.billboard_data`
),
grid_min_distance AS (
  SELECT
    g.grid_lat, 
    g.grid_long, 
    g.point_count, 
    g.unique_devices,
    MIN(ST_DISTANCE(g.grid_point, b.b_point)) AS distance_to_nearest_billboard
  FROM grid_points g
  CROSS JOIN billboard_points b
  GROUP BY g.grid_lat, g.grid_long, g.point_count, g.unique_devices
)
SELECT
  *,
  CASE WHEN distance_to_nearest_billboard > 500 THEN TRUE ELSE FALSE END AS is_opportunity_gap
FROM grid_min_distance
ORDER BY point_count DESC;


------------------------------------------------------------------------
-- 02. WHITESPACE MARKET EVALUATION
-- Extract top recommended zones for new billboard placements 
-- and calculate the overall market gap percentage.
------------------------------------------------------------------------

-- 1. Top 30 Unserved High-Traffic Zones (Prime Locations for Expansion)
SELECT *
FROM `stickearn-test-502018.stickearn_test.opportunity_gap`
WHERE is_opportunity_gap = TRUE
ORDER BY point_count DESC
LIMIT 30;

-- 2. Overall Opportunity Gap Summary (Percentage of Unserved Zones)
SELECT
  COUNTIF(is_opportunity_gap = TRUE) AS total_gap_zones,
  COUNT(*) AS total_grid_zones,
  ROUND(COUNTIF(is_opportunity_gap = TRUE) / COUNT(*) * 100, 2) AS pct_gap_zones
FROM `stickearn-test-502018.stickearn_test.opportunity_gap`;
