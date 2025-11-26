#!/bin/bash
# Periodic tail for SPIRE Agent log
# Usage: ./monitor-spire-agent.sh [interval_seconds]

INTERVAL=${1:-3}  # Default: 3 seconds

echo "Monitoring SPIRE Agent log every ${INTERVAL} seconds..."
echo "Press Ctrl+C to exit"
echo ""

while true; do
  clear
  echo "════════════════════════════════════════════════════════════════"
  echo "  SPIRE Agent Log - $(date '+%Y-%m-%d %H:%M:%S')"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  tail -20 /tmp/spire-agent.log 2>/dev/null || echo "  [Log file not found]"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  Refreshing in ${INTERVAL} seconds... (Ctrl+C to exit)"
  echo "════════════════════════════════════════════════════════════════"
  sleep "$INTERVAL"
done

