#!/bin/bash
# Watch mobile sensor service logs in real-time
# Usage: ./scripts/watch-mobile-sensor-logs.sh

LOG_FILE="/tmp/mobile-sensor.log"

echo "=========================================="
echo "Watching Mobile Sensor Service Logs"
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

