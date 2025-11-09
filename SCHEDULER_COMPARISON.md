# Scheduler Idle Policy Comparison Methodology

## The Single Metric: **Idle Efficiency Score**

Higher score = More efficient scheduler idle policy

## How to Use

### 1. Experimental Setup
```bash
# For each scheduler you want to compare:

# 1. Flash the kernel with the target scheduler
# 2. Reboot phone
# 3. Wait 2 minutes for system to stabilize
# 4. Clear all apps
# 5. Open TikTok
# 6. Start trace recording:
cd /home/sixigma/perfetto-traces
./record-trace.sh tiktok_scheduler_A system-trace-config.pbtx

# 7. Perform EXACT SAME workload:
#    - Scroll through 10 videos
#    - Each video: watch 5 seconds
#    - Total duration: ~60 seconds
#
# 8. Stop trace (automatic after 30s)
# 9. Repeat 3 times per scheduler for consistency
```

### 2. Run Analysis
```bash
# For each trace file:
cat test_idle.sql | ./trace_processor tiktok_scheduler_A_trace1.perfetto-trace
cat test_idle.sql | ./trace_processor tiktok_scheduler_B_trace1.perfetto-trace
```

### 3. Compare Scores

**Example Results:**
```
Scheduler CFS:    score = 0.85
Scheduler EEVDF:  score = 1.20
Scheduler Custom: score = 1.45
```

**Winner: Custom scheduler** (1.45) - 70% more efficient idle policy than CFS!

## What the Score Measures

### Formula
```
Score = (Weighted Idle Time) / (Trace Duration × CPU Count)

Weights:
- C-state 2+  (deep sleep)    → 3x weight
- C-state 1   (shallow sleep) → 1x weight
- C-state 0   (active)        → 0x weight
```

### Interpretation

**Score 1.5-3.0**: Excellent
- Scheduler aggressively consolidates work
- CPUs enter deep sleep states frequently
- "Race to idle" strategy working well

**Score 0.8-1.5**: Good
- Decent idle management
- Mostly shallow sleep states (C1)
- Moderate power efficiency

**Score 0.3-0.8**: Moderate
- CPUs frequently active or in very shallow sleep
- May indicate poor task packing
- Could have frequent wake-ups

**Score < 0.3**: Poor
- Very little idle time or only active states
- Scheduler keeping CPUs unnecessarily busy
- Likely power inefficient

## Important Controls

### ✓ What to Keep Constant:
1. **Same workload** - Use a script if possible
2. **Same duration** - 30-60 seconds recommended
3. **Same apps running** - Close all background apps
4. **Same power state** - Full battery, not charging
5. **Same temperature** - Let phone cool between tests
6. **Multiple runs** - At least 3 per scheduler, average the scores

### ✓ What to Validate:
1. **Performance** - Check frame drops, ensure no jank
2. **Completion time** - Workload should finish in similar time
3. **Battery drain** - Confirm score correlates with power usage

## Files

- **test_idle.sql** - The query (single-line, ready to run)
- **idle_score_final.sql** - Commented version with explanation
- **This file** - Methodology documentation

## Quick Command

```bash
# Run on a trace:
cat test_idle.sql | ./trace_processor your_trace.perfetto-trace

# Expected output:
# idle_efficiency_score | total_idle_sec | weighted_idle_sec | ...
#              1.234000 |       45.67000 |          123.45000| ...
```

The first column is your answer: **1.234** = The idle efficiency score

## Note on Your Current Trace

Your phone (Pixel 6a with 8 CPUs) only uses C0 and C1 states:
- C0: Active (197 events)
- C1: Shallow idle (1,895 events)
- No C2+ deep states observed

This is normal for modern Android devices. The score will still differentiate schedulers based on:
- How much time in C1 vs C0
- How quickly CPUs can enter C1
- How long C1 periods last (longer = better task consolidation)
