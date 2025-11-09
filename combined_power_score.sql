-- Combined Power Efficiency Score
-- THE BEST SINGLE METRIC: Combines CPU frequency + idle time
--
-- Theory: Power has two components:
--   1. When active: Power ≈ Frequency³
--   2. When idle: Power ≈ 0
--
-- This metric: Time-weighted average frequency (treating idle as freq=0)
--
-- Lower score = More efficient
-- Score = Average effective frequency across all CPUs (MHz)
--
-- "Effective frequency" = actual freq when active, 0 when idle

WITH freq_events AS (
  SELECT
    e.ts,
    e.cpu,
    CAST(a.int_value AS INTEGER) AS freq_khz
  FROM ftrace_event e
  JOIN args a ON e.arg_set_id = a.arg_set_id
  WHERE e.name = 'cpu_frequency' AND a.key = 'state'
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
combined_events AS (
  SELECT ts, cpu, 'freq' AS type, freq_khz AS value FROM freq_events
  UNION ALL
  SELECT ts, cpu, 'idle' AS type, state AS value FROM idle_events
  ORDER BY cpu, ts
),
state_tracking AS (
  SELECT
    cpu,
    ts,
    type,
    value,
    LEAD(ts) OVER (PARTITION BY cpu ORDER BY ts) AS next_ts,
    LAG(type) OVER (PARTITION BY cpu ORDER BY ts) AS prev_type,
    LAG(value) OVER (PARTITION BY cpu ORDER BY ts) AS prev_value
  FROM combined_events
),
cpu_states AS (
  SELECT
    cpu,
    ts AS start_ts,
    next_ts AS end_ts,
    CASE
      WHEN type = 'freq' THEN value
      WHEN prev_type = 'freq' THEN prev_value
      ELSE 0
    END AS freq_khz,
    CASE
      WHEN type = 'idle' AND value > 0 AND value < 4000000000 THEN 1
      WHEN prev_type = 'idle' AND prev_value > 0 AND prev_value < 4000000000 THEN 1
      ELSE 0
    END AS is_idle
  FROM state_tracking
  WHERE next_ts IS NOT NULL
),
effective_freq AS (
  SELECT
    cpu,
    CASE WHEN is_idle = 1 THEN 0 ELSE freq_khz END AS eff_freq_khz,
    CAST((end_ts - start_ts) / 1e9 AS REAL) AS duration_sec
  FROM cpu_states
)
SELECT
  ROUND(SUM(eff_freq_khz * duration_sec) / SUM(duration_sec) / 1000, 0) AS power_score_mhz,
  COUNT(DISTINCT cpu) AS cpu_count,
  ROUND(SUM(duration_sec) / COUNT(DISTINCT cpu), 2) AS trace_duration_sec
FROM effective_freq;
