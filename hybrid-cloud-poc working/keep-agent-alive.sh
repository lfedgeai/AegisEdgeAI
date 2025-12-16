#!/bin/bash
# Keep rust-keylime agent alive - restart if it dies
# This is a workaround until we fix the root cause

set -euo pipefail

AGENT_DIR="/tmp/keylime-agent"
AGENT_LOG="/tmp/rust-keylime-agent.log"
AGENT_BIN="./rust-keylime/target/release/keylime_agent"
MAX_RESTARTS=10
RESTART_COUNT=0

# Export required environment variables
export KEYLIME_DIR="$AGENT_DIR"
export KEYLIME_AGENT_KEYLIME_DIR="$AGENT_DIR"
export USE_TPM2_QUOTE_DIRECT=1
export TCTI="device:/dev/tpmrm0"
export UNIFIED_IDENTITY_ENABLED=true

echo "Starting rust-keylime agent with auto-restart..."
echo "Max restarts: $MAX_RESTARTS"
echo "Log file: $AGENT_LOG"
echo ""

while [ $RESTART_COUNT -lt $MAX_RESTARTS ]; do
    echo "[$(date)] Starting agent (attempt $((RESTART_COUNT + 1))/$MAX_RESTARTS)..."
    
    # Start agent in background
    $AGENT_BIN >> "$AGENT_LOG" 2>&1 &
    AGENT_PID=$!
    
    echo "[$(date)] Agent started with PID: $AGENT_PID"
    
    # Wait for agent to exit
    wait $AGENT_PID
    EXIT_CODE=$?
    
    echo "[$(date)] Agent exited with code: $EXIT_CODE"
    
    # Check if it was a clean exit (code 0) or crash
    if [ $EXIT_CODE -eq 0 ]; then
        echo "[$(date)] Agent exited cleanly (code 0) - this shouldn't happen!"
        echo "[$(date)] Agent should run indefinitely until SIGINT/SIGTERM"
    else
        echo "[$(date)] Agent crashed with exit code: $EXIT_CODE"
    fi
    
    RESTART_COUNT=$((RESTART_COUNT + 1))
    
    if [ $RESTART_COUNT -lt $MAX_RESTARTS ]; then
        echo "[$(date)] Restarting in 2 seconds..."
        sleep 2
    fi
done

echo "[$(date)] Max restarts ($MAX_RESTARTS) reached. Giving up."
echo "[$(date)] Check logs at: $AGENT_LOG"
exit 1
