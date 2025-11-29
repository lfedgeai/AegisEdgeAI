#!/bin/bash
# Periodic tail for Client Workload log
# Usage: ./monitor-client-workload.sh [interval_seconds]

INTERVAL=${1:-1}  # Default: 3 seconds

echo "Monitoring Client Workload log every ${INTERVAL} seconds..."
echo "Press Ctrl+C to exit"
echo ""

while true; do
  clear
  echo "════════════════════════════════════════════════════════════════"
  echo "  Client Workload Log - $(date '+%Y-%m-%d %H:%M:%S')"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  tail -50 /tmp/mtls-client-app.log 2>/dev/null || echo "  [Log file not found]"
  tail -50 /tmp/mtls-client-app.log | grep -i hello
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  Refreshing in ${INTERVAL} seconds... (Ctrl+C to exit)"
  echo "════════════════════════════════════════════════════════════════"
  sleep "$INTERVAL"
done

