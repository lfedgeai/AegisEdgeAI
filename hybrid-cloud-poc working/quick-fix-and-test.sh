#!/bin/bash
# Quick Fix and Test Script
# This script combines diagnosis, fix, and testing in one go

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Quick Fix and Test - Single Machine Setup                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Function to wait for user
pause() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Step 1: Diagnose current state
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}STEP 1: Diagnosing Current State${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo ""

if [ -f "./fix-tpm-plugin-communication.sh" ]; then
    ./fix-tpm-plugin-communication.sh
else
    echo -e "${RED}✗ fix-tpm-plugin-communication.sh not found${NC}"
    echo "  Please copy the diagnostic script first"
    exit 1
fi

pause

# Step 2: Fix TPM Plugin communication if needed
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}STEP 2: Fixing TPM Plugin Communication${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Check if stub data issue exists
if grep -q "stub data" /tmp/spire-agent.log 2>/dev/null; then
    echo -e "${YELLOW}⚠ Stub data issue detected - fixing...${NC}"
    echo ""
    
    # Stop SPIRE Agent
    echo "  Stopping SPIRE Agent..."
    pkill -f spire-agent || true
    sleep 2
    
    # Verify TPM Plugin Server is running
    if ! pgrep -f "tpm_plugin_server" > /dev/null; then
        echo -e "${RED}  ✗ TPM Plugin Server is not running${NC}"
        echo "    Starting TPM Plugin Server..."
        
        # Start TPM Plugin Server
        cd ~/dhanush/hybrid-cloud-poc-backup/tpm-plugin
        mkdir -p /tmp/spire-data/tpm-plugin
        
        python3 tpm_plugin_server.py \
            --socket /tmp/spire-data/tpm-plugin/tpm-plugin.sock \
            --work-dir /tmp/spire-data/tpm-plugin \
            > /tmp/tpm-plugin-server.log 2>&1 &
        
        echo $! > /tmp/tpm-plugin-server.pid
        sleep 3
        
        if pgrep -f "tpm_plugin_server" > /dev/null; then
            echo -e "${GREEN}  ✓ TPM Plugin Server started${NC}"
        else
            echo -e "${RED}  ✗ Failed to start TPM Plugin Server${NC}"
            echo "    Check logs: tail -50 /tmp/tpm-plugin-server.log"
            exit 1
        fi
    else
        echo -e "${GREEN}  ✓ TPM Plugin Server is running${NC}"
    fi
    
    # Verify socket exists
    if [ ! -S /tmp/spire-data/tpm-plugin/tpm-plugin.sock ]; then
        echo -e "${RED}  ✗ TPM Plugin socket not found${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ TPM Plugin socket exists${NC}"
    
    # Restart SPIRE Agent with correct environment
    echo "  Restarting SPIRE Agent with correct environment..."
    cd ~/dhanush/hybrid-cloud-poc-backup/spire
    
    export TPM_PLUGIN_ENDPOINT="unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
    export UNIFIED_IDENTITY_ENABLED="true"
    
    nohup ./bin/spire-agent run -config ./conf/agent/agent.conf > /tmp/spire-agent.log 2>&1 &
    echo $! > /tmp/spire-agent.pid
    
    echo "  Waiting for SPIRE Agent to start..."
    sleep 10
    
    # Check if agent is running
    if pgrep -f "spire-agent" > /dev/null; then
        echo -e "${GREEN}  ✓ SPIRE Agent restarted${NC}"
    else
        echo -e "${RED}  ✗ SPIRE Agent failed to start${NC}"
        echo "    Check logs: tail -50 /tmp/spire-agent.log"
        exit 1
    fi
    
    # Wait for attestation
    echo "  Waiting for attestation to complete..."
    for i in {1..30}; do
        if [ -S /tmp/spire-agent/public/api.sock ]; then
            echo -e "${GREEN}  ✓ Workload API socket created - attestation successful!${NC}"
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${RED}  ✗ Attestation did not complete in 30 seconds${NC}"
            echo "    Check logs:"
            echo "      tail -50 /tmp/spire-agent.log"
            echo "      tail -50 /tmp/spire-server.log"
            echo "      tail -50 /tmp/keylime-verifier.log"
            exit 1
        fi
        sleep 1
    done
    
    # Verify no stub data
    echo "  Verifying TPM operations..."
    sleep 2
    if grep -q "stub data" /tmp/spire-agent.log; then
        echo -e "${RED}  ✗ Still using stub data${NC}"
        echo "    Recent logs:"
        tail -20 /tmp/spire-agent.log | grep -i "tpm\|stub\|plugin"
        exit 1
    else
        echo -e "${GREEN}  ✓ No stub data - using real TPM!${NC}"
    fi
    
else
    echo -e "${GREEN}✓ No stub data issue detected${NC}"
fi

pause

# Step 3: Test Workload SVID
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}STEP 3: Testing Workload SVID Generation${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo ""

if [ -S /tmp/spire-agent/public/api.sock ]; then
    echo "  Fetching Workload SVID..."
    cd ~/dhanush/hybrid-cloud-poc-backup/python-app-demo
    
    if python3 fetch-sovereign-svid-grpc.py; then
        echo -e "${GREEN}  ✓ Workload SVID fetched successfully!${NC}"
        
        # Show SVID details
        if [ -f /tmp/svid-dump/svid.pem ]; then
            echo ""
            echo "  SVID Certificate Chain:"
            openssl crl2pkcs7 -nocrl -certfile /tmp/svid-dump/svid.pem 2>/dev/null | \
                openssl pkcs7 -print_certs -text -noout 2>/dev/null | \
                grep -E "Subject:|URI:spiffe" | head -4
        fi
        
        if [ -f /tmp/svid-dump/attested_claims.json ]; then
            echo ""
            echo "  Attested Claims:"
            cat /tmp/svid-dump/attested_claims.json | python3 -m json.tool 2>/dev/null | head -20
        fi
    else
        echo -e "${RED}  ✗ Failed to fetch Workload SVID${NC}"
        exit 1
    fi
else
    echo -e "${RED}  ✗ Workload API socket not found${NC}"
    echo "    SPIRE Agent attestation may have failed"
    exit 1
fi

pause

# Step 4: Summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Summary                                                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo -e "${GREEN}✓ All checks passed!${NC}"
echo ""
echo "Services running:"
ps aux | grep -E "spire-server|spire-agent|keylime|tpm_plugin" | grep -v grep | awk '{print "  - " $11}' | sort -u

echo ""
echo "Sockets created:"
[ -S /tmp/spire-server/private/api.sock ] && echo "  ✓ SPIRE Server socket"
[ -S /tmp/spire-agent/public/api.sock ] && echo "  ✓ SPIRE Agent Workload API socket"
[ -S /tmp/spire-data/tpm-plugin/tpm-plugin.sock ] && echo "  ✓ TPM Plugin socket"

echo ""
echo "Next steps:"
echo "  1. Configure single machine: ./configure-single-machine.sh"
echo "  2. Run integration test: ./test_complete_integration.sh --no-pause"
echo "  3. Build CI/CD automation"
echo ""
echo -e "${CYAN}For detailed instructions, see: SINGLE_MACHINE_SETUP_GUIDE.md${NC}"
echo ""
