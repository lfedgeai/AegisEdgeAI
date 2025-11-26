#!/bin/bash
# Periodic tail for Server Workload log
# Usage: ./monitor-server-workload.sh [interval_seconds]

INTERVAL=${1:-3}  # Default: 3 seconds

echo "Monitoring Server Workload log every ${INTERVAL} seconds..."
echo "Press Ctrl+C to exit"
echo ""

while true; do
  clear
  echo "════════════════════════════════════════════════════════════════"
  echo "  Server Workload Log - $(date '+%Y-%m-%d %H:%M:%S')"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  tail -20 /tmp/mtls-server-app.log 2>/dev/null || echo "  [Log file not found]"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  Refreshing in ${INTERVAL} seconds... (Ctrl+C to exit)"
  echo "════════════════════════════════════════════════════════════════"
  sleep "$INTERVAL"
done

