#!/bin/bash
# Unified-Identity - Phase 1: Complete demo script
# Sets up SPIRE, creates registration entry, fetches SVID, and dumps it

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

# Step 0: Cleanup any existing setup
echo "Step 0: Cleaning up any existing setup..."
"${SCRIPT_DIR}/cleanup.sh"
echo ""
prompt_continue

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
prompt_continue

# Step 1: Setup SPIRE
echo "Step 1: Setting up SPIRE and Keylime Stub..."
"${SCRIPT_DIR}/setup-spire.sh"
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
echo "Step 2: Creating registration entry..."
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

# Step 3: Fetch sovereign SVID
echo "Step 3: Fetching Sovereign SVID with AttestedClaims..."
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
echo "Step 4: Dumping SVID with AttestedClaims..."
if [ -f /tmp/svid-dump/attested_claims.json ]; then
    "${SCRIPT_DIR}/../scripts/dump-svid" \
        -cert /tmp/svid-dump/svid.pem \
        -attested /tmp/svid-dump/attested_claims.json
else
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
echo "Step 5: Summary Logs..."
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

