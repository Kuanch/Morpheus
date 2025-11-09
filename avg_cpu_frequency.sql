-- Average CPU Frequency - Better power metric than idle time alone
-- Lower average frequency = More power efficient
--
-- This metric captures DVFS (Dynamic Voltage Frequency Scaling) efficiency
-- Power ≈ Voltage² × Frequency, and Voltage scales with Frequency
-- So: Power ≈ Frequency³ (approximately)
--
-- Usage: Lower average MHz = more efficient scheduler

WITH trace_duration AS (
  SELECT CAST((trace_end() - trace_start()) / 1e9 AS REAL) AS duration_sec
),
freq_events AS (
  SELECT
    e.ts,
    e.cpu,
    CAST(a.int_value AS INTEGER) AS freq_khz
  FROM ftrace_event e
  JOIN args a ON e.arg_set_id = a.arg_set_id
  WHERE e.name = 'cpu_frequency' AND a.key = 'state'
),
freq_periods AS (
  SELECT
    cpu,
    freq_khz,
    ts AS start_ts,
    LEAD(ts) OVER (PARTITION BY cpu ORDER BY ts) AS end_ts
  FROM freq_events
),
time_at_freq AS (
  SELECT
    freq_khz,
    SUM(CAST((end_ts - start_ts) / 1e9 AS REAL)) AS time_sec
  FROM freq_periods
  WHERE end_ts IS NOT NULL
  GROUP BY freq_khz
)
SELECT
  ROUND(SUM(freq_khz * time_sec) / SUM(time_sec) / 1000, 0) AS avg_frequency_mhz,
  ROUND(MIN(freq_khz) / 1000, 0) AS min_frequency_mhz,
  ROUND(MAX(freq_khz) / 1000, 0) AS max_frequency_mhz,
  ROUND(SUM(time_sec), 2) AS total_time_sec,
  (SELECT duration_sec FROM trace_duration) AS trace_duration_sec
FROM time_at_freq;
