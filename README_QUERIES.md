# Perfetto SQL Queries

## Running SQL Queries on Traces

You can run SQL queries on your traces using the Perfetto UI or command-line tools.

### Method 1: Perfetto UI (Recommended)

1. Open https://ui.perfetto.dev
2. Load your trace file
3. Click "Query (SQL)" in the left sidebar
4. Paste the SQL query
5. Click "Execute" or press Ctrl+Enter

### Method 2: Command Line (trace_processor_shell)

```bash
# Download trace processor
curl -LO https://get.perfetto.dev/trace_processor

# Make it executable
chmod +x trace_processor

# Run query on trace
./trace_processor trace_20251108_153537.perfetto-trace < count_swapper_switches.sql
```

## Available Queries

### 1. Count Switches to Swapper (`count_swapper_switches.sql`)

Counts how many times the scheduler switched to the idle thread (swapper).

**What it measures:**
- Total number of times CPUs went idle
- Average idle transitions per second

**Output columns:**
- `total_swapper_switches` - Total count
- `trace_duration_sec` - Trace duration in seconds
- `switches_per_sec` - Rate of switches to idle

### Usage

Simply copy and paste the query into Perfetto UI's SQL tab, or run via command line.

**Example output:**
```
total_swapper_switches | trace_duration_sec | switches_per_sec
4523                   | 10                 | 452.3
```

This means the CPUs went idle 4,523 times over 10 seconds, averaging 452.3 idle transitions per second.
