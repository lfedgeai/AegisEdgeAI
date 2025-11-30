#!/bin/bash
# Periodic tail for SPIRE Agent log
# Usage: ./monitor-spire-agent.sh [interval_seconds]

INTERVAL="${1:-5}"

# Check if unified_identity is enabled (default: true)
UNIFIED_IDENTITY_ENABLED="${UNIFIED_IDENTITY_ENABLED:-true}"

tail -1 /tmp/spire-agent.log 2>/dev/null || echo "  [Log file not found]"

if [ "${UNIFIED_IDENTITY_ENABLED}" = "true" ]; then
    # unified_identity: Agent SVID uses reattestation only (no rotation)
    echo "Monitoring agent SVID reattestations (unified_identity enabled)..."
    watch -n "$INTERVAL" 'grep "Successfully reattested node" /tmp/spire-agent.log | wc -l'
else
    # Non-reattestable: Agent SVID uses rotation
    echo "Monitoring agent SVID rotations..."
    watch -n "$INTERVAL" 'grep "Successfully rotated agent SVID" /tmp/spire-agent.log | wc -l'
fi
