# CPU Frequency vs Idle Time: Which Matters More?

## You're Right: Frequency is More Direct!

**Power Formula:**
```
Power = Capacitance × Voltage² × Frequency

Since Voltage scales with Frequency:
Power ≈ Frequency² to Frequency³
```

## Why This Matters

### Example: Two Schedulers Running TikTok

**Scheduler A (Race-to-idle strategy):**
- Bursts work at 2.4 GHz (max performance)
- Then goes idle
- Result: 70% idle, but high frequency when active

**Scheduler B (Energy-aware strategy):**
- Spreads work at 800 MHz (lower performance)
- Stays active longer
- Result: 40% idle, but low frequency when active

**My idle-only metric says:** A is better (70% > 40%)
**Reality:** B might use less power! (800 MHz uses ~1/9th power of 2.4 GHz)

## The Two Metrics You Should Use

### 1. Average CPU Frequency (Most Direct)
```bash
cat avg_cpu_frequency.sql | ... | ./trace_processor your_trace.perfetto-trace
```

**Output:**
```
avg_frequency_mhz: 494 MHz
min_frequency_mhz: 300 MHz
max_frequency_mhz: 2253 MHz
```

**Lower average = More efficient**

**Example comparison:**
- Scheduler CFS: 850 MHz average
- Scheduler Custom: 620 MHz average ← 27% more efficient!

### 2. Idle Percentage (Secondary validation)
```bash
cat simple_idle_percentage.sql | ... | ./trace_processor your_trace.perfetto-trace
```

**Output:**
```
idle_percentage: 98.29%
```

**Higher % = More idle time**

## Your Current Trace Results

```
Average Frequency: 494 MHz
Idle Time: 98.3%
```

**Interpretation:**
- Very efficient! Low frequency AND high idle
- CPUs spending most time idle, and when active using low-mid frequencies
- This is good baseline performance

## Recommended Methodology for TikTok Testing

### Compare THREE metrics:

1. **Average CPU Frequency** (Primary) - Lower is better
   - Most direct correlation to power
   - Captures DVFS efficiency

2. **Idle Percentage** (Secondary) - Higher is better
   - Shows task consolidation
   - Complements frequency data

3. **User Experience** (Validation) - Must be equal
   - Frame drops, jank, responsiveness
   - If UX is worse, efficiency doesn't matter!

### Example Results Table

| Scheduler | Avg Freq (MHz) | Idle % | Frame Drops | Winner? |
|-----------|----------------|--------|-------------|---------|
| CFS       | 850            | 85%    | 2           | -       |
| EEVDF     | 620            | 92%    | 1           | ✓ Best  |
| Custom    | 500            | 95%    | 15          | ✗ Worse UX |

## Why Both Metrics Matter

**Frequency alone isn't enough:**
```
Scheduler A: 500 MHz average, 50% idle
Scheduler B: 500 MHz average, 90% idle

Same frequency, but B is better! (more time fully off)
```

**Idle alone isn't enough:**
```
Scheduler A: 90% idle, 2400 MHz when active
Scheduler B: 80% idle, 600 MHz when active

More idle, but A uses 4x more power when active!
```

## Conclusion

You were absolutely right to question the idle-only metric!

**Use this ranking:**
1. **Average CPU Frequency** (best single metric)
2. **Idle Percentage** (good complementary metric)
3. **Combined score** (ideal but complex to calculate correctly)

For your Pixel 6a TikTok testing:
```bash
# Primary metric (use this!)
cat avg_cpu_frequency.sql | tr '\n' ' ' | sed 's/--.*//g' | ./trace_processor trace.perfetto-trace

# Secondary validation
cat simple_idle_percentage.sql | tr '\n' ' ' | sed 's/--.*//g' | ./trace_processor trace.perfetto-trace
```

Lower frequency + higher idle = Winner!
