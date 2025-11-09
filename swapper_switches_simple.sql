-- Simple query: Count switches to swapper/idle thread
SELECT
  COUNT(*) AS total_switches_to_swapper,
  CAST((trace_end() - trace_start()) / 1e9 AS INTEGER) AS duration_seconds,
  ROUND(CAST(COUNT(*) AS REAL) / ((trace_end() - trace_start()) / 1e9), 2) AS switches_per_second
FROM sched_slice
WHERE utid IN (SELECT utid FROM thread WHERE tid = 0);
