-- Simple Idle Efficiency Metric
-- For comparing schedulers running the same TikTok workload
--
-- Key metric: DEEP_SLEEP_RATIO
--   = (Time in deep C-states C2+) / (Total trace time) × 100
--
-- Why this works:
--   - Same workload = similar work done
--   - More deep sleep = better energy efficiency
--   - Assumes you validate similar performance (no frame drops)
--
-- Higher percentage = More efficient scheduler

WITH trace_duration AS (
  SELECT CAST((trace_end() - trace_start()) / 1e9 AS REAL) AS duration_sec
),
deep_sleep AS (
  SELECT SUM(CAST(dur / 1e9 AS REAL)) AS deep_sec
  FROM counter_track ct
  JOIN counter c ON ct.id = c.track_id
  WHERE ct.name = 'cpuidle'
    AND c.value >= 2  -- C2 and deeper states
)
SELECT
  ROUND((ds.deep_sec / td.duration_sec) * 100, 2) AS deep_sleep_percentage,
  ROUND(ds.deep_sec, 2) AS deep_sleep_seconds,
  td.duration_sec AS trace_duration_seconds
FROM deep_sleep ds, trace_duration td;
