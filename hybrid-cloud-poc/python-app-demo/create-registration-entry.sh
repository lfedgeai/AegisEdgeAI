#!/bin/bash
# Unified-Identity - Setup: Create registration entry for Python app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${SCRIPT_DIR}/../spire"

# Get agent SPIFFE ID
echo "Getting agent SPIFFE ID..."
# Extract SPIFFE ID from "SPIFFE ID         : spiffe://..."
AGENT_ID=$("${SPIRE_DIR}/bin/spire-server" agent list \
    -socketPath /tmp/spire-server/private/api.sock \
    | grep "SPIFFE ID" | awk -F': ' '{print $2}' | awk '{print $1}')

# Fallback: try sed if awk doesn't work
if [ -z "$AGENT_ID" ] || [ "$AGENT_ID" = "SPIFFE" ]; then
    AGENT_ID=$("${SPIRE_DIR}/bin/spire-server" agent list \
        -socketPath /tmp/spire-server/private/api.sock \
        | grep "spiffe://" | head -1 | sed 's/.*SPIFFE ID[[:space:]]*:[[:space:]]*\(spiffe:\/\/[^[:space:]]*\).*/\1/')
fi

# Final validation
if [ -z "$AGENT_ID" ] || [ "$AGENT_ID" = "SPIFFE" ] || [ "${AGENT_ID#spiffe://}" = "$AGENT_ID" ]; then
    echo "Error: Could not get agent SPIFFE ID"
    echo "Debug: Agent list output:"
    "${SPIRE_DIR}/bin/spire-server" agent list \
        -socketPath /tmp/spire-server/private/api.sock
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
    # Method 2: Extract from "Entry ID         : <uuid>" format
    if [ -z "$ENTRY_ID" ]; then
        ENTRY_ID=$(echo "$ENTRY_SHOW_OUTPUT" | grep -i "Entry ID" | sed -n 's/.*Entry ID[[:space:]]*:[[:space:]]*\([a-f0-9-]\+\).*/\1/p' | head -1)
    fi
    # Method 3: Use awk (fallback)
    if [ -z "$ENTRY_ID" ]; then
        ENTRY_ID=$(echo "$ENTRY_SHOW_OUTPUT" | grep -i "Entry ID" | awk -F': ' '{print $2}' | awk '{print $1}' | head -1)
    fi
    
    if [ -n "$ENTRY_ID" ]; then
        echo "  Found entry ID: $ENTRY_ID"
        if "${SPIRE_DIR}/bin/spire-server" entry delete \
            -entryID "$ENTRY_ID" \
            -socketPath /tmp/spire-server/private/api.sock 2>&1; then
            echo "  ✓ Existing entry deleted"
            # Verify deletion
            sleep 0.5
            VERIFY_OUTPUT=$("${SPIRE_DIR}/bin/spire-server" entry show \
                -spiffeID "$WORKLOAD_SPIFFE_ID" \
                -socketPath /tmp/spire-server/private/api.sock 2>&1 || echo "")
            if echo "$VERIFY_OUTPUT" | grep -qi "Entry ID" && ! echo "$VERIFY_OUTPUT" | grep -qi "Found 0 entries"; then
                echo "  ⚠ WARNING: Entry still exists after deletion!"
            fi
        else
            echo "  ⚠ Failed to delete entry (ID: $ENTRY_ID)"
            echo "  Attempting to list all entries and delete by SPIFFE ID..."
            # Fallback: try to delete all entries with this SPIFFE ID
            ENTRY_LIST=$("${SPIRE_DIR}/bin/spire-server" entry list \
                -spiffeID "$WORKLOAD_SPIFFE_ID" \
                -socketPath /tmp/spire-server/private/api.sock 2>&1 || echo "")
            if [ -n "$ENTRY_LIST" ]; then
                echo "$ENTRY_LIST" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | while read -r eid; do
                    if [ -n "$eid" ]; then
                        "${SPIRE_DIR}/bin/spire-server" entry delete -entryID "$eid" -socketPath /tmp/spire-server/private/api.sock 2>&1 && echo "  ✓ Deleted entry: $eid"
                    fi
                done
            fi
        fi
    else
        echo "  ⚠ Could not extract entry ID from output"
        echo "  ⚠ Debug output:"
        echo "$ENTRY_SHOW_OUTPUT" | head -10 | sed 's/^/    /'
        echo "  Attempting to delete by listing all entries..."
        # Fallback: list all entries and find matching SPIFFE ID
        ENTRY_LIST=$("${SPIRE_DIR}/bin/spire-server" entry list \
            -socketPath /tmp/spire-server/private/api.sock 2>&1 || echo "")
        if echo "$ENTRY_LIST" | grep -q "$WORKLOAD_SPIFFE_ID"; then
            echo "$ENTRY_LIST" | grep -B 5 "$WORKLOAD_SPIFFE_ID" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1 | while read -r eid; do
                if [ -n "$eid" ]; then
                    "${SPIRE_DIR}/bin/spire-server" entry delete -entryID "$eid" -socketPath /tmp/spire-server/private/api.sock 2>&1 && echo "  ✓ Deleted entry: $eid"
                fi
            done
        fi
    fi
fi

# Create new entry
ENTRY_ID=$("${SPIRE_DIR}/bin/spire-server" entry create \
    -spiffeID "$WORKLOAD_SPIFFE_ID" \
    -parentID "$AGENT_ID" \
    -selector "unix:uid:$(id -u)" \
    -socketPath /tmp/spire-server/private/api.sock \
    | grep "Entry ID" | awk '{print $3}')

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

