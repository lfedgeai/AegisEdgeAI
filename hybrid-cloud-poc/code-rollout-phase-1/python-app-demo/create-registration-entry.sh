#!/bin/bash
# Unified-Identity - Phase 1: Create registration entry for Python app

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

# Check if entry already exists
"${SPIRE_DIR}/bin/spire-server" entry show \
    -spiffeID "$WORKLOAD_SPIFFE_ID" \
    -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1 && {
    echo "Entry already exists, deleting..."
    ENTRY_ID=$("${SPIRE_DIR}/bin/spire-server" entry show \
        -spiffeID "$WORKLOAD_SPIFFE_ID" \
        -socketPath /tmp/spire-server/private/api.sock \
        | grep "Entry ID" | awk '{print $3}')
    "${SPIRE_DIR}/bin/spire-server" entry delete \
        -entryID "$ENTRY_ID" \
        -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1 || true
}

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

