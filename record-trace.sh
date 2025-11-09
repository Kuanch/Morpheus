#!/bin/bash
# Perfetto trace recording script for Pixel 6a

TRACE_NAME="${1:-trace}"
CONFIG="${2:-cpu-trace-config.pbtx}"
OUTPUT_FILE="${TRACE_NAME}_$(date +%Y%m%d_%H%M%S).perfetto-trace"

echo "Recording Perfetto trace..."
echo "Config: $CONFIG"
echo "Output: $OUTPUT_FILE"
echo ""

# Record trace using the config
if [ -f "$CONFIG" ]; then
    echo "Starting trace (this will take the duration specified in config)..."
    adb shell perfetto -c - --txt -o /data/misc/perfetto-traces/trace.perfetto-trace < "$CONFIG"

    # Pull the trace from device
    echo "Pulling trace from device..."
    adb pull /data/misc/perfetto-traces/trace.perfetto-trace "$OUTPUT_FILE"

    # Clean up device trace
    adb shell rm /data/misc/perfetto-traces/trace.perfetto-trace

    echo ""
    echo "Trace saved to: $OUTPUT_FILE"
    echo "View at: https://ui.perfetto.dev"
else
    echo "Error: Config file '$CONFIG' not found!"
    echo ""
    echo "Usage: $0 [trace-name] [config-file]"
    echo "Example: $0 my-trace cpu-trace-config.pbtx"
    exit 1
fi
