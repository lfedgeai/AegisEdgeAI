#!/bin/bash
# Unified-Identity - Phase 1: Complete demo script
# Sets up SPIRE, creates registration entry, fetches SVID, and dumps it

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SPIRE_DIR="${PROJECT_ROOT}/spire"
cd "$SCRIPT_DIR"

# ANSI color codes for step headers
BOLD='\033[1m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Check if running interactively (stdin is a TTY)
INTERACTIVE=false
if [ -t 0 ]; then
    INTERACTIVE=true
fi

# Function to prompt user to continue (only if interactive)
prompt_continue() {
    if [ "$INTERACTIVE" = true ]; then
        echo ""
        read -p "Press Enter to continue to the next step... " -r
        echo ""
    fi
}

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Unified-Identity - Phase 1: Python App Demo                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 0: Cleanup any existing setup (FIRST - ensures clean state)
echo -e "${BOLD}${CYAN}Step 0: Cleaning up any existing setup...${RESET}"
echo "  (This removes SPIRE data directory to ensure no entries persist)"
echo ""

# Clean up registration entries FIRST (while server might still be running)
SERVER_SOCKET="/tmp/spire-server/private/api.sock"
if [ -S "$SERVER_SOCKET" ] && [ -f "${SPIRE_DIR}/bin/spire-server" ]; then
    echo "  Cleaning up SPIRE registration entries..."
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
                echo "    ✓ Deleted $ENTRY_COUNT registration entry/entries"
            fi
        fi
    fi
fi

# Stop processes
echo "  Stopping processes..."
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
echo "  Waiting for processes to terminate..."
for i in {1..5}; do
    if ! pgrep -f "spire-server|spire-agent|keylime-stub" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Force kill any stubborn processes
if pgrep -f "spire-server|spire-agent|keylime-stub" >/dev/null 2>&1; then
    echo "    Force killing remaining processes..."
    pkill -9 -f "spire-server" >/dev/null 2>&1 || true
    pkill -9 -f "spire-agent" >/dev/null 2>&1 || true
    pkill -9 -f "keylime-stub" >/dev/null 2>&1 || true
    sleep 1
fi

# Remove sockets
echo "  Removing sockets..."
rm -rf /tmp/spire-server /tmp/spire-agent 2>/dev/null || true

# Remove data directories (CRITICAL: This removes all registration entries)
echo "  Removing SPIRE data directory and all persistent files..."
# Check if directory exists and list what we're removing
if [ -d /opt/spire/data ]; then
    echo "    Found /opt/spire/data directory"
    echo "    Files to be removed:"
    find /opt/spire/data -type f 2>/dev/null | sed 's/^/      /' || true
    
    # Check if any process is using the data directory
    if command -v lsof >/dev/null 2>&1; then
        LOCKED_FILES=$(lsof +D /opt/spire/data 2>/dev/null | grep -v "^COMMAND" || true)
        if [ -n "$LOCKED_FILES" ]; then
            echo "    ⚠ Files in /opt/spire/data are locked, waiting..."
            sleep 2
        fi
    fi
    
    # Explicitly remove critical files first (database, keys, agent data)
    echo "    Removing critical files explicitly..."
    sudo rm -f /opt/spire/data/server/datastore.sqlite3 2>/dev/null || true
    sudo rm -f /opt/spire/data/server/datastore.sqlite3-wal 2>/dev/null || true
    sudo rm -f /opt/spire/data/server/datastore.sqlite3-shm 2>/dev/null || true
    sudo rm -f /opt/spire/data/server/keys.json 2>/dev/null || true
    sudo rm -f /opt/spire/data/agent/keys.json 2>/dev/null || true
    sudo rm -f /opt/spire/data/agent/agent-data.json 2>/dev/null || true
    
    # Try without sudo first (in case user owns the directory)
    echo "    Attempting removal (without sudo)..."
    rm -rf /opt/spire/data 2>&1 || true
    sleep 0.5
fi

# Try with sudo if it still exists
if [ -d /opt/spire/data ]; then
    echo "    Attempting removal with sudo..."
    sudo rm -rf /opt/spire/data 2>&1 || true
    sleep 0.5
fi

# Wait a moment and verify removal
sleep 1
if [ -d /opt/spire/data ]; then
    echo "    ⚠ ERROR: /opt/spire/data still exists - entries WILL persist!"
    echo "    ⚠ Directory contents:"
    ls -la /opt/spire/data 2>/dev/null || true
    echo "    ⚠ Remaining files:"
    find /opt/spire/data -type f 2>/dev/null | sed 's/^/      /' || true
    echo "    ⚠ Attempting manual cleanup..."
    # Try one more time with more aggressive approach
    sudo rm -rf /opt/spire/data/* 2>/dev/null || true
    sudo rmdir /opt/spire/data 2>/dev/null || true
    sleep 1
    if [ -d /opt/spire/data ]; then
        echo "    ⚠ CRITICAL: Cannot remove /opt/spire/data - manual intervention required:"
        echo "       sudo rm -rf /opt/spire/data"
        echo "    ⚠ Exiting - please clean up manually and restart"
        exit 1
    else
        echo "    ✓ SPIRE data directory removed (all entries cleared)"
    fi
else
    echo "    ✓ SPIRE data directory removed (all entries cleared)"
fi

# Final verification: check for any remaining files
REMAINING_FILES=$(find /opt/spire/data -type f 2>/dev/null | wc -l)
if [ "$REMAINING_FILES" -gt 0 ] 2>/dev/null; then
    echo "    ⚠ WARNING: $REMAINING_FILES file(s) still exist in /opt/spire/data:"
    find /opt/spire/data -type f 2>/dev/null | sed 's/^/      /'
    echo "    ⚠ Attempting to remove remaining files..."
    sudo find /opt/spire/data -type f -delete 2>/dev/null || true
    sudo find /opt/spire/data -type d -empty -delete 2>/dev/null || true
fi

# Verify directory is completely gone
if [ -d /opt/spire/data ]; then
    echo "    ⚠ CRITICAL: Directory still exists after cleanup - manual intervention required"
    exit 1
fi

# Remove log files
echo "  Removing log files..."
rm -f /tmp/spire-server.log /tmp/spire-agent.log /tmp/keylime-stub.log 2>/dev/null || true

# Remove SVID output files
echo "  Removing SVID output files..."
rm -rf /tmp/svid-dump /tmp/svid.pem /tmp/svid.key /tmp/svid_attested_claims.json 2>/dev/null || true

echo "  ✓ Cleanup complete"
echo ""

# Check and install Python dependencies
echo "Checking Python dependencies..."
MISSING_DEPS=false

# Check for spiffe library (for fallback)
if ! python3 -c "import spiffe.workloadapi" 2>/dev/null; then
    MISSING_DEPS=true
fi

# Check for gRPC dependencies (for real AttestedClaims)
if ! python3 -c "import grpc" 2>/dev/null; then
    MISSING_DEPS=true
fi

if [ "$MISSING_DEPS" = true ]; then
    echo "Installing Python dependencies from requirements.txt..."
    python3 -m pip install -r requirements.txt || {
        echo "Error: Failed to install dependencies"
        echo "Try: python3 -m pip install --user -r requirements.txt"
        exit 1
    }
    echo "✓ Python dependencies installed"
else
    echo "✓ Python dependencies already installed"
fi

# Generate protobuf stubs if using gRPC version
if [ -f "${SCRIPT_DIR}/fetch-sovereign-svid-grpc.py" ]; then
    if [ ! -f "${SCRIPT_DIR}/generated/spiffe/workload/workload_pb2.py" ]; then
        echo "Generating protobuf stubs for gRPC version..."
        if [ -f "${SCRIPT_DIR}/generate-proto-stubs.sh" ]; then
            "${SCRIPT_DIR}/generate-proto-stubs.sh" || echo "⚠ Failed to generate protobuf stubs (will try to generate on-the-fly)"
        fi
    fi
fi
echo ""

# Step 1: Setup SPIRE
echo -e "${BOLD}${CYAN}Step 1: Setting up SPIRE and Keylime Stub...${RESET}"

# Final check: ensure data directory is gone before starting SPIRE
if [ -d /opt/spire/data ]; then
    echo "  ⚠ CRITICAL: /opt/spire/data still exists before starting SPIRE!"
    echo "  ⚠ This will cause entries to persist. Attempting final cleanup..."
    sudo rm -rf /opt/spire/data 2>/dev/null || true
    sleep 1
    if [ -d /opt/spire/data ]; then
        echo "  ⚠ ERROR: Cannot remove /opt/spire/data - aborting"
        echo "  Please run manually: sudo rm -rf /opt/spire/data"
        exit 1
    fi
    echo "  ✓ Final cleanup succeeded"
fi

"${SCRIPT_DIR}/setup-spire.sh"

# Verify data directory is fresh (no existing entries)
echo "  Verifying clean state..."
# Wait for server to be fully ready
for i in {1..10}; do
    if [ -S "$SERVER_SOCKET" ] && "${SPIRE_DIR}/bin/spire-server" healthcheck -socketPath "$SERVER_SOCKET" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if [ -S "$SERVER_SOCKET" ] && [ -f "${SPIRE_DIR}/bin/spire-server" ]; then
    # Check for existing entries
    ENTRY_LIST=$("${SPIRE_DIR}/bin/spire-server" entry list -socketPath "$SERVER_SOCKET" 2>/dev/null || echo "")
    # Count entries more robustly - handle empty output and multiple matches
    if [ -z "$ENTRY_LIST" ]; then
        ENTRY_COUNT=0
    else
        ENTRY_COUNT=$(echo "$ENTRY_LIST" | grep -c "Entry ID" 2>/dev/null || echo "0")
        # Ensure we have a valid number
        if ! [[ "$ENTRY_COUNT" =~ ^[0-9]+$ ]]; then
            ENTRY_COUNT=0
        fi
    fi
    
    if [ "$ENTRY_COUNT" -gt 0 ] 2>/dev/null; then
        echo "    ⚠ WARNING: Found $ENTRY_COUNT existing registration entry/entries!"
        echo "    ⚠ This suggests cleanup didn't fully remove the data directory."
        echo "    ⚠ Listing entries:"
        echo "$ENTRY_LIST" | grep -E "(Entry ID|SPIFFE ID)" | sed 's/^/      /' || true
        echo "    ⚠ Attempting to delete all entries..."
        ENTRY_IDS=$(echo "$ENTRY_LIST" | grep "Entry ID" | sed -n 's/.*Entry ID[[:space:]]*:[[:space:]]*\([a-f0-9-]\+\).*/\1/p')
        DELETED=0
        while IFS= read -r entry_id; do
            if [ -n "$entry_id" ]; then
                echo "      Deleting entry: $entry_id"
                if "${SPIRE_DIR}/bin/spire-server" entry delete -entryID "$entry_id" -socketPath "$SERVER_SOCKET" >/dev/null 2>&1; then
                    DELETED=$((DELETED + 1))
                fi
            fi
        done <<< "$ENTRY_IDS"
        if [ $DELETED -gt 0 ]; then
            echo "    ✓ Deleted $DELETED existing entry/entries"
        else
            echo "    ⚠ Failed to delete entries - they may persist"
        fi
        # Verify deletion
        sleep 1
        REMAINING_LIST=$("${SPIRE_DIR}/bin/spire-server" entry list -socketPath "$SERVER_SOCKET" 2>/dev/null || echo "")
        if [ -z "$REMAINING_LIST" ]; then
            REMAINING=0
        else
            REMAINING=$(echo "$REMAINING_LIST" | grep -c "Entry ID" 2>/dev/null || echo "0")
            if ! [[ "$REMAINING" =~ ^[0-9]+$ ]]; then
                REMAINING=0
            fi
        fi
        if [ "$REMAINING" -gt 0 ] 2>/dev/null; then
            echo "    ⚠ WARNING: $REMAINING entries still remain after deletion attempt"
        else
            echo "    ✓ All entries successfully deleted"
        fi
    else
        echo "    ✓ Verified: No existing registration entries (clean state)"
        # Double-check by trying to show the specific entry we'll create
        WORKLOAD_SPIFFE_ID="spiffe://example.org/python-app"
        # Note: entry list doesn't support -spiffeID filter, so we only use entry show
        ENTRY_SHOW_OUTPUT=$("${SPIRE_DIR}/bin/spire-server" entry show -spiffeID "$WORKLOAD_SPIFFE_ID" -socketPath "$SERVER_SOCKET" 2>/dev/null || echo "")
        
        # Check if entry actually exists by looking for "Entry ID" in output (not just exit code)
        # "Found 0 entries" means entry does NOT exist - check this first
        ENTRY_EXISTS=false
        if echo "$ENTRY_SHOW_OUTPUT" | grep -qi "Found 0 entries"; then
            # Entry does not exist
            ENTRY_EXISTS=false
        elif echo "$ENTRY_SHOW_OUTPUT" | grep -qi "Entry ID" && ! echo "$ENTRY_SHOW_OUTPUT" | grep -qi "Found 0 entries"; then
            # Entry exists (has Entry ID and NOT "Found 0 entries")
            ENTRY_EXISTS=true
        fi
        
        if [ "$ENTRY_EXISTS" = true ]; then
            echo "    ⚠ WARNING: Entry for $WORKLOAD_SPIFFE_ID exists but wasn't in list!"
            echo "    ⚠ This is unexpected - attempting to delete it..."
            # Try multiple methods to extract entry ID from output
            ENTRY_ID=$(echo "$ENTRY_SHOW_OUTPUT" | grep -i "Entry ID" | awk -F': ' '{print $2}' | awk '{print $1}' | head -1)
            if [ -z "$ENTRY_ID" ]; then
                # Try alternative format: "Entry ID         : uuid-here"
                ENTRY_ID=$(echo "$ENTRY_SHOW_OUTPUT" | grep -i "Entry ID" | sed -n 's/.*Entry ID[[:space:]]*:[[:space:]]*\([a-f0-9-]\+\).*/\1/p' | head -1)
            fi
            if [ -z "$ENTRY_ID" ]; then
                # Try with awk field 3
                ENTRY_ID=$(echo "$ENTRY_SHOW_OUTPUT" | grep -i "Entry ID" | awk '{print $3}' | head -1)
            fi
            if [ -z "$ENTRY_ID" ]; then
                # Try extracting UUID pattern directly
                ENTRY_ID=$(echo "$ENTRY_SHOW_OUTPUT" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
            fi
            
            if [ -n "$ENTRY_ID" ]; then
                echo "      Found entry ID: $ENTRY_ID"
                if "${SPIRE_DIR}/bin/spire-server" entry delete -entryID "$ENTRY_ID" -socketPath "$SERVER_SOCKET" >/dev/null 2>&1; then
                    echo "    ✓ Deleted existing entry"
                    # Verify deletion
                    sleep 1
                    if "${SPIRE_DIR}/bin/spire-server" entry show -spiffeID "$WORKLOAD_SPIFFE_ID" -socketPath "$SERVER_SOCKET" >/dev/null 2>&1; then
                        echo "    ⚠ WARNING: Entry still exists after deletion attempt!"
                    else
                        echo "    ✓ Verified: Entry successfully deleted"
                    fi
                else
                    echo "    ⚠ Failed to delete entry (entry ID: $ENTRY_ID)"
                    echo "    ⚠ Debug: Entry show output (first 10 lines):"
                    echo "$ENTRY_SHOW_OUTPUT" | head -10 | sed 's/^/      /'
                fi
            else
                echo "    ⚠ Could not extract entry ID from output"
                echo "    ⚠ Debug: Entry show output (first 15 lines):"
                echo "$ENTRY_SHOW_OUTPUT" | head -15 | sed 's/^/      /'
                echo "    ⚠ Entry may still exist - manual cleanup may be required"
                echo "    ⚠ You can try: spire-server entry list -socketPath $SERVER_SOCKET | grep python-app"
            fi
        else
            # Entry doesn't exist - this is the expected state
            echo "    ✓ Verified: Entry for $WORKLOAD_SPIFFE_ID does not exist (clean state)"
        fi
    fi
else
    echo "    ⚠ Cannot verify: SPIRE server socket not ready"
fi
echo ""

# Show initial logs after setup
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Initial Component Logs (after startup)                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Keylime Stub (Unified-Identity logs):"
if [ -f /tmp/keylime-stub.log ]; then
    grep -i "unified-identity" /tmp/keylime-stub.log | tail -10 | sed 's/^/  /' || echo "  (No Unified-Identity logs found)"
else
    echo "  ⚠ Log file not found"
fi
echo ""
echo "SPIRE Server (Unified-Identity logs):"
if [ -f /tmp/spire-server.log ]; then
    grep -i "unified-identity\|sovereign\|attested" /tmp/spire-server.log | tail -10 | sed 's/^/  /' || echo "  (No Unified-Identity logs found)"
    # Check for server bootstrap AttestedClaims log
    BOOTSTRAP_CLAIMS=$(grep -i "AttestedClaims attached to agent bootstrap SVID\|host/python-demo-agent.*AttestedClaims" /tmp/spire-server.log | tail -1 || true)
    if [ -n "$BOOTSTRAP_CLAIMS" ]; then
        echo ""
        echo "  ↪ Agent bootstrap AttestedClaims (server log):"
        echo "    ${BOOTSTRAP_CLAIMS}"
    else
        # Check for various diagnostic messages
        MISSING_SOVEREIGN=$(grep -i "SovereignAttestation.*nil\|params.Params is nil\|SovereignAttestation missing" /tmp/spire-server.log | tail -1 || true)
        RECEIVED_SOVEREIGN=$(grep -i "Received SovereignAttestation in agent bootstrap" /tmp/spire-server.log | tail -1 || true)
        NIL_CLAIMS=$(grep -i "processSovereignAttestation returned nil claims" /tmp/spire-server.log | tail -1 || true)
        
        if [ -n "$RECEIVED_SOVEREIGN" ]; then
            echo ""
            echo "  ✓ Server received SovereignAttestation:"
            echo "    ${RECEIVED_SOVEREIGN}"
            if [ -n "$NIL_CLAIMS" ]; then
                echo "  ⚠ But processSovereignAttestation returned nil claims:"
                echo "    ${NIL_CLAIMS}"
            fi
        elif [ -n "$MISSING_SOVEREIGN" ]; then
            echo ""
            echo "  ⚠ Server log indicates SovereignAttestation issue:"
            echo "    ${MISSING_SOVEREIGN}"
            echo "    This suggests the agent may not be sending SovereignAttestation during bootstrap."
        else
            echo ""
            echo "  ↪ Agent bootstrap AttestedClaims (server log): (not found)"
            echo "    Checking for agent attestation completion..."
            ATTEST_COMPLETE=$(grep -i "Agent attestation request completed" /tmp/spire-server.log | grep -i "host/python-demo-agent\|spire/agent" | tail -1 || true)
            if [ -n "$ATTEST_COMPLETE" ]; then
                echo "    Agent attestation completed, but no AttestedClaims log found."
                echo "    This may indicate SovereignAttestation processing failed silently."
            fi
        fi
    fi
else
    echo "  ⚠ Log file not found"
fi
echo ""
echo "SPIRE Agent (Unified-Identity logs):"
if [ -f /tmp/spire-agent.log ]; then
    grep -i "unified-identity\|sovereign\|attested" /tmp/spire-agent.log | tail -10 | sed 's/^/  /' || echo "  (No Unified-Identity logs found)"
    # Check for bootstrap AttestedClaims (during initial attestation)
    AGENT_BOOTSTRAP=$(grep -i "Received AttestedClaims.*agent bootstrap\|Received AttestedClaims.*agent SVID" /tmp/spire-agent.log | tail -1 || true)
    # Also check for any AttestedClaims log with geolocation/integrity fields (more flexible)
    if [ -z "$AGENT_BOOTSTRAP" ]; then
        AGENT_BOOTSTRAP=$(grep -i "Received AttestedClaims\|AttestedClaims.*geolocation\|AttestedClaims.*integrity" /tmp/spire-agent.log | grep -i "agent\|bootstrap" | tail -1 || true)
    fi
    echo ""
    if [ -n "$AGENT_BOOTSTRAP" ]; then
        echo "  ↪ Agent bootstrap AttestedClaims (agent log):"
        echo "    ${AGENT_BOOTSTRAP}"
    else
        echo "  ↪ Agent bootstrap AttestedClaims (agent log): (not found)"
        echo "    Note: This log appears when AttestedClaims are received during agent bootstrap."
        echo "    Diagnostic: Checking for any AttestedClaims references in agent log..."
        ATTESTED_CHECK=$(grep -i "attested" /tmp/spire-agent.log | head -3 || true)
        if [ -n "$ATTESTED_CHECK" ]; then
            echo "    Found AttestedClaims references:"
            echo "$ATTESTED_CHECK" | sed 's/^/      /'
        else
            echo "    ⚠ No 'AttestedClaims' references found in agent log"
            echo "    This suggests AttestedClaims may not be in the server response."
            echo "    Check server logs for: 'AttestedClaims attached to agent bootstrap SVID'"
        fi
    fi
else
    echo "  ⚠ Log file not found"
fi
echo ""
prompt_continue

# Step 2: Create registration entry
echo -e "${BOLD}${CYAN}Step 2: Creating registration entry for Python App Workload...${RESET}"

"${SCRIPT_DIR}/create-registration-entry.sh"
echo ""

# Show server logs after entry creation
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  SPIRE Server Logs - Unified-Identity (after entry creation)  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
if [ -f /tmp/spire-server.log ]; then
    grep -i "unified-identity\|sovereign\|attested\|entry.*python-app" /tmp/spire-server.log | tail -5 | sed 's/^/  /' || echo "  (No Unified-Identity logs found)"
else
    echo "  ⚠ Log file not found"
fi
echo ""
prompt_continue

# Step 3: Sovereign SVID from Python App Workload
echo -e "${BOLD}${CYAN}Step 3: Sovereign SVID with AttestedClaims for Python App Workload ...${RESET}"
# Wait a moment for registration entry to propagate to agent
# The agent needs time to:
# 1. Receive the entry from server (sync happens every few seconds)
# 2. Fetch the SVID from server for the entry
# 3. Cache it for workloads
echo "Waiting for registration entry to propagate to agent..."
echo "  (Agent syncs with server every ~5 seconds, then fetches SVIDs)"
sleep 5

# Try gRPC version first (gets real AttestedClaims), fallback to spiffe library version
if [ -f "${SCRIPT_DIR}/fetch-sovereign-svid-grpc.py" ]; then
    echo "Using gRPC version to get real AttestedClaims from Workload API..."
    python3 "${SCRIPT_DIR}/fetch-sovereign-svid-grpc.py" || {
        echo "⚠ gRPC version failed, falling back to spiffe library version..."
        python3 "${SCRIPT_DIR}/fetch-sovereign-svid.py"
    }
else
    echo "Using spiffe library version (AttestedClaims may be mock data)..."
    python3 "${SCRIPT_DIR}/fetch-sovereign-svid.py"
fi
echo ""

# Show agent/server logs after SVID fetch
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Component Logs (after SVID fetch)                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "SPIRE Agent (Unified-Identity logs):"
if [ -f /tmp/spire-agent.log ]; then
    grep -i "unified-identity\|sovereign\|attested\|python-app" /tmp/spire-agent.log | tail -5 | sed 's/^/  /' || echo "  (No Unified-Identity logs found)"
    AGENT_WORKLOAD=$(grep -i "python-app" /tmp/spire-agent.log | grep -i "Fetched X.509 SVID" | tail -1 || true)
    if [ -n "$AGENT_WORKLOAD" ]; then
        echo "  ↪ Workload SVID (agent log): ${AGENT_WORKLOAD}"
    else
        echo "  ↪ Workload SVID (agent log): (not found – enable debug logging if needed)"
    fi
else
    echo "  ⚠ Log file not found"
fi
echo ""
echo "SPIRE Server (Unified-Identity logs):"
if [ -f /tmp/spire-server.log ]; then
    grep -i "unified-identity\|sovereign\|attested\|python-app" /tmp/spire-server.log | tail -5 | sed 's/^/  /' || echo "  (No Unified-Identity logs found)"
    SERVER_WORKLOAD=$(grep -i "python-app" /tmp/spire-server.log | grep -i "Added AttestedClaims" | tail -1 || true)
    if [ -n "$SERVER_WORKLOAD" ]; then
        echo "  ↪ Workload AttestedClaims (server log): ${SERVER_WORKLOAD}"
    fi
else
    echo "  ⚠ Log file not found"
fi
echo ""
prompt_continue

# Step 4: Dump SVID
if [ -f /tmp/svid-dump/attested_claims.json ]; then
    echo -e "${BOLD}${CYAN}Step 4: Dumping SVID with AttestedClaims...${RESET}"
    "${SCRIPT_DIR}/../scripts/dump-svid" \
        -cert /tmp/svid-dump/svid.pem \
        -attested /tmp/svid-dump/attested_claims.json
else
    echo -e "${BOLD}${CYAN}Step 4: Dumping SVID ...${RESET}"
    "${SCRIPT_DIR}/../scripts/dump-svid" \
        -cert /tmp/svid-dump/svid.pem
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Demo Complete!                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Files saved to: /tmp/svid-dump/"
echo "  - svid.pem (SVID certificate)"
echo "  - attested_claims.json (AttestedClaims, if available)"
echo ""
prompt_continue

# Step 5: Show summary logs
echo -e "${BOLD}${CYAN}Step 5: Summary Logs...${RESET}"
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Keylime Stub Logs - Unified-Identity                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
if [ -f /tmp/keylime-stub.log ]; then
    grep -i "unified-identity" /tmp/keylime-stub.log | tail -15 || echo "⚠ No Unified-Identity logs found"
else
    echo "⚠ Keylime Stub log file not found: /tmp/keylime-stub.log"
fi
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  SPIRE Server Logs - Unified-Identity                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
if [ -f /tmp/spire-server.log ]; then
    grep -i "unified-identity\|sovereign\|attested" /tmp/spire-server.log | tail -15 || echo "⚠ No Unified-Identity logs found"
else
    echo "⚠ SPIRE Server log file not found: /tmp/spire-server.log"
fi
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  SPIRE Agent Logs - Unified-Identity                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
if [ -f /tmp/spire-agent.log ]; then
    grep -i "unified-identity\|sovereign\|attested" /tmp/spire-agent.log | tail -15 || echo "⚠ No Unified-Identity logs found"
else
    echo "⚠ SPIRE Agent log file not found: /tmp/spire-agent.log"
fi
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Log Files Location                                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo "  Keylime Stub:  /tmp/keylime-stub.log"
echo "  SPIRE Server: /tmp/spire-server.log"
echo "  SPIRE Agent:  /tmp/spire-agent.log"
echo ""
echo "To view full logs in real-time:"
echo "  tail -f /tmp/keylime-stub.log"
echo "  tail -f /tmp/spire-server.log"
echo "  tail -f /tmp/spire-agent.log"
echo ""

