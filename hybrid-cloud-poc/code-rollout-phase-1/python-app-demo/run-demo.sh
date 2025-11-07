#!/bin/bash
# Unified-Identity - Phase 1: Complete demo script
# Sets up SPIRE, creates registration entry, fetches SVID, and dumps it

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Unified-Identity - Phase 1: Python App Demo                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 0: Cleanup any existing setup
echo "Step 0: Cleaning up any existing setup..."
"${SCRIPT_DIR}/cleanup.sh"
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
else
    echo "  ⚠ Log file not found"
fi
echo ""
echo "SPIRE Agent (Unified-Identity logs):"
if [ -f /tmp/spire-agent.log ]; then
    grep -i "unified-identity\|sovereign\|attested" /tmp/spire-agent.log | tail -10 | sed 's/^/  /' || echo "  (No Unified-Identity logs found)"
else
    echo "  ⚠ Log file not found"
fi
echo ""

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
else
    echo "  ⚠ Log file not found"
fi
echo ""
echo "SPIRE Server (Unified-Identity logs):"
if [ -f /tmp/spire-server.log ]; then
    grep -i "unified-identity\|sovereign\|attested\|python-app" /tmp/spire-server.log | tail -5 | sed 's/^/  /' || echo "  (No Unified-Identity logs found)"
else
    echo "  ⚠ Log file not found"
fi
echo ""

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

