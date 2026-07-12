------------------------------------------------------------------------
-- 12. TEMPORAL EXPOSURE ANALYSIS (TIME-OF-DAY PERFORMANCE)
-- Analyze how billboard exposure (impressions and reach) fluctuates 
-- across different hours of the day.
------------------------------------------------------------------------
SELECT
  billboard_id,
  billboard_name,
  EXTRACT(HOUR FROM datetime) AS hour_of_day,
  COUNT(*) AS impressions,
  COUNT(DISTINCT device_id) AS reach
FROM `stickearn-test-502018.stickearn_test.exposure_proximity`
WHERE within_100m = TRUE
GROUP BY billboard_id, billboard_name, hour_of_day
ORDER BY billboard_id, hour_of_day;

SELECT 
  billboard_id, 
  billboard_name, 
  COUNT(*) AS impressions_at_hour19
FROM `stickearn-test-502018.stickearn_test.exposure_proximity`
WHERE within_100m = TRUE AND EXTRACT(HOUR FROM datetime) = 19
GROUP BY billboard_id, billboard_name
ORDER BY impressions_at_hour19 DESC
LIMIT 10;
