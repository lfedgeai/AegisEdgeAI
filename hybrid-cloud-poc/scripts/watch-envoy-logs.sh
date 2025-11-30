#!/bin/bash
# Watch Envoy logs in real-time
# Usage: ./scripts/watch-envoy-logs.sh

LOG_FILE="/opt/envoy/logs/envoy.log"

echo "=========================================="
echo "Watching Envoy Logs"
echo "=========================================="
echo "Log file: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo "=========================================="
echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo "Warning: Log file not found: $LOG_FILE"
    echo "Waiting for log file to be created..."
    while [ ! -f "$LOG_FILE" ]; do
        sleep 1
    done
    echo "Log file created, starting to watch..."
fi

tail -f "$LOG_FILE"

