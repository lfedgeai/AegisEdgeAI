#!/bin/bash
# Unified-Identity - Phase 1: Create registration entry for Python app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${SCRIPT_DIR}/../spire"

# Get agent SPIFFE ID
echo "Getting agent SPIFFE ID..."
AGENT_ID=$("${SPIRE_DIR}/bin/spire-server" agent list \
    -socketPath /tmp/spire-server/private/api.sock \
    | grep "spiffe://" | head -1 | awk '{print $1}')

if [ -z "$AGENT_ID" ]; then
    echo "Error: Could not get agent SPIFFE ID"
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

