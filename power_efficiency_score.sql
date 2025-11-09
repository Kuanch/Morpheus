-- Power Efficiency Score - Combines CPU Frequency + Idle Time
-- This is MORE ACCURATE than idle-only metrics
--
-- Theory: Power ≈ Frequency³ (roughly, due to voltage scaling)
-- Lower score = More efficient (less power consumption)
--
-- Formula:
--   Weighted_Frequency = Σ(frequency × time) / total_time
--   For idle periods: frequency = 0
--   Normalized by max frequency to get 0-100 scale
--
-- Usage: Compare schedulers running same TikTok workload
--   Scheduler A: score = 45.2
--   Scheduler B: score = 38.7 ← More efficient (lower is better)

WITH trace_info AS (
  SELECT
    CAST((trace_end() - trace_start()) / 1e9 AS REAL) AS duration_sec,
    COUNT(DISTINCT cpu) AS num_cpus
  FROM ftrace_event
  WHERE name = 'cpu_frequency' OR name = 'cpu_idle'
),
cpu_freq_events AS (
  SELECT
    e.ts,
    e.cpu,
    CAST(a.int_value AS INTEGER) AS freq_khz
  FROM ftrace_event e
  JOIN args a ON e.arg_set_id = a.arg_set_id
  WHERE e.name = 'cpu_frequency' AND a.key = 'state'
),
cpu_idle_events AS (
  SELECT
    e.ts,
    e.cpu,
    CAST(a.int_value AS INTEGER) AS idle_state
  FROM ftrace_event e
  JOIN args a ON e.arg_set_id = a.arg_set_id
  WHERE e.name = 'cpu_idle' AND a.key = 'state'
),
all_events AS (
  SELECT ts, cpu, freq_khz, NULL AS idle_state, 'freq' AS event_type
  FROM cpu_freq_events
  UNION ALL
  SELECT ts, cpu, NULL AS freq_khz, idle_state, 'idle' AS event_type
  FROM cpu_idle_events
),
state_periods AS (
  SELECT
    cpu,
    ts AS start_ts,
    LEAD(ts) OVER (PARTITION BY cpu ORDER BY ts) AS end_ts,
    COALESCE(freq_khz, LAG(freq_khz) OVER (PARTITION BY cpu ORDER BY ts)) AS freq_khz,
    COALESCE(idle_state, LAG(idle_state) OVER (PARTITION BY cpu ORDER BY ts)) AS idle_state
  FROM all_events
),
weighted_freq AS (
  SELECT
    cpu,
    CASE
      WHEN idle_state > 0 AND idle_state < 4000000000 THEN 0
      ELSE COALESCE(freq_khz, 0)
    END AS effective_freq,
    CAST((end_ts - start_ts) / 1e9 AS REAL) AS duration_sec
  FROM state_periods
  WHERE end_ts IS NOT NULL
),
avg_freq_per_cpu AS (
  SELECT
    cpu,
    SUM(effective_freq * duration_sec) / SUM(duration_sec) AS avg_freq_khz
  FROM weighted_freq
  GROUP BY cpu
),
max_freq AS (
  SELECT MAX(freq_khz) AS max_freq_khz FROM cpu_freq_events
)
SELECT
  ROUND(AVG(a.avg_freq_khz / m.max_freq_khz) * 100, 2) AS power_efficiency_score,
  ROUND(AVG(a.avg_freq_khz) / 1000, 0) AS avg_frequency_mhz,
  ROUND(m.max_freq_khz / 1000, 0) AS max_frequency_mhz,
  t.num_cpus AS cpu_count,
  t.duration_sec AS trace_duration_sec
FROM avg_freq_per_cpu a, max_freq m, trace_info t
GROUP BY m.max_freq_khz, t.num_cpus, t.duration_sec;
