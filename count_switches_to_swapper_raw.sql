-- Alternative: Count sched_switch events to swapper using raw ftrace events
-- This counts the actual sched_switch events where next_pid = 0

WITH trace_bounds AS (
  SELECT
    CAST((trace_end() - trace_start()) / 1e9 AS REAL) AS duration_sec
),
switches_to_swapper AS (
  SELECT COUNT(*) AS total
  FROM ftrace_event
  WHERE name = 'sched_switch'
    AND CAST(STR_SPLIT(args, 'next_pid=', 1) AS INTEGER) = 0
)
SELECT
  s.total AS total_switches_to_swapper,
  t.duration_sec AS trace_duration_sec,
  ROUND(CAST(s.total AS REAL) / t.duration_sec, 2) AS switches_per_sec
FROM switches_to_swapper s, trace_bounds t;
