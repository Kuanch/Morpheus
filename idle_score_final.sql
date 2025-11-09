-- IDLE EFFICIENCY SCORE - Single Metric for Scheduler Comparison
--
-- Usage: Run TikTok with same workload on different schedulers,
--        record traces, and compare this score.
--
-- Higher score = More efficient scheduler idle policy
--
-- Methodology:
-- - Weights idle states: C2+=3pts, C1=1pt, C0/active=0pts
-- - Calculates weighted average across all CPUs
-- - Normalizes by trace duration
--
-- Score interpretation (for same workload):
--   Scheduler A: score=1.2, Scheduler B: score=0.8
--   → Scheduler A is 50% more efficient at idle management

WITH trace_info AS (
  SELECT
    CAST((trace_end() - trace_start()) / 1e9 AS REAL) AS duration_sec
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
    state,
    CASE
      WHEN state >= 2 AND state < 4000000000 THEN 3  -- Deep C-states (C2+)
      WHEN state = 1 THEN 1                           -- Shallow C-state (C1)
      ELSE 0                                          -- Active or exit event
    END AS weight
  FROM idle_events
  WHERE state < 4000000000  -- Exclude exit events (-1 = 4294967295)
),
weighted_idle AS (
  SELECT
    SUM(CAST((exit_ts - enter_ts) / 1e9 AS REAL) * weight) AS weighted_time,
    SUM(CAST((exit_ts - enter_ts) / 1e9 AS REAL)) AS total_idle_time,
    COUNT(DISTINCT cpu) AS num_cpus
  FROM idle_periods
  WHERE exit_ts IS NOT NULL
)
SELECT
  ROUND(w.weighted_time / (t.duration_sec * w.num_cpus), 3) AS idle_efficiency_score,
  ROUND(w.total_idle_time, 2) AS total_idle_seconds,
  ROUND(w.weighted_time, 2) AS weighted_idle_seconds,
  ROUND(t.duration_sec, 2) AS trace_duration_seconds,
  w.num_cpus AS cpu_count,
  ROUND((w.total_idle_time / (t.duration_sec * w.num_cpus)) * 100, 1) AS idle_time_pct
FROM weighted_idle w, trace_info t;
