#!/bin/bash
# Unified-Identity - Setup: Create registration entry for Python app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${SCRIPT_DIR}/../spire"

# Get agent SPIFFE ID
echo "Getting agent SPIFFE ID..."

# Wait briefly for agent to stabilize (it may be re-attesting)
sleep 2

AGENT_ID=""

# APPROACH 1: Get the agent ID from SPIRE Server logs (most reliable - records actual attestations)
# This is the most authoritative source because it shows what the server actually accepted
if [ -f /tmp/spire-server.log ]; then
    # Get the most recent "Successfully reattested node" or "Attested" log entry
    AGENT_ID=$(grep -E "Successfully reattested node|Successfully attested node|Attested agent" /tmp/spire-server.log 2>/dev/null | \
        tail -1 | \
        grep -oE 'spiffe://[^"]+' | \
        head -1 | \
        tr -d ' \r\n"')
    
    if [ -n "$AGENT_ID" ] && [ "${AGENT_ID#spiffe://}" != "$AGENT_ID" ]; then
        echo "  (Got agent ID from SPIRE Server logs - most recent attestation)"
    else
        AGENT_ID=""
    fi
fi

# APPROACH 2: Get the agent ID from SPIRE Agent logs
if [ -z "$AGENT_ID" ] || [ "${AGENT_ID#spiffe://}" = "$AGENT_ID" ]; then
    if [ -f /tmp/spire-agent.log ]; then
        # Look for the agent's SVID - this is what the agent is actually using
        AGENT_ID=$(grep -E "reattested node|spiffe_id=.*unified-identity" /tmp/spire-agent.log 2>/dev/null | \
            grep -oE 'spiffe://[^"]+unified-identity[^"]*' | \
            tail -1 | \
            tr -d ' \r\n"')
        
        if [ -n "$AGENT_ID" ] && [ "${AGENT_ID#spiffe://}" != "$AGENT_ID" ]; then
            echo "  (Got agent ID from SPIRE Agent logs)"
        else
            AGENT_ID=""
        fi
    fi
fi

# APPROACH 3: Fallback to agent list - pick agent with LATEST expiration time (most recently attested)
if [ -z "$AGENT_ID" ] || [ "${AGENT_ID#spiffe://}" = "$AGENT_ID" ]; then
    echo "  (Falling back to spire-server agent list - WARNING: may return stale agents)"
    
    # Get the FULL agent list output for debugging
    AGENT_LIST_OUTPUT=$("${SPIRE_DIR}/bin/spire-server" agent list \
        -socketPath /tmp/spire-server/private/api.sock 2>&1 || echo "")
    
    # Check if we have any agents
    if [ -z "$AGENT_LIST_OUTPUT" ] || echo "$AGENT_LIST_OUTPUT" | grep -qi "no attested agents"; then
        echo "Error: No attested agents found"
        echo "Debug: Agent list output:"
        echo "$AGENT_LIST_OUTPUT"
        exit 1
    fi
    
    # Count agents and warn if multiple
    AGENT_COUNT=$(echo "$AGENT_LIST_OUTPUT" | grep -c "SPIFFE ID" || echo "0")
    if [ "$AGENT_COUNT" -gt 1 ]; then
        echo "  ⚠ Warning: Found $AGENT_COUNT agents in database"
        echo "  Selecting agent with latest expiration time (most recently attested)..."
        
        # Parse agent list and find the one with the latest expiration time
        # Format: SPIFFE ID : spiffe://... followed by Expiration time : 2025-12-15 12:12:18 +0530 IST
        LATEST_EXP=""
        LATEST_AGENT=""
        
        # Process agents in pairs (SPIFFE ID and Expiration time lines)
        current_agent=""
        while IFS= read -r line; do
            if echo "$line" | grep -q "SPIFFE ID"; then
                current_agent=$(echo "$line" | sed 's/.*SPIFFE ID[[:space:]]*:[[:space:]]*//' | tr -d ' \r\n')
            elif echo "$line" | grep -q "Expiration time" && [ -n "$current_agent" ]; then
                exp_time=$(echo "$line" | sed 's/.*Expiration time[[:space:]]*:[[:space:]]*//' | tr -d '\r')
                # Compare timestamps - later ones should be "greater"
                if [ -z "$LATEST_EXP" ] || [[ "$exp_time" > "$LATEST_EXP" ]]; then
                    LATEST_EXP="$exp_time"
                    LATEST_AGENT="$current_agent"
                fi
            fi
        done <<< "$AGENT_LIST_OUTPUT"
        
        if [ -n "$LATEST_AGENT" ]; then
            AGENT_ID="$LATEST_AGENT"
            echo "  Selected agent with expiration: $LATEST_EXP"
        fi
    else
        # Only one agent - use it
        AGENT_ID=$(echo "$AGENT_LIST_OUTPUT" | grep "SPIFFE ID" | tail -1 | awk -F': ' '{print $2}' | tr -d ' \r\n')
    fi
    
    # Fallback: try sed if awk doesn't work
    if [ -z "$AGENT_ID" ] || [ "$AGENT_ID" = "SPIFFE" ]; then
        AGENT_ID=$(echo "$AGENT_LIST_OUTPUT" | grep "spiffe://" | tail -1 | sed 's/.*SPIFFE ID[[:space:]]*:[[:space:]]*\(spiffe:\/\/[^[:space:]]*\).*/\1/' | tr -d ' \r\n')
    fi
fi

# Final validation
if [ -z "$AGENT_ID" ] || [ "$AGENT_ID" = "SPIFFE" ] || [ "${AGENT_ID#spiffe://}" = "$AGENT_ID" ]; then
    echo "Error: Could not get agent SPIFFE ID"
    echo "Debug: Checking SPIRE Server logs for recent attestations..."
    if [ -f /tmp/spire-server.log ]; then
        grep -E "Successfully (re)?attested" /tmp/spire-server.log 2>/dev/null | tail -5 | sed 's/^/    /'
    fi
    exit 1
fi

echo "✓ Agent SPIFFE ID: $AGENT_ID"
echo ""

# Create registration entry for Python app
echo "Creating registration entry for Python app..."
WORKLOAD_SPIFFE_ID="spiffe://example.org/python-app"

# Check if entry already exists (check output content, not just exit code)
ENTRY_SHOW_OUTPUT=$("${SPIRE_DIR}/bin/spire-server" entry show \
    -spiffeID "$WORKLOAD_SPIFFE_ID" \
    -socketPath /tmp/spire-server/private/api.sock 2>&1 || echo "")

# Check if entry actually exists by looking for "Entry ID" in output (not just exit code)
if echo "$ENTRY_SHOW_OUTPUT" | grep -qi "Entry ID" && ! echo "$ENTRY_SHOW_OUTPUT" | grep -qi "Found 0 entries"; then
    echo "⚠ Entry already exists (verification step should have caught this)"
    echo "  Deleting existing entry..."
    # Try multiple methods to extract entry ID
    # Method 1: Extract UUID pattern (most reliable)
    ENTRY_ID=$(echo "$ENTRY_SHOW_OUTPUT" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
    
    if [ -n "$ENTRY_ID" ]; then
        echo "  Found entry ID: $ENTRY_ID"
        if "${SPIRE_DIR}/bin/spire-server" entry delete \
            -entryID "$ENTRY_ID" \
            -socketPath /tmp/spire-server/private/api.sock 2>&1; then
            echo "  ✓ Existing entry deleted"
        else
            echo "  ⚠ Failed to delete entry (ID: $ENTRY_ID)"
        fi
    else
        # Fallback: list and delete
         ENTRY_LIST=$("${SPIRE_DIR}/bin/spire-server" entry list \
            -spiffeID "$WORKLOAD_SPIFFE_ID" \
            -socketPath /tmp/spire-server/private/api.sock 2>&1 || echo "")
        if [ -n "$ENTRY_LIST" ]; then
             echo "$ENTRY_LIST" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | while read -r eid; do
                if [ -n "$eid" ]; then
                    "${SPIRE_DIR}/bin/spire-server" entry delete -entryID "$eid" -socketPath /tmp/spire-server/private/api.sock 2>&1
                fi
            done
        fi
    fi
fi

# Create new entry
# Use grep -oE to extract UUID reliably, ignoring column headers/delimiters
ENTRY_ID=$("${SPIRE_DIR}/bin/spire-server" entry create \
    -spiffeID "$WORKLOAD_SPIFFE_ID" \
    -parentID "$AGENT_ID" \
    -selector "unix:uid:$(id -u)" \
    -socketPath /tmp/spire-server/private/api.sock \
    | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)

if [ -z "$ENTRY_ID" ]; then
    echo "Error: Failed to create registration entry"
    exit 1
fi

echo "✓ Registration entry created: $ENTRY_ID"
echo "  SPIFFE ID: $WORKLOAD_SPIFFE_ID"
echo "  Parent: $AGENT_ID"
echo "  Selector: unix:uid:$(id -u)"
echo ""
echo "  Checking SPIRE Server logs for entry creation..."
if [ -f /tmp/spire-server.log ]; then
    tail -5 /tmp/spire-server.log | grep -E "(entry|Entry|$WORKLOAD_SPIFFE_ID)" | tail -2 | sed 's/^/    /' || echo "    (No matching log entries found)"
fi
echo ""

