#!/bin/bash
# Quick fix for quote fetching issue
# Tests different approaches to resolve HTTP 599 errors

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Fix: Keylime Verifier Quote Fetching Issue                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Step 1: Run diagnostics
echo -e "${CYAN}[1] Running diagnostics...${NC}"
if [ -f "test-agent-quote-endpoint.sh" ]; then
    chmod +x test-agent-quote-endpoint.sh
    ./test-agent-quote-endpoint.sh
else
    echo -e "${YELLOW}  Diagnostic script not found, skipping...${NC}"
fi
echo ""

# Step 2: Test tornado connection
echo -e "${CYAN}[2] Testing tornado connection...${NC}"
if [ -f "test-tornado-agent-connection.py" ]; then
    echo "  Testing with mTLS..."
    if python3 test-tornado-agent-connection.py 2>&1 | tee /tmp/tornado-test-mtls.log; then
        echo -e "${GREEN}  ✓ mTLS connection works!${NC}"
        MTLS_WORKS=true
    else
        echo -e "${RED}  ✗ mTLS connection failed${NC}"
        MTLS_WORKS=false
    fi
    echo ""
    
    echo "  Testing without mTLS (HTTP)..."
    if python3 test-tornado-agent-connection.py --no-mtls 2>&1 | tee /tmp/tornado-test-http.log; then
        echo -e "${GREEN}  ✓ HTTP connection works!${NC}"
        HTTP_WORKS=true
    else
        echo -e "${RED}  ✗ HTTP connection failed${NC}"
        HTTP_WORKS=false
    fi
else
    echo -e "${YELLOW}  Test script not found, skipping...${NC}"
    MTLS_WORKS=false
    HTTP_WORKS=false
fi
echo ""

# Step 3: Determine fix approach
echo -e "${CYAN}[3] Determining fix approach...${NC}"
if [ "${MTLS_WORKS}" = "true" ]; then
    echo -e "${GREEN}  ✓ mTLS works - no fix needed!${NC}"
    echo "  The timeout increase should resolve the issue."
    exit 0
elif [ "${HTTP_WORKS}" = "true" ]; then
    echo -e "${YELLOW}  ⚠ mTLS fails but HTTP works${NC}"
    echo "  Recommendation: Disable agent mTLS temporarily"
    echo ""
    echo "  Apply fix? (y/n)"
    read -r APPLY_FIX
    if [ "${APPLY_FIX}" = "y" ]; then
        echo "  Disabling agent mTLS..."
        
        # Backup configs
        cp rust-keylime/keylime-agent.conf rust-keylime/keylime-agent.conf.backup
        cp keylime/verifier.conf.minimal keylime/verifier.conf.minimal.backup
        
        # Disable mTLS in agent config
        sed -i 's/enable_agent_mtls = true/enable_agent_mtls = false/' rust-keylime/keylime-agent.conf
        
        # Disable mTLS in verifier config
        sed -i 's/enable_agent_mtls = True/enable_agent_mtls = False/' keylime/verifier.conf.minimal
        
        echo -e "${GREEN}  ✓ mTLS disabled${NC}"
        echo "  Restart services to apply changes:"
        echo "    pkill -f keylime_agent"
        echo "    pkill -f keylime_verifier"
        echo "    ./test_complete_control_plane.sh --no-pause"
        echo "    ./test_complete.sh --no-pause"
    else
        echo "  Fix not applied."
    fi
else
    echo -e "${RED}  ✗ Both mTLS and HTTP fail${NC}"
    echo "  This indicates a deeper issue. Check:"
    echo "  1. Is the agent running? ps aux | grep keylime_agent"
    echo "  2. Is the agent listening? netstat -tln | grep 9002"
    echo "  3. Check agent logs: tail -50 /tmp/rust-keylime-agent.log"
    echo "  4. Check verifier logs: tail -50 /tmp/keylime-verifier.log"
fi
echo ""

# Step 4: Show current status
echo -e "${CYAN}[4] Current status:${NC}"
echo "  Agent mTLS: $(grep 'enable_agent_mtls' rust-keylime/keylime-agent.conf || echo 'not found')"
echo "  Verifier agent mTLS: $(grep 'enable_agent_mtls' keylime/verifier.conf.minimal || echo 'not found')"
echo "  Verifier timeout: $(grep 'agent_quote_timeout' keylime/verifier.conf.minimal || echo 'not found (using default)')"
echo ""

echo "For more details, see: TROUBLESHOOT_QUOTE_FETCHING.md"
