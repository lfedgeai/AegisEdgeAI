#!/bin/bash
# Unified-Identity - Phase 1: Cleanup script for Python app demo

set -e

echo "Unified-Identity - Phase 1: Cleaning up Python App Demo"
echo ""

# Stop processes
echo "Stopping processes..."
if [ -f /tmp/spire-server.pid ]; then
    kill $(cat /tmp/spire-server.pid) 2>/dev/null || true
    rm -f /tmp/spire-server.pid
fi
if [ -f /tmp/spire-agent.pid ]; then
    kill $(cat /tmp/spire-agent.pid) 2>/dev/null || true
    rm -f /tmp/spire-agent.pid
fi
if [ -f /tmp/keylime-stub.pid ]; then
    kill $(cat /tmp/keylime-stub.pid) 2>/dev/null || true
    rm -f /tmp/keylime-stub.pid
fi

# Kill any remaining processes
pkill -f "spire-server" >/dev/null 2>&1 || true
pkill -f "spire-agent" >/dev/null 2>&1 || true
pkill -f "keylime-stub" >/dev/null 2>&1 || true
pkill -f "go run main.go" >/dev/null 2>&1 || true

sleep 2

# Clean up SPIRE registration entries
echo "Cleaning up SPIRE registration entries..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${SCRIPT_DIR}/../spire"
SERVER_SOCKET="/tmp/spire-server/private/api.sock"

if [ -S "$SERVER_SOCKET" ] && [ -f "${SPIRE_DIR}/bin/spire-server" ]; then
    ENTRY_LIST=$("${SPIRE_DIR}/bin/spire-server" entry list -socketPath "$SERVER_SOCKET" 2>/dev/null || echo "")
    if [ -n "$ENTRY_LIST" ] && echo "$ENTRY_LIST" | grep -q "Entry ID"; then
        ENTRY_IDS=$(echo "$ENTRY_LIST" | grep "Entry ID" | sed -n 's/.*Entry ID[[:space:]]*:[[:space:]]*\([a-f0-9-]\+\).*/\1/p' || \
                    echo "$ENTRY_LIST" | awk '/Entry ID/ {print $NF}')
        
        ENTRY_COUNT=0
        while IFS= read -r entry_id; do
            if [ -n "$entry_id" ] && [ "$entry_id" != "Entry" ] && [ "$entry_id" != "ID" ] && [ "$entry_id" != ":" ]; then
                if "${SPIRE_DIR}/bin/spire-server" entry delete -entryID "$entry_id" -socketPath "$SERVER_SOCKET" >/dev/null 2>&1; then
                    ENTRY_COUNT=$((ENTRY_COUNT + 1))
                fi
            fi
        done <<< "$ENTRY_IDS"
        
        if [ "$ENTRY_COUNT" -gt 0 ]; then
            echo "  ✓ Deleted $ENTRY_COUNT registration entry/entries"
        fi
    fi
fi

# Remove sockets
echo "Removing sockets..."
rm -rf /tmp/spire-server /tmp/spire-agent 2>/dev/null || true

# Remove data directories
echo "Removing data directories..."
sudo rm -rf /opt/spire/data 2>/dev/null || true

# Remove log files
echo "Removing log files..."
rm -f /tmp/spire-server.log /tmp/spire-agent.log /tmp/keylime-stub.log 2>/dev/null || true

# Remove output files (optional)
read -p "Remove SVID output files from /tmp/svid-dump? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /tmp/svid-dump /tmp/svid.pem /tmp/svid.key /tmp/svid_attested_claims.json 2>/dev/null || true
    echo "  ✓ Removed SVID output files"
fi

echo ""
echo "✓ Cleanup complete"

