-- Count CFS sched_switch events to swapper (idle thread)
-- This query counts how many times threads are switched out for the idle thread

WITH trace_bounds AS (
  SELECT
    CAST((trace_end() - trace_start()) / 1e9 AS INTEGER) AS duration_sec
),
swapper_switches AS (
  SELECT COUNT(*) AS total_switches
  FROM sched_slice
  WHERE utid IN (
    SELECT utid
    FROM thread
    WHERE tid = 0  -- swapper has tid 0
  )
)
SELECT
  s.total_switches AS total_swapper_switches,
  t.duration_sec AS trace_duration_sec,
  CAST(s.total_switches AS REAL) / t.duration_sec AS switches_per_sec
FROM swapper_switches s, trace_bounds t;
