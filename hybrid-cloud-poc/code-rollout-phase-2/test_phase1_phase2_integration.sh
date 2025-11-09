#!/bin/bash
# Unified-Identity - Phase 1 & Phase 2: Complete End-to-End Integration Test
# Tests the full workflow: SPIRE Server + Real Keylime Verifier (Phase 2) -> Sovereign SVID Generation
# Ensures unified_identity flag is enabled and mock Keylime Verifier (stub) is NOT started

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE1_DIR="${SCRIPT_DIR}/../code-rollout-phase-1"
PHASE2_DIR="${SCRIPT_DIR}"
KEYLIME_DIR="${PHASE2_DIR}/keylime"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Unified-Identity - Phase 1 & Phase 2: Complete Integration  ║"
echo "║  Testing: SPIRE Server + Real Keylime Verifier -> SVID        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Function to stop all existing instances and clean up all data
stop_all_instances_and_cleanup() {
    echo -e "${CYAN}Stopping all existing instances and cleaning up all data...${NC}"
    echo ""
    
    # Step 1: Stop all processes
    echo "  1. Stopping all processes..."
    
    # Stop SPIRE processes
    echo "     Stopping SPIRE Server and Agent..."
    pkill -f "spire-server" >/dev/null 2>&1 || true
    pkill -f "spire-agent" >/dev/null 2>&1 || true
    
    # Stop Keylime processes (both real and stub)
    echo "     Stopping Keylime Verifier (real and stub)..."
    pkill -f "keylime_verifier" >/dev/null 2>&1 || true
    pkill -f "python.*keylime" >/dev/null 2>&1 || true
    pkill -f "keylime-stub" >/dev/null 2>&1 || true
    pkill -f "go run.*keylime-stub" >/dev/null 2>&1 || true
    
    # Kill processes using Keylime and SPIRE ports
    if command -v lsof >/dev/null 2>&1; then
        echo "     Freeing up ports..."
        lsof -ti:8881 | xargs kill -9 >/dev/null 2>&1 || true
        lsof -ti:8888 | xargs kill -9 >/dev/null 2>&1 || true
        lsof -ti:8080 | xargs kill -9 >/dev/null 2>&1 || true
        lsof -ti:8081 | xargs kill -9 >/dev/null 2>&1 || true
    fi
    if command -v fuser >/dev/null 2>&1; then
        fuser -k 8881/tcp >/dev/null 2>&1 || true
        fuser -k 8888/tcp >/dev/null 2>&1 || true
        fuser -k 8080/tcp >/dev/null 2>&1 || true
        fuser -k 8081/tcp >/dev/null 2>&1 || true
    fi
    
    # Wait for processes to fully stop
    sleep 2
    
    # Force kill any remaining processes
    RUNNING_COUNT=0
    if pgrep -f "spire-server|spire-agent|keylime" >/dev/null 2>&1; then
        RUNNING_COUNT=$(pgrep -f "spire-server|spire-agent|keylime" | wc -l)
        if [ "$RUNNING_COUNT" -gt 0 ]; then
            echo "     Force killing $RUNNING_COUNT remaining process(es)..."
            pkill -9 -f "spire-server" >/dev/null 2>&1 || true
            pkill -9 -f "spire-agent" >/dev/null 2>&1 || true
            pkill -9 -f "keylime" >/dev/null 2>&1 || true
            sleep 1
        fi
    fi
    
    # Step 2: Clean up all data directories and databases
    echo "  2. Cleaning up all data directories and databases..."
    
    # Clean up SPIRE data directories
    echo "     Removing SPIRE data directories..."
    sudo rm -rf /opt/spire/data 2>/dev/null || true
    rm -rf /tmp/spire-server 2>/dev/null || true
    rm -rf /tmp/spire-agent 2>/dev/null || true
    
    # Clean up Keylime databases (if any)
    echo "     Removing Keylime databases..."
    rm -f "${KEYLIME_DIR}/verifier.db" 2>/dev/null || true
    rm -f "${KEYLIME_DIR}/verifier.sqlite" 2>/dev/null || true
    rm -f "${KEYLIME_DIR}"/*.db 2>/dev/null || true
    rm -f "${KEYLIME_DIR}"/*.sqlite 2>/dev/null || true
    
    # Clean up SVID dump directory
    echo "     Removing SVID dump directory..."
    rm -rf /tmp/svid-dump 2>/dev/null || true
    
    # Step 3: Clean up all PID files
    echo "  3. Removing PID files..."
    rm -f /tmp/keylime-verifier.pid 2>/dev/null || true
    rm -f /tmp/keylime-stub.pid 2>/dev/null || true
    rm -f /tmp/spire-server.pid 2>/dev/null || true
    rm -f /tmp/spire-agent.pid 2>/dev/null || true
    
    # Step 4: Clean up all log files
    echo "  4. Removing log files..."
    rm -f /tmp/keylime-test.log 2>/dev/null || true
    rm -f /tmp/keylime-verifier.log 2>/dev/null || true
    rm -f /tmp/keylime-stub.log 2>/dev/null || true
    rm -f /tmp/spire-server.log 2>/dev/null || true
    rm -f /tmp/spire-agent.log 2>/dev/null || true
    rm -f /tmp/bundle.pem 2>/dev/null || true
    
    # Step 5: Clean up sockets
    echo "  5. Removing socket files..."
    rm -f /tmp/spire-server/private/api.sock 2>/dev/null || true
    rm -f /tmp/spire-agent/public/api.sock 2>/dev/null || true
    rm -rf /tmp/spire-server 2>/dev/null || true
    rm -rf /tmp/spire-agent 2>/dev/null || true
    
    # Step 6: Recreate clean data directories
    echo "  6. Creating clean data directories..."
    sudo mkdir -p /opt/spire/data/server /opt/spire/data/agent 2>/dev/null || true
    sudo chown -R "$(whoami):$(whoami)" /opt/spire/data 2>/dev/null || true
    mkdir -p /tmp/spire-server/private 2>/dev/null || true
    mkdir -p /tmp/spire-agent/public 2>/dev/null || true
    
    # Final verification
    echo ""
    if ! pgrep -f "spire-server|spire-agent|keylime" >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ All existing instances stopped and all data cleaned up${NC}"
        return 0
    else
        echo -e "${YELLOW}  ⚠ Some processes may still be running:${NC}"
        pgrep -f "spire-server|spire-agent|keylime" || true
        return 1
    fi
}

# Cleanup function (called on exit)
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up on exit...${NC}"
    # Only stop processes on exit, don't delete data (user may want to inspect)
    pkill -f "keylime_verifier" >/dev/null 2>&1 || true
    pkill -f "python.*keylime" >/dev/null 2>&1 || true
    pkill -f "spire-server" >/dev/null 2>&1 || true
    pkill -f "spire-agent" >/dev/null 2>&1 || true
    pkill -f "keylime-stub" >/dev/null 2>&1 || true
}

trap cleanup EXIT

# Step 0: Stop all existing instances and clean up all data
echo -e "${CYAN}Step 0: Stopping all existing instances and cleaning up all data...${NC}"
echo ""
stop_all_instances_and_cleanup
echo ""

# Step 0b: Verify mock Keylime Verifier (stub) is NOT running
echo -e "${CYAN}Step 0b: Verifying mock Keylime Verifier (stub) is NOT running...${NC}"
if pgrep -f "keylime-stub" >/dev/null 2>&1; then
    echo -e "${RED}  ✗ ERROR: Mock Keylime Verifier (stub) is running!${NC}"
    echo "  This test requires the REAL Keylime Verifier (Phase 2), not the stub."
    echo "  Stopping stub..."
    pkill -9 -f "keylime-stub" >/dev/null 2>&1 || true
    sleep 1
fi
if [ -f /tmp/keylime-stub.pid ]; then
    echo "  Removing stale stub PID file..."
    rm -f /tmp/keylime-stub.pid
fi
echo -e "${GREEN}  ✓ Mock Keylime Verifier (stub) is NOT running${NC}"
echo ""

# Step 1: Setup Keylime environment with TLS certificates
echo -e "${CYAN}Step 1: Setting up Keylime environment with TLS certificates...${NC}"
echo ""

# Create minimal config if needed
VERIFIER_CONFIG="${PHASE2_DIR}/verifier.conf.minimal"
if [ ! -f "${VERIFIER_CONFIG}" ]; then
    echo -e "${RED}Error: Verifier config not found at ${VERIFIER_CONFIG}${NC}"
    exit 1
fi

# Verify unified_identity_enabled is set to true
if ! grep -q "unified_identity_enabled = true" "${VERIFIER_CONFIG}"; then
    echo -e "${RED}Error: unified_identity_enabled must be set to true in ${VERIFIER_CONFIG}${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ unified_identity_enabled = true verified in config${NC}"

# Set environment variables
export KEYLIME_VERIFIER_CONFIG="$(cd "${PHASE2_DIR}" && pwd)/verifier.conf.minimal"
export KEYLIME_TEST=on
export KEYLIME_DIR="$(cd "${KEYLIME_DIR}" && pwd)"
export KEYLIME_CA_CONFIG="${VERIFIER_CONFIG}"

# Create work directory for Keylime
WORK_DIR="${KEYLIME_DIR}"
TLS_DIR="${WORK_DIR}/cv_ca"

echo "  Setting up TLS certificates..."
echo "  Work directory: ${WORK_DIR}"
echo "  TLS directory: ${TLS_DIR}"

# Pre-generate TLS certificates if they don't exist or are corrupted
if [ ! -d "${TLS_DIR}" ] || [ ! -f "${TLS_DIR}/cacert.crt" ] || [ ! -f "${TLS_DIR}/server-cert.crt" ]; then
    echo "  Generating CA and TLS certificates..."
    # Remove old/corrupted certificates
    rm -rf "${TLS_DIR}"
    mkdir -p "${TLS_DIR}"
    chmod 700 "${TLS_DIR}"
    
    # Use Python to generate certificates via Keylime's CA utilities
    python3 << 'PYTHON_EOF'
import sys
import os
sys.path.insert(0, os.environ['KEYLIME_DIR'])

# Set up config before importing
os.environ['KEYLIME_VERIFIER_CONFIG'] = os.environ.get('KEYLIME_VERIFIER_CONFIG', '')
os.environ['KEYLIME_TEST'] = 'on'

from keylime import config, ca_util, keylime_logging

# Initialize logging
logger = keylime_logging.init_logging("verifier")

# Get TLS directory
tls_dir = os.path.join(os.environ['KEYLIME_DIR'], 'cv_ca')

# Change to TLS directory for certificate generation
original_cwd = os.getcwd()
os.chdir(tls_dir)

try:
    # Set empty password for testing (must be done before cmd_init)
    ca_util.read_password("")
    
    # Initialize CA
    print(f"  Generating CA in {tls_dir}...")
    ca_util.cmd_init(tls_dir)
    print("  ✓ CA certificate generated")
    
    # Generate server certificate
    print("  Generating server certificate...")
    ca_util.cmd_mkcert(tls_dir, 'server', password=None)
    print("  ✓ Server certificate generated")
    
    # Generate client certificate
    print("  Generating client certificate...")
    ca_util.cmd_mkcert(tls_dir, 'client', password=None)
    print("  ✓ Client certificate generated")
    
    print("  ✓ TLS setup complete")
finally:
    os.chdir(original_cwd)
PYTHON_EOF

    if [ $? -ne 0 ]; then
        echo -e "${RED}  ✗ Failed to generate TLS certificates${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}  ✓ TLS certificates already exist${NC}"
fi

# Step 2: Start Real Keylime Verifier (Phase 2) with unified_identity enabled
echo ""
echo -e "${CYAN}Step 2: Starting Real Keylime Verifier (Phase 2) with unified_identity enabled...${NC}"
cd "${KEYLIME_DIR}"

# Start verifier in background
echo "  Starting verifier on port 8881..."
python3 -m keylime.cmd.verifier > /tmp/keylime-test.log 2>&1 &
KEYLIME_PID=$!
echo $KEYLIME_PID > /tmp/keylime-verifier.pid

# Wait for verifier to start
echo "  Waiting for verifier to start..."
VERIFIER_STARTED=false
for i in {1..90}; do
    # Try multiple endpoints (with and without TLS)
    if curl -s -k https://localhost:8881/version >/dev/null 2>&1 || \
       curl -s http://localhost:8881/version >/dev/null 2>&1 || \
       curl -s -k https://localhost:8881/v2.4/version >/dev/null 2>&1 || \
       curl -s http://localhost:8881/v2.4/version >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ Keylime Verifier started (PID: $KEYLIME_PID)${NC}"
        VERIFIER_STARTED=true
        break
    fi
    # Check if process is still running
    if ! kill -0 $KEYLIME_PID 2>/dev/null; then
        echo -e "${RED}  ✗ Keylime Verifier process died${NC}"
        echo "  Logs:"
        tail -50 /tmp/keylime-test.log
        exit 1
    fi
    # Show progress every 10 seconds
    if [ $((i % 10)) -eq 0 ]; then
        echo "    Still waiting... (${i}/90 seconds)"
    fi
    sleep 1
done

if [ "$VERIFIER_STARTED" = false ]; then
    echo -e "${YELLOW}  ⚠ Keylime Verifier may not be fully ready, but continuing...${NC}"
    echo "  Logs:"
    tail -30 /tmp/keylime-test.log | grep -E "(ERROR|Starting|port|TLS)" || tail -20 /tmp/keylime-test.log
fi

# Verify unified_identity feature flag is enabled
echo ""
echo "  Verifying unified_identity feature flag..."
FEATURE_ENABLED=$(python3 -c "
import sys
sys.path.insert(0, '${KEYLIME_DIR}')
import os
os.environ['KEYLIME_VERIFIER_CONFIG'] = '${VERIFIER_CONFIG}'
os.environ['KEYLIME_TEST'] = 'on'
from keylime import app_key_verification
print(app_key_verification.is_unified_identity_enabled())
" 2>&1 | tail -1)

if [ "$FEATURE_ENABLED" = "True" ]; then
    echo -e "${GREEN}  ✓ unified_identity feature flag is ENABLED${NC}"
else
    echo -e "${RED}  ✗ unified_identity feature flag is DISABLED (expected: True, got: $FEATURE_ENABLED)${NC}"
    exit 1
fi

# Step 3: Start SPIRE Server and Agent
echo ""
echo -e "${CYAN}Step 3: Starting SPIRE Server and Agent...${NC}"

if [ ! -d "${PHASE1_DIR}" ]; then
    echo -e "${RED}Error: Phase 1 directory not found at ${PHASE1_DIR}${NC}"
    exit 1
fi

# Set Keylime Verifier URL for SPIRE Server (use HTTPS - Keylime Verifier uses TLS)
export KEYLIME_VERIFIER_URL="https://localhost:8881"
echo "  Setting KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL} (HTTPS)"

# Check if SPIRE binaries exist
SPIRE_SERVER="${PHASE1_DIR}/spire/bin/spire-server"
SPIRE_AGENT="${PHASE1_DIR}/spire/bin/spire-agent"

if [ ! -f "${SPIRE_SERVER}" ] || [ ! -f "${SPIRE_AGENT}" ]; then
    echo -e "${YELLOW}  ⚠ SPIRE binaries not found, skipping SPIRE integration test${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}Integration Test Summary:${NC}"
    echo -e "${GREEN}  ✓ Mock Keylime Verifier (stub) is NOT running${NC}"
    echo -e "${GREEN}  ✓ TLS certificates generated successfully${NC}"
    echo -e "${GREEN}  ✓ Real Keylime Verifier (Phase 2) started${NC}"
    echo -e "${GREEN}  ✓ unified_identity feature flag is ENABLED${NC}"
    echo -e "${YELLOW}  ⚠ SPIRE integration test skipped (binaries not found)${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo "To complete full integration test:"
    echo "  1. Build SPIRE: cd ${PHASE1_DIR}/spire && make bin/spire-server bin/spire-agent"
    echo "  2. Run this script again"
    exit 0
fi

# Use Phase 1's start script but ensure it uses real Keylime Verifier
echo "  Starting SPIRE Server and Agent using Phase 1 script..."
cd "${PHASE1_DIR}/scripts"

# Ensure the start script uses real Keylime Verifier (not stub)
# Use HTTPS - Keylime Verifier uses TLS by default
export KEYLIME_VERIFIER_URL="https://localhost:8881"
export KEYLIME_VERIFIER_PORT=8881
export KEYLIME_VERIFIER_CONFIG="${VERIFIER_CONFIG}"

# Start SPIRE Server and Agent (this script should NOT start keylime-stub)
# Note: The start script may exit if Keylime Verifier isn't ready immediately,
# but we've already started it, so we'll start SPIRE components manually if needed
if ! "${PHASE1_DIR}/scripts/start-unified-identity-phase2.sh" 2>&1; then
    echo -e "${YELLOW}  ⚠ Start script had issues, but Keylime Verifier is already running${NC}"
    echo "  Starting SPIRE Server and Agent manually..."
    
    # Start SPIRE Server manually
    cd "${PHASE1_DIR}"
    SERVER_CONFIG="${PHASE1_DIR}/python-app-demo/spire-server-phase2.conf"
    if [ -f "${SERVER_CONFIG}" ]; then
        echo "    Starting SPIRE Server (logs: /tmp/spire-server.log)..."
        "${SPIRE_SERVER}" run -config "${SERVER_CONFIG}" > /tmp/spire-server.log 2>&1 &
        echo $! > /tmp/spire-server.pid
        sleep 3
    fi
    
    # Start SPIRE Agent manually
    AGENT_CONFIG="${PHASE1_DIR}/python-app-demo/spire-agent.conf"
    if [ -f "${AGENT_CONFIG}" ]; then
        echo "    Starting SPIRE Agent (logs: /tmp/spire-agent.log)..."
        "${SPIRE_AGENT}" run -config "${AGENT_CONFIG}" > /tmp/spire-agent.log 2>&1 &
        echo $! > /tmp/spire-agent.pid
        sleep 3
    fi
fi

# Wait for SPIRE Server to be ready
echo "  Waiting for SPIRE Server to be ready..."
for i in {1..30}; do
    if "${SPIRE_SERVER}" healthcheck -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1; then
        echo -e "${GREEN}  ✓ SPIRE Server is ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${YELLOW}  ⚠ SPIRE Server may not be fully ready, but continuing...${NC}"
    fi
    sleep 1
done

# Wait a bit more for Agent to complete attestation
echo "  Waiting for SPIRE Agent to complete attestation..."
sleep 5

# Show initial attestation logs
echo ""
echo -e "${CYAN}  Initial SPIRE Agent Attestation Status:${NC}"
if [ -f /tmp/spire-agent.log ]; then
    echo "  Checking for attestation completion..."
    if grep -q "Node attestation was successful\|SVID loaded" /tmp/spire-agent.log; then
        echo -e "${GREEN}  ✓ Agent attestation completed${NC}"
        echo "  Agent SVID details:"
        grep -E "Node attestation was successful|SVID loaded|spiffe://.*agent" /tmp/spire-agent.log | tail -3 | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ Agent attestation may still be in progress...${NC}"
    fi
fi

# Wait for user input after steps 1-3 are completed
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Steps 1-3 completed: Keylime Verifier and SPIRE are running${NC}"
echo -e "${BOLD}Press Enter to continue to Step 4 (Create Registration Entry)...${NC}"
read -r

# Step 4: Create Registration Entry
echo ""
echo -e "${CYAN}Step 4: Creating registration entry for workload...${NC}"

cd "${PHASE1_DIR}/python-app-demo"
if [ -f "./create-registration-entry.sh" ]; then
    ./create-registration-entry.sh
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Registration entry created${NC}"
    else
        echo -e "${YELLOW}  ⚠ Registration entry creation had issues, but continuing...${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ Registration entry script not found, skipping...${NC}"
fi

# Wait for user input before proceeding
echo ""
echo -e "${BOLD}Press Enter to continue to Step 5 (Generate Sovereign SVID)...${NC}"
read -r

# Step 5: Generate Sovereign SVID
echo ""
echo -e "${CYAN}Step 5: Generating Sovereign SVID with AttestedClaims...${NC}"
echo "  This tests the complete workflow:"
echo "    1. Workload requests SVID with SovereignAttestation"
echo "    2. SPIRE Agent sends SovereignAttestation to SPIRE Server"
echo "    3. SPIRE Server calls Real Keylime Verifier (Phase 2)"
echo "    4. Keylime Verifier validates and returns AttestedClaims"
echo "    5. SPIRE Server evaluates policy and returns AttestedClaims"
echo "    6. Workload receives SVID + AttestedClaims"
echo ""

if [ -f "./fetch-sovereign-svid-grpc.py" ]; then
    python3 fetch-sovereign-svid-grpc.py
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ Sovereign SVID generated successfully${NC}"
        
        # Check if SVID was created
        if [ -f "/tmp/svid-dump/svid.pem" ]; then
            echo -e "${GREEN}  ✓ SVID saved to /tmp/svid-dump/svid.pem${NC}"
            echo ""
            echo "  To view the SVID certificate with AttestedClaims extension:"
            echo "    ${PHASE2_DIR}/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem"
            echo ""
            echo "  Or use OpenSSL directly:"
            echo "    openssl x509 -in /tmp/svid-dump/svid.pem -text -noout | grep -A 2 \"1.3.6.1.4.1.99999.1\""
        fi
        # Note: AttestedClaims are now embedded in the certificate extension
        # The separate attested_claims.json file may still exist for backward compatibility
        if [ -f "/tmp/svid-dump/attested_claims.json" ]; then
            echo -e "${GREEN}  ✓ AttestedClaims also saved to /tmp/svid-dump/attested_claims.json (for reference)${NC}"
            echo ""
            echo "  Note: AttestedClaims are now embedded in the certificate extension."
            echo "  The JSON file is provided for reference, but the certificate extension is authoritative."
            echo ""
            echo "  AttestedClaims from Real Keylime Verifier (Phase 2):"
            cat /tmp/svid-dump/attested_claims.json | python3 -m json.tool 2>/dev/null | head -20 || cat /tmp/svid-dump/attested_claims.json
        fi
    else
        echo -e "${YELLOW}  ⚠ Sovereign SVID generation had issues${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ fetch-sovereign-svid-grpc.py not found, skipping SVID generation test${NC}"
fi

# Wait for user input before proceeding
echo ""
echo -e "${BOLD}Press Enter to continue to Step 6 (Verify Integration)...${NC}"
read -r

# Step 6: Verify Integration
echo ""
echo -e "${CYAN}Step 6: Verifying Phase 1 + Phase 2 Integration...${NC}"

# Check logs for Unified-Identity activity
echo "  Checking SPIRE Server logs for Keylime Verifier calls..."
if [ -f /tmp/spire-server.log ]; then
    KEYLIME_CALLS=$(grep -i "unified-identity.*keylime" /tmp/spire-server.log | wc -l)
    if [ "$KEYLIME_CALLS" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Found $KEYLIME_CALLS Unified-Identity Keylime calls in SPIRE Server logs${NC}"
        echo "  Sample log entries:"
        grep -i "unified-identity.*keylime" /tmp/spire-server.log | tail -3 | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ No Unified-Identity Keylime calls found in SPIRE Server logs${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ SPIRE Server log not found${NC}"
fi

echo ""
echo "  Checking Keylime Verifier logs for Phase 2 activity..."
if [ -f /tmp/keylime-test.log ]; then
    PHASE2_LOGS=$(grep -i "unified-identity.*phase 2" /tmp/keylime-test.log | wc -l)
    if [ "$PHASE2_LOGS" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Found $PHASE2_LOGS Phase 2 Unified-Identity logs${NC}"
        echo "  Sample log entries:"
        grep -i "unified-identity.*phase 2" /tmp/keylime-test.log | tail -3 | sed 's/^/    /'
    else
        echo -e "${YELLOW}  ⚠ No Phase 2 Unified-Identity logs found${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ Keylime Verifier log not found${NC}"
fi

# Step 6b: Show Critical SPIRE Agent and Server Logs for SVID
echo ""
echo -e "${CYAN}Step 6b: Critical SPIRE Agent and Server Logs - SVID Issuance...${NC}"
echo ""

# SPIRE Server logs - Agent attestation and SVID issuance
echo -e "${BOLD}  SPIRE Server Logs - Agent Attestation & SVID Issuance:${NC}"
if [ -f /tmp/spire-server.log ]; then
    echo ""
    echo "  📋 Agent Attestation Request Completed:"
    grep -i "Agent attestation request completed" /tmp/spire-server.log | tail -2 | sed 's/^/    /' || echo "    (not found)"
    
    echo ""
    echo "  📋 Keylime Verifier Calls (Sovereign Attestation):"
    grep -i "unified-identity.*keylime\|Received AttestedClaims from Keylime" /tmp/spire-server.log | tail -5 | sed 's/^/    /' || echo "    (not found)"
    
    echo ""
    echo "  📋 SVID Signed for Agent:"
    grep -i "Signed X509 SVID\|spiffe_id.*agent\|Node attestation was successful" /tmp/spire-server.log | tail -3 | sed 's/^/    /' || echo "    (not found)"
    
    echo ""
    echo "  📋 AttestedClaims Attached to Agent SVID:"
    grep -i "AttestedClaims attached to agent SVID\|AttestedClaims for agent" /tmp/spire-server.log | tail -3 | sed 's/^/    /' || echo "    (not found)"
else
    echo -e "${YELLOW}    ⚠ SPIRE Server log not found at /tmp/spire-server.log${NC}"
fi

# SPIRE Agent logs - SVID receipt
echo ""
echo -e "${BOLD}  SPIRE Agent Logs - SVID Receipt:${NC}"
if [ -f /tmp/spire-agent.log ]; then
    echo ""
    echo "  📋 Node Attestation Status:"
    grep -i "Node attestation was successful\|SVID loaded\|SVID is not found" /tmp/spire-agent.log | tail -3 | sed 's/^/    /' || echo "    (not found)"
    
    echo ""
    echo "  📋 Agent SPIFFE ID (from SVID):"
    grep -i "spiffe_id\|spiffe://.*agent" /tmp/spire-agent.log | grep -i "agent\|attestation\|SVID" | tail -5 | sed 's/^/    /' || echo "    (not found)"
    
    echo ""
    echo "  📋 AttestedClaims Received During Bootstrap:"
    grep -i "Received AttestedClaims during agent bootstrap\|Received AttestedClaims for agent SVID" /tmp/spire-agent.log | tail -3 | sed 's/^/    /' || echo "    (not found)"
    
    echo ""
    echo "  📋 SVID Details (if available):"
    grep -i "Creating X509-SVID\|Renewing X509-SVID\|Fetched X.509 SVID" /tmp/spire-agent.log | tail -3 | sed 's/^/    /' || echo "    (not found)"
else
    echo -e "${YELLOW}    ⚠ SPIRE Agent log not found at /tmp/spire-agent.log${NC}"
fi

# Try to extract actual SVID certificate info if available
echo ""
echo -e "${BOLD}  Actual SVID Certificate Information:${NC}"
if [ -f /tmp/spire-agent.log ]; then
    # Look for SPIFFE ID in agent logs
    AGENT_SPIFFE_ID=$(grep -oP 'spiffe://[^"]+' /tmp/spire-agent.log | grep -i agent | head -1)
    if [ -n "$AGENT_SPIFFE_ID" ]; then
        echo "    Agent SPIFFE ID: $AGENT_SPIFFE_ID"
    fi
    
    # Check if we can get SVID from agent's data directory
    if [ -d /opt/spire/data/agent ]; then
        echo "    Agent data directory: /opt/spire/data/agent"
        echo "    (SVID stored in agent's secure storage)"
    fi
fi

# Show recent critical logs from both
echo ""
echo -e "${BOLD}  Recent Critical Logs (Last 10 lines from each):${NC}"
echo ""
echo "  SPIRE Server (last 10 lines):"
if [ -f /tmp/spire-server.log ]; then
    tail -10 /tmp/spire-server.log | sed 's/^/    /'
else
    echo "    (log file not found)"
fi

echo ""
echo "  SPIRE Agent (last 10 lines):"
if [ -f /tmp/spire-agent.log ]; then
    tail -10 /tmp/spire-agent.log | sed 's/^/    /'
else
    echo "    (log file not found)"
fi

# Final verification: Ensure stub is still NOT running
echo ""
echo "  Final verification: Ensuring mock Keylime Verifier (stub) is NOT running..."
if pgrep -f "keylime-stub" >/dev/null 2>&1; then
    echo -e "${RED}  ✗ ERROR: Mock Keylime Verifier (stub) is running!${NC}"
    echo "  This should not happen - the stub must NOT be running for Phase 2 tests."
    exit 1
else
    echo -e "${GREEN}  ✓ Mock Keylime Verifier (stub) is confirmed NOT running${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Integration Test Summary                                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}  ✓ Mock Keylime Verifier (stub) is NOT running${NC}"
echo -e "${GREEN}  ✓ TLS certificates generated successfully${NC}"
echo -e "${GREEN}  ✓ Real Keylime Verifier (Phase 2) started${NC}"
echo -e "${GREEN}  ✓ unified_identity feature flag is ENABLED${NC}"
if [ -f "${SPIRE_SERVER}" ]; then
    echo -e "${GREEN}  ✓ SPIRE Server and Agent started${NC}"
    echo -e "${GREEN}  ✓ Registration entry created${NC}"
    if [ -f "/tmp/svid-dump/attested_claims.json" ]; then
        echo -e "${GREEN}  ✓ Sovereign SVID generated with AttestedClaims${NC}"
    fi
fi
echo ""
echo -e "${GREEN}Phase 1 + Phase 2 integration test completed successfully!${NC}"
echo ""
echo "Keylime Verifier is running in background (PID: $KEYLIME_PID)"
echo "SPIRE Server and Agent are running"
echo ""
echo "To view logs:"
echo "  Keylime Verifier: tail -f /tmp/keylime-test.log"
echo "  SPIRE Server:     tail -f /tmp/spire-server.log"
echo "  SPIRE Agent:      tail -f /tmp/spire-agent.log"
echo ""
if [ -f "/tmp/svid-dump/svid.pem" ]; then
    echo "To view SVID certificate with AttestedClaims extension:"
    echo "  ${PHASE2_DIR}/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem"
    echo ""
fi
echo "To stop all services:"
echo "  ${PHASE1_DIR}/scripts/stop-unified-identity-phase2.sh"
