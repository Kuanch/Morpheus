#!/bin/bash
# Run SQL query on a Perfetto trace file

TRACE_FILE="${1:-trace_20251108_153537.perfetto-trace}"
SQL_QUERY="$2"

if [ -z "$SQL_QUERY" ]; then
    echo "Usage: $0 <trace-file> <sql-query-file-or-string>"
    echo ""
    echo "Examples:"
    echo "  $0 trace.perfetto-trace swapper_switches_simple.sql"
    echo "  $0 trace.perfetto-trace \"SELECT COUNT(*) FROM sched_slice\""
    exit 1
fi

# Check if SQL_QUERY is a file
if [ -f "$SQL_QUERY" ]; then
    # Convert multi-line SQL to single line
    SQL_CMD=$(cat "$SQL_QUERY" | grep -v '^--' | tr '\n' ' ' | sed 's/  */ /g')
else
    SQL_CMD="$SQL_QUERY"
fi

echo "Running query on: $TRACE_FILE"
echo ""
echo "$SQL_CMD" | ./trace_processor "$TRACE_FILE"
