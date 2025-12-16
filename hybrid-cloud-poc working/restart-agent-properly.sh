#!/bin/bash
# Properly restart rust-keylime agent using the same method as test_complete.sh

set -e

echo "Stopping rust-keylime agent..."
pkill -f "keylime_agent" >/dev/null 2>&1 || true
sleep 2

echo "Starting rust-keylime agent..."
cd ~/dhanush/hybrid-cloud-poc-backup/rust-keylime

# Set environment variables
export KEYLIME_DIR="/tmp/keylime-agent"
export KEYLIME_AGENT_KEYLIME_DIR="/tmp/keylime-agent"
export KEYLIME_AGENT_CONFIG="$(pwd)/keylime-agent.conf"
export UNIFIED_IDENTITY_ENABLED=true
export USE_TPM2_QUOTE_DIRECT=1
export TCTI="device:/dev/tpmrm0"
export KEYLIME_AGENT_RUN_AS="$(whoami):$(id -gn)"

# Start agent
./target/release/keylime_agent > /tmp/rust-keylime-agent.log 2>&1 &
AGENT_PID=$!

echo "Agent started with PID: $AGENT_PID"
echo "Waiting for agent to be ready..."
sleep 5

# Check if agent is responding
if curl -k https://localhost:9002/v2.2/agent/version &>/dev/null; then
    echo "✅ Agent is responding!"
else
    echo "❌ Agent is not responding. Check logs:"
    echo "   tail -50 /tmp/rust-keylime-agent.log"
fi
