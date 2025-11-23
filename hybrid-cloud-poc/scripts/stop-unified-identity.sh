#!/bin/bash
# Unified-Identity - Phase 1: Shared teardown script for SPIRE Server, Agent, and Keylime Stub

set -euo pipefail

QUIET=${QUIET:-0}

log() {
    if [ "$QUIET" -eq 0 ]; then
        echo "$1"
    fi
}

log "Unified-Identity - Phase 1: Stopping SPIRE stack"
log ""

# Clean up registration entries FIRST (while server might still be running)
log "Cleaning up SPIRE registration entries..."
SPIRE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/spire"
SERVER_SOCKET="/tmp/spire-server/private/api.sock"

if [ -S "$SERVER_SOCKET" ] && [ -f "${SPIRE_DIR}/bin/spire-server" ]; then
    # Check if server is actually responding
    if "${SPIRE_DIR}/bin/spire-server" healthcheck -socketPath "$SERVER_SOCKET" >/dev/null 2>&1; then
        ENTRY_LIST=$("${SPIRE_DIR}/bin/spire-server" entry list -socketPath "$SERVER_SOCKET" 2>/dev/null || echo "")
        if [ -n "$ENTRY_LIST" ] && echo "$ENTRY_LIST" | grep -q "Entry ID"; then
            ENTRY_IDS=$(echo "$ENTRY_LIST" | grep "Entry ID" | sed -n 's/.*Entry ID[[:space:]]*:[[:space:]]*\([a-f0-9-]\+\).*/\1/p')
            ENTRY_COUNT=0
            while IFS= read -r entry_id; do
                if [ -n "$entry_id" ]; then
                    if "${SPIRE_DIR}/bin/spire-server" entry delete -entryID "$entry_id" -socketPath "$SERVER_SOCKET" >/dev/null 2>&1; then
                        ENTRY_COUNT=$((ENTRY_COUNT + 1))
                    fi
                fi
            done <<< "$ENTRY_IDS"
            if [ $ENTRY_COUNT -gt 0 ]; then
                log "  ✓ Deleted $ENTRY_COUNT registration entry/entries"
            fi
        fi
    fi
fi

# Stop processes
log "Stopping processes..."
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

# Wait for processes to fully terminate
log "Waiting for processes to terminate..."
for i in {1..5}; do
    if ! pgrep -f "spire-server|spire-agent|keylime-stub" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Force kill any stubborn processes
if pgrep -f "spire-server|spire-agent|keylime-stub" >/dev/null 2>&1; then
    log "  Force killing remaining processes..."
    pkill -9 -f "spire-server" >/dev/null 2>&1 || true
    pkill -9 -f "spire-agent" >/dev/null 2>&1 || true
    pkill -9 -f "keylime-stub" >/dev/null 2>&1 || true
    sleep 1
fi

# Remove sockets
log "Removing sockets..."
rm -rf /tmp/spire-server /tmp/spire-agent 2>/dev/null || true

# Remove data directories (CRITICAL: This removes all registration entries)
log "Removing data directories and all persistent files..."
# Check if directory exists and list what we're removing
if [ -d /opt/spire/data ]; then
    log "  Found /opt/spire/data directory"
    # Check if any process is using the data directory
    if command -v lsof >/dev/null 2>&1; then
        LOCKED_FILES=$(lsof +D /opt/spire/data 2>/dev/null | grep -v "^COMMAND" || true)
        if [ -n "$LOCKED_FILES" ]; then
            log "  ⚠ Files in /opt/spire/data are locked, waiting..."
            sleep 2
        fi
    fi
    
    # Explicitly remove critical files first (database, keys, agent data)
    log "  Removing critical files explicitly..."
    sudo rm -f /opt/spire/data/server/datastore.sqlite3 2>/dev/null || true
    sudo rm -f /opt/spire/data/server/datastore.sqlite3-wal 2>/dev/null || true
    sudo rm -f /opt/spire/data/server/datastore.sqlite3-shm 2>/dev/null || true
    sudo rm -f /opt/spire/data/server/keys.json 2>/dev/null || true
    sudo rm -f /opt/spire/data/agent/keys.json 2>/dev/null || true
    sudo rm -f /opt/spire/data/agent/agent-data.json 2>/dev/null || true
    
    # Try without sudo first (in case user owns the directory)
    rm -rf /opt/spire/data 2>/dev/null || true
    sleep 0.5
fi

# Try with sudo if it still exists
if [ -d /opt/spire/data ]; then
    log "  Attempting removal with sudo..."
    sudo rm -rf /opt/spire/data 2>/dev/null || true
    sleep 0.5
fi

# Wait a moment and verify removal
sleep 1
if [ -d /opt/spire/data ]; then
    log "  ⚠ ERROR: /opt/spire/data still exists - entries WILL persist!"
    log "  ⚠ Remaining files:"
    find /opt/spire/data -type f 2>/dev/null | sed 's/^/    /' || true
    log "  ⚠ Attempting manual cleanup..."
    # Try one more time with more aggressive approach
    sudo rm -rf /opt/spire/data/* 2>/dev/null || true
    sudo rmdir /opt/spire/data 2>/dev/null || true
    sleep 1
    if [ -d /opt/spire/data ]; then
        log "  ⚠ CRITICAL: Cannot remove /opt/spire/data - manual intervention required:"
        log "     sudo rm -rf /opt/spire/data"
        log "  ⚠ Continuing anyway, but entries may persist..."
        # Don't exit - let the demo continue but warn the user
    else
        log "  ✓ SPIRE data directory removed (all entries cleared)"
    fi
else
    log "  ✓ SPIRE data directory removed (all entries cleared)"
fi

# Final verification: check for any remaining files
REMAINING_FILES=$(find /opt/spire/data -type f 2>/dev/null | wc -l)
if [ "$REMAINING_FILES" -gt 0 ] 2>/dev/null; then
    log "  ⚠ WARNING: $REMAINING_FILES file(s) still exist in /opt/spire/data"
    log "  ⚠ Attempting to remove remaining files..."
    sudo find /opt/spire/data -type f -delete 2>/dev/null || true
    sudo find /opt/spire/data -type d -empty -delete 2>/dev/null || true
fi

# Remove log files (optional)
log "Removing log files..."
rm -f /tmp/spire-server.log /tmp/spire-agent.log /tmp/keylime-stub.log 2>/dev/null || true

# Remove SVID output files
rm -rf /tmp/svid-dump /tmp/svid.pem /tmp/svid.key /tmp/svid_attested_claims.json 2>/dev/null || true
log "Removed SVID output files"

log ""
log "✓ Cleanup complete"


