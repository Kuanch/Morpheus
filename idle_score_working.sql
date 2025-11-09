-- Idle Efficiency Score (Single Metric for Scheduler Comparison)
--
-- Methodology:
-- 1. Run TikTok with same workload on different schedulers
-- 2. Record trace for each
-- 3. Compare this ONE metric
--
-- Higher score = Better scheduler idle policy
--
-- Formula: (Time in deep idle states) / (Total trace time) × 100
-- Deep idle = C-state >= 2 (excludes shallow C1 and active states)

WITH trace_info AS (
  SELECT
    CAST((trace_end() - trace_start()) / 1e9 AS REAL) AS duration_sec,
    trace_start() AS start_ts,
    trace_end() AS end_ts
),
idle_events AS (
  SELECT
    e.ts,
    e.cpu,
    CAST(a.int_value AS INTEGER) AS state
  FROM ftrace_event e
  JOIN args a ON e.arg_set_id = a.arg_set_id
  WHERE e.name = 'cpu_idle'
    AND a.key = 'state'
),
idle_periods AS (
  SELECT
    cpu,
    ts AS enter_ts,
    LEAD(ts) OVER (PARTITION BY cpu ORDER BY ts) AS exit_ts,
    state,
    CASE WHEN state >= 2 AND state < 4294967295 THEN 1 ELSE 0 END AS is_deep_idle
  FROM idle_events
),
deep_idle_time AS (
  SELECT
    SUM(CAST((exit_ts - enter_ts) / 1e9 AS REAL)) AS total_deep_sec
  FROM idle_periods
  WHERE is_deep_idle = 1
    AND exit_ts IS NOT NULL
)
SELECT
  ROUND((d.total_deep_sec / t.duration_sec) * 100, 2) AS idle_efficiency_score,
  ROUND(d.total_deep_sec, 2) AS deep_sleep_seconds,
  ROUND(t.duration_sec, 2) AS trace_duration_seconds,
  ROUND((d.total_deep_sec / t.duration_sec) * 100, 1) AS deep_sleep_percentage
FROM deep_idle_time d, trace_info t;
