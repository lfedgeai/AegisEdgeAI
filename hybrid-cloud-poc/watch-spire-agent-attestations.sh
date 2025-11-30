#!/bin/bash
# Watch SPIRE Agent attestation events in real-time
# Filters for attestation-related log entries
# Usage: ./watch-spire-agent-attestations.sh

LOG_FILE="/tmp/spire-agent.log"

echo "=========================================="
echo "Watching SPIRE Agent Attestation Events"
echo "=========================================="
echo "Log file: $LOG_FILE"
echo "Filtering for: TPM Plugin, SovereignAttestation, TPM Quote, Agent SVID, Workload, Unified-Identity, attest"
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

# Count successful reattestations
REATTEST_COUNT=$(grep -c 'level=info msg="Successfully reattested node"' "$LOG_FILE" 2>/dev/null || echo "0")
echo "Current reattestation count: $REATTEST_COUNT"
echo "=========================================="
echo ""

# Watch log file and update count when reattestation occurs
tail -f "$LOG_FILE" | while IFS= read -r line; do
    # Check if this line matches our filter
    if echo "$line" | grep -qE "TPM Plugin|SovereignAttestation|TPM Quote|certificate|Agent SVID|Workload|Unified-Identity|attest|python-app|BatchNewX509SVID"; then
        echo "$line"
        # If this is a reattestation message, update and show count
        if echo "$line" | grep -q 'level=info msg="Successfully reattested node"'; then
            REATTEST_COUNT=$((REATTEST_COUNT + 1))
            echo "--- Reattestation count: $REATTEST_COUNT ---"
        fi
    fi
done

