-- Simple Idle Percentage (Single Metric for Pixel 6a Scheduler Comparison)
-- Higher percentage = More efficient scheduler
-- This version doesn't use weights since Pixel 6a only has C0/C1 states

WITH trace_info AS (
  SELECT CAST((trace_end() - trace_start()) / 1e9 AS REAL) AS duration_sec
),
idle_events AS (
  SELECT
    e.ts,
    e.cpu,
    CAST(a.int_value AS INTEGER) AS state
  FROM ftrace_event e
  JOIN args a ON e.arg_set_id = a.arg_set_id
  WHERE e.name = 'cpu_idle' AND a.key = 'state'
),
idle_periods AS (
  SELECT
    cpu,
    ts AS enter_ts,
    LEAD(ts) OVER (PARTITION BY cpu ORDER BY ts) AS exit_ts,
    state
  FROM idle_events
  WHERE state > 0 AND state < 4000000000
),
total_idle AS (
  SELECT
    SUM(CAST((exit_ts - enter_ts) / 1e9 AS REAL)) AS idle_time,
    COUNT(DISTINCT cpu) AS num_cpus
  FROM idle_periods
  WHERE exit_ts IS NOT NULL
)
SELECT
  ROUND((i.idle_time / (t.duration_sec * i.num_cpus)) * 100, 2) AS idle_percentage,
  ROUND(i.idle_time, 2) AS total_idle_seconds,
  ROUND(t.duration_sec, 2) AS trace_duration_seconds,
  i.num_cpus AS cpu_count
FROM total_idle i, trace_info t;
