#!/bin/bash
# Watch mTLS server logs in real-time
# Usage: ./scripts/watch-mtls-server-logs.sh

LOG_FILE="/tmp/mtls-server.log"

echo "=========================================="
echo "Watching mTLS Server Logs"
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

