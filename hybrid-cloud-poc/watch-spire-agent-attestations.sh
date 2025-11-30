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

tail -f "$LOG_FILE" | grep -E --line-buffered "TPM Plugin|SovereignAttestation|TPM Quote|certificate|Agent SVID|Workload|Unified-Identity|attest|python-app|BatchNewX509SVID"

