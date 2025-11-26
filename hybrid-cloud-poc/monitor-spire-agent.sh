#!/bin/bash
# Periodic tail for SPIRE Agent log
# Usage: ./monitor-spire-agent.sh [interval_seconds]

tail -1 /tmp/spire-agent.log 2>/dev/null || echo "  [Log file not found]"

watch -n 5 'grep "Successfully rotated agent SVID" /tmp/spire-agent.log | wc -l'
