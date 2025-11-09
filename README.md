# Perfetto Tracing Setup for Pixel 6a

Your environment is ready for recording Perfetto performance traces!

## Quick Start

```bash
cd /home/sixigma/perfetto-traces
./record-trace.sh
```

This will record a 10-second CPU trace and save it locally.

## Available Configs

1. **cpu-trace-config.pbtx** - Lightweight CPU and scheduling trace (10s)
2. **system-trace-config.pbtx** - Comprehensive system trace with CPU, memory, battery, GPU (30s)

## Usage Examples

```bash
# Record a CPU trace with default name
./record-trace.sh

# Record with custom name
./record-trace.sh my-cpu-trace

# Record comprehensive system trace
./record-trace.sh system-trace system-trace-config.pbtx
```

## Manual Recording (Advanced)

```bash
# Record trace directly
adb shell perfetto -c - --txt -o /data/misc/perfetto-traces/trace.perfetto-trace < cpu-trace-config.pbtx

# Pull trace from device
adb pull /data/misc/perfetto-traces/trace.perfetto-trace ./my-trace.perfetto-trace

# Clean up
adb shell rm /data/misc/perfetto-traces/trace.perfetto-trace
```

## View Traces

Upload your `.perfetto-trace` files to: **https://ui.perfetto.dev**

## Phone Info

- Device: Pixel 6a (bluejay)
- Serial: 26141JEGR17358
- Perfetto Version: v50.1

## Trace Storage

All traces are saved in: `/home/sixigma/perfetto-traces/`

## Windows Access

Access from Windows File Explorer: `\\wsl$\Ubuntu\home\sixigma\perfetto-traces\`
