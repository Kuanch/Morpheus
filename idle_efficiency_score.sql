-- Idle Policy Efficiency Score
-- Single metric to compare scheduler efficiency for same workload
-- Higher score = better scheduler (more efficient idle policy)
--
-- Theory: Efficient schedulers "race to idle" - complete work quickly,
-- then enter DEEP sleep states (C2, C3+) for longer periods.
-- Poor schedulers keep CPUs in shallow sleep or cause frequent wake/sleep.
--
-- Score formula:
--   (Deep_C3_time × 3 + Medium_C2_time × 2 + Shallow_C1_time × 1) / Total_time
--
-- Interpretation:
--   Score > 1.5: Excellent idle policy (lots of deep sleep)
--   Score 1.0-1.5: Good idle policy
--   Score 0.5-1.0: Moderate idle policy
--   Score < 0.5: Poor idle policy (shallow sleep, frequent waking)

WITH cpu_count AS (
  SELECT COUNT(DISTINCT cpu) AS num_cpus FROM counter WHERE name = 'cpuidle'
),
trace_duration AS (
  SELECT CAST((trace_end() - trace_start()) / 1e9 AS REAL) AS duration_sec
),
idle_states AS (
  SELECT
    value AS state,
    CAST(dur / 1e9 AS REAL) AS duration_sec,
    CASE
      WHEN value >= 3 THEN 3  -- Deep C-states (highest weight)
      WHEN value = 2 THEN 2   -- Medium C-state
      WHEN value = 1 THEN 1   -- Shallow C-state
      ELSE 0                  -- Active or unknown
    END AS weight
  FROM counter_track ct
  JOIN counter c ON ct.id = c.track_id
  WHERE ct.name = 'cpuidle'
    AND c.value >= 0  -- Exclude exit events (value = -1)
),
weighted_idle AS (
  SELECT SUM(duration_sec * weight) AS weighted_idle_time
  FROM idle_states
),
deep_sleep_time AS (
  SELECT SUM(duration_sec) AS deep_sec
  FROM idle_states
  WHERE weight >= 2  -- C2 and above
),
total_idle_time AS (
  SELECT SUM(duration_sec) AS total_idle_sec
  FROM idle_states
  WHERE weight > 0
)
SELECT
  ROUND(wi.weighted_idle_time / (td.duration_sec * cc.num_cpus), 3) AS efficiency_score,
  ROUND(ds.deep_sec, 2) AS deep_sleep_sec,
  ROUND(ti.total_idle_sec, 2) AS total_idle_sec,
  td.duration_sec AS trace_duration_sec,
  cc.num_cpus AS num_cpus,
  ROUND((ds.deep_sec / ti.total_idle_sec) * 100, 1) AS deep_sleep_pct,
  ROUND((ti.total_idle_sec / td.duration_sec) * 100, 1) AS idle_pct
FROM weighted_idle wi, trace_duration td, cpu_count cc, deep_sleep_time ds, total_idle_time ti;
