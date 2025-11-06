#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Script to rejoin SPIRE Agent (evict old agent and join with new token)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${SCRIPT_DIR}/../spire"
SERVER_SOCKET="/tmp/spire-server/private/api.sock"

echo "Unified-Identity - Phase 1: Rejoining SPIRE Agent"
echo ""

# Step 1: Get current agent SPIFFE ID
echo "Step 1: Getting current agent SPIFFE ID..."
AGENT_LIST=$("${SPIRE_DIR}/bin/spire-server" agent list -socketPath "$SERVER_SOCKET" 2>&1)

# Parse SPIFFE ID from the output (format: "SPIFFE ID         : spiffe://...")
# Method 1: Use awk to split on ": " and get the second field, then take first word
CURRENT_AGENT_ID=$(echo "$AGENT_LIST" | grep "SPIFFE ID" | awk -F': ' '/SPIFFE ID/ {print $2}' | awk '{print $1}' | head -1)

# Method 2: If that didn't work, try sed
if [ -z "$CURRENT_AGENT_ID" ] || [ "$CURRENT_AGENT_ID" = ":" ]; then
    CURRENT_AGENT_ID=$(echo "$AGENT_LIST" | grep "SPIFFE ID" | sed -n 's/.*SPIFFE ID[[:space:]]*:[[:space:]]*\(spiffe:[^[:space:]]*\).*/\1/p' | head -1)
fi

# Method 3: If still empty, try grep with Perl regex (if available)
if [ -z "$CURRENT_AGENT_ID" ] || [ "$CURRENT_AGENT_ID" = ":" ]; then
    CURRENT_AGENT_ID=$(echo "$AGENT_LIST" | grep -oP 'SPIFFE ID\s+:\s+\K[^\s]+' | head -1) 2>/dev/null || true
fi

# Validate the SPIFFE ID
if [ -z "$CURRENT_AGENT_ID" ] || [ "$CURRENT_AGENT_ID" = ":" ] || [[ ! "$CURRENT_AGENT_ID" == spiffe://* ]]; then
    echo "⚠ No agent found. Starting fresh agent join..."
    CURRENT_AGENT_ID=""
else
    echo "  Found agent: $CURRENT_AGENT_ID"
fi

# Step 2: Stop current agent
echo ""
echo "Step 2: Stopping current SPIRE Agent..."
if [ -f /tmp/spire-agent.pid ]; then
    pid=$(cat /tmp/spire-agent.pid)
    if ps -p "$pid" > /dev/null 2>&1; then
        echo "  Stopping agent (PID: $pid)..."
        kill "$pid" 2>/dev/null || true
        sleep 2
        # Force kill if still running
        if ps -p "$pid" > /dev/null 2>&1; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
    rm -f /tmp/spire-agent.pid
fi
pkill -f "spire-agent" >/dev/null 2>&1 || true
sleep 1
echo "  ✓ Agent stopped"

# Step 3: Evict agent from server (if it exists)
if [ -n "$CURRENT_AGENT_ID" ] && [ "$CURRENT_AGENT_ID" != ":" ] && [[ "$CURRENT_AGENT_ID" == spiffe://* ]]; then
    echo ""
    echo "Step 3: Evicting agent from server..."
    EVICT_OUTPUT=$("${SPIRE_DIR}/bin/spire-server" agent evict -spiffeID "$CURRENT_AGENT_ID" -socketPath "$SERVER_SOCKET" 2>&1)
    EVICT_EXIT=$?
    if [ $EVICT_EXIT -eq 0 ]; then
        echo "  ✓ Agent evicted successfully"
    else
        echo "  ⚠ Failed to evict agent (may already be evicted or not exist)"
        echo "  Error output: $EVICT_OUTPUT"
    fi
else
    echo ""
    echo "Step 3: Skipping eviction (no valid agent found)"
fi

# Step 4: Generate new join token
echo ""
echo "Step 4: Generating new join token..."
JOIN_TOKEN_OUTPUT=$("${SPIRE_DIR}/bin/spire-server" token generate \
    -spiffeID spiffe://example.org/host/external-agent \
    -socketPath "$SERVER_SOCKET" 2>&1)

JOIN_TOKEN=$(echo "$JOIN_TOKEN_OUTPUT" | grep -oP 'Token:\s+\K[^\s]+' || \
             echo "$JOIN_TOKEN_OUTPUT" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)

if [ -z "$JOIN_TOKEN" ]; then
    echo "  ✗ Failed to generate join token"
    echo "  Output: $JOIN_TOKEN_OUTPUT"
    exit 1
fi

echo "  ✓ Join token generated: $JOIN_TOKEN"

# Step 5: Start agent with new token
echo ""
echo "Step 5: Starting SPIRE Agent with new token..."
"${SPIRE_DIR}/bin/spire-agent" run \
    -config "${SCRIPT_DIR}/spire-agent/agent.conf" \
    -joinToken "$JOIN_TOKEN" > /tmp/spire-agent.log 2>&1 &
SPIRE_AGENT_PID=$!
echo $SPIRE_AGENT_PID > /tmp/spire-agent.pid
sleep 5
echo "  ✓ SPIRE Agent started (PID: $SPIRE_AGENT_PID)"

# Step 6: Verify agent joined
echo ""
echo "Step 6: Verifying agent joined..."
sleep 3
AGENT_LIST_NEW=$("${SPIRE_DIR}/bin/spire-server" agent list -socketPath "$SERVER_SOCKET" 2>&1)

# Parse SPIFFE ID from the output (format: "SPIFFE ID         : spiffe://...")
# Method 1: Use awk to split on ": " and get the second field, then take first word
NEW_AGENT_ID=$(echo "$AGENT_LIST_NEW" | grep "SPIFFE ID" | awk -F': ' '/SPIFFE ID/ {print $2}' | awk '{print $1}' | head -1)

# Method 2: If that didn't work, try sed
if [ -z "$NEW_AGENT_ID" ] || [ "$NEW_AGENT_ID" = ":" ]; then
    NEW_AGENT_ID=$(echo "$AGENT_LIST_NEW" | grep "SPIFFE ID" | sed -n 's/.*SPIFFE ID[[:space:]]*:[[:space:]]*\(spiffe:[^[:space:]]*\).*/\1/p' | head -1)
fi

# Method 3: If still empty, try grep with Perl regex (if available)
if [ -z "$NEW_AGENT_ID" ] || [ "$NEW_AGENT_ID" = ":" ]; then
    NEW_AGENT_ID=$(echo "$AGENT_LIST_NEW" | grep -oP 'SPIFFE ID\s+:\s+\K[^\s]+' | head -1) 2>/dev/null || true
fi

if [ -n "$NEW_AGENT_ID" ]; then
    echo "  ✓ Agent successfully joined with SPIFFE ID: $NEW_AGENT_ID"
    
    # Check if socket exists
    if [ -S "/tmp/spire-agent/public/api.sock" ]; then
        echo "  ✓ Agent socket created: /tmp/spire-agent/public/api.sock"
    else
        echo "  ⚠ Agent socket not found yet (may take a few more seconds)"
    fi
else
    echo "  ⚠ Agent may not have joined yet. Check logs: tail -f /tmp/spire-agent.log"
    echo "  Agent list output:"
    echo "$AGENT_LIST_NEW"
fi

echo ""
echo "✅ Agent rejoin complete!"
echo ""
echo "To check agent status:"
echo "  ${SPIRE_DIR}/bin/spire-server agent list -socketPath $SERVER_SOCKET"
echo ""
echo "To view agent logs:"
echo "  tail -f /tmp/spire-agent.log"

