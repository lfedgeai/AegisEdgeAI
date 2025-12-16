#!/bin/bash
# Fix TPM Plugin Communication Issues
# This script diagnoses and fixes SPIRE Agent <-> TPM Plugin Server communication

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  TPM Plugin Communication Diagnostic & Fix                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check TPM Plugin Server
echo -e "${CYAN}Step 1: Checking TPM Plugin Server...${NC}"
if pgrep -f "tpm_plugin_server" > /dev/null; then
    echo -e "${GREEN}  ✓ TPM Plugin Server is running${NC}"
    TPM_PLUGIN_PID=$(pgrep -f "tpm_plugin_server")
    echo "    PID: $TPM_PLUGIN_PID"
else
    echo -e "${RED}  ✗ TPM Plugin Server is NOT running${NC}"
    echo "    Please start it first with: ./test_complete.sh"
    exit 1
fi
echo ""

# Step 2: Check UDS Socket
echo -e "${CYAN}Step 2: Checking UDS Socket...${NC}"
SOCKET_PATH="/tmp/spire-data/tpm-plugin/tpm-plugin.sock"
if [ -S "$SOCKET_PATH" ]; then
    echo -e "${GREEN}  ✓ UDS socket exists: $SOCKET_PATH${NC}"
    ls -la "$SOCKET_PATH"
    
    # Check permissions
    SOCKET_PERMS=$(stat -c "%a" "$SOCKET_PATH" 2>/dev/null || stat -f "%A" "$SOCKET_PATH" 2>/dev/null)
    echo "    Permissions: $SOCKET_PERMS"
    
    # Check owner
    SOCKET_OWNER=$(stat -c "%U:%G" "$SOCKET_PATH" 2>/dev/null || stat -f "%Su:%Sg" "$SOCKET_PATH" 2>/dev/null)
    echo "    Owner: $SOCKET_OWNER"
else
    echo -e "${RED}  ✗ UDS socket NOT found: $SOCKET_PATH${NC}"
    echo "    TPM Plugin Server may not have created the socket"
    exit 1
fi
echo ""

# Step 3: Test Socket Communication
echo -e "${CYAN}Step 3: Testing Socket Communication...${NC}"
echo "  Testing /get-app-key endpoint..."
RESPONSE=$(curl --unix-socket "$SOCKET_PATH" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{}' \
  -s \
  http://localhost/get-app-key 2>&1 || echo "ERROR")

if echo "$RESPONSE" | grep -q "app_key_public"; then
    echo -e "${GREEN}  ✓ TPM Plugin Server is responding correctly${NC}"
    echo "    Response preview:"
    echo "$RESPONSE" | python3 -m json.tool 2>/dev/null | head -10 | sed 's/^/      /'
else
    echo -e "${RED}  ✗ TPM Plugin Server is NOT responding correctly${NC}"
    echo "    Response: $RESPONSE"
    echo ""
    echo "  Checking TPM Plugin Server logs..."
    tail -20 /tmp/tpm-plugin-server.log
    exit 1
fi
echo ""

# Step 4: Check SPIRE Agent
echo -e "${CYAN}Step 4: Checking SPIRE Agent...${NC}"
if pgrep -f "spire-agent" > /dev/null; then
    echo -e "${GREEN}  ✓ SPIRE Agent is running${NC}"
    SPIRE_AGENT_PID=$(pgrep -f "spire-agent")
    echo "    PID: $SPIRE_AGENT_PID"
    
    # Check environment variables
    echo "  Checking environment variables..."
    if [ -f /proc/$SPIRE_AGENT_PID/environ ]; then
        TPM_ENDPOINT=$(cat /proc/$SPIRE_AGENT_PID/environ | tr '\0' '\n' | grep "TPM_PLUGIN_ENDPOINT" || echo "NOT_SET")
        UNIFIED_IDENTITY=$(cat /proc/$SPIRE_AGENT_PID/environ | tr '\0' '\n' | grep "UNIFIED_IDENTITY_ENABLED" || echo "NOT_SET")
        
        if echo "$TPM_ENDPOINT" | grep -q "unix://"; then
            echo -e "${GREEN}    ✓ TPM_PLUGIN_ENDPOINT is set: $TPM_ENDPOINT${NC}"
        else
            echo -e "${RED}    ✗ TPM_PLUGIN_ENDPOINT is NOT set correctly: $TPM_ENDPOINT${NC}"
        fi
        
        if echo "$UNIFIED_IDENTITY" | grep -q "true"; then
            echo -e "${GREEN}    ✓ UNIFIED_IDENTITY_ENABLED=true${NC}"
        else
            echo -e "${YELLOW}    ⚠ UNIFIED_IDENTITY_ENABLED: $UNIFIED_IDENTITY${NC}"
        fi
    fi
else
    echo -e "${RED}  ✗ SPIRE Agent is NOT running${NC}"
    exit 1
fi
echo ""

# Step 5: Check SPIRE Agent Logs
echo -e "${CYAN}Step 5: Analyzing SPIRE Agent Logs...${NC}"
if [ -f /tmp/spire-agent.log ]; then
    echo "  Checking for TPM Plugin errors..."
    
    if grep -q "TPM plugin not available" /tmp/spire-agent.log; then
        echo -e "${RED}  ✗ Found 'TPM plugin not available' errors${NC}"
        echo "    Recent errors:"
        grep "TPM plugin not available" /tmp/spire-agent.log | tail -5 | sed 's/^/      /'
        echo ""
        echo -e "${YELLOW}  This means SPIRE Agent cannot connect to TPM Plugin Server${NC}"
    else
        echo -e "${GREEN}  ✓ No 'TPM plugin not available' errors found${NC}"
    fi
    
    if grep -q "stub data" /tmp/spire-agent.log; then
        echo -e "${RED}  ✗ Found 'stub data' fallback${NC}"
        echo "    Recent occurrences:"
        grep "stub data" /tmp/spire-agent.log | tail -5 | sed 's/^/      /'
    else
        echo -e "${GREEN}  ✓ No stub data fallback found${NC}"
    fi
    
    if grep -q "Workload API socket" /tmp/spire-agent.log; then
        echo -e "${GREEN}  ✓ Workload API socket mentioned in logs${NC}"
    else
        echo -e "${YELLOW}  ⚠ Workload API socket not mentioned${NC}"
    fi
else
    echo -e "${RED}  ✗ SPIRE Agent log not found: /tmp/spire-agent.log${NC}"
fi
echo ""

# Step 6: Check Workload API Socket
echo -e "${CYAN}Step 6: Checking Workload API Socket...${NC}"
WORKLOAD_SOCKET="/tmp/spire-agent/public/api.sock"
if [ -S "$WORKLOAD_SOCKET" ]; then
    echo -e "${GREEN}  ✓ Workload API socket exists: $WORKLOAD_SOCKET${NC}"
    ls -la "$WORKLOAD_SOCKET"
else
    echo -e "${RED}  ✗ Workload API socket NOT found: $WORKLOAD_SOCKET${NC}"
    echo "    This means SPIRE Agent has not completed attestation"
    echo "    Agent needs successful attestation to create this socket"
fi
echo ""

# Step 7: Recommendations
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Diagnostic Summary & Recommendations                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Determine the issue
ISSUE_FOUND=false

if ! [ -S "$WORKLOAD_SOCKET" ]; then
    echo -e "${RED}Issue: Workload API socket not created${NC}"
    echo "  Root cause: SPIRE Agent attestation failed"
    echo ""
    ISSUE_FOUND=true
fi

if grep -q "TPM plugin not available" /tmp/spire-agent.log 2>/dev/null; then
    echo -e "${RED}Issue: SPIRE Agent cannot connect to TPM Plugin Server${NC}"
    echo ""
    echo "Possible causes:"
    echo "  1. TPM_PLUGIN_ENDPOINT environment variable not passed to agent process"
    echo "  2. Socket permissions issue"
    echo "  3. SPIRE Agent started before TPM Plugin Server"
    echo ""
    echo "Recommended fix:"
    echo "  1. Stop SPIRE Agent: pkill -f spire-agent"
    echo "  2. Verify TPM Plugin Server is running: ps aux | grep tpm_plugin_server"
    echo "  3. Verify socket exists: ls -la $SOCKET_PATH"
    echo "  4. Restart SPIRE Agent with correct environment:"
    echo "     export TPM_PLUGIN_ENDPOINT=\"unix://$SOCKET_PATH\""
    echo "     export UNIFIED_IDENTITY_ENABLED=\"true\""
    echo "     ./spire/bin/spire-agent run -config ./spire/conf/agent/agent.conf"
    echo ""
    ISSUE_FOUND=true
fi

if grep -q "keylime verification failed" /tmp/spire-server.log 2>/dev/null; then
    echo -e "${RED}Issue: Keylime Verifier rejected attestation${NC}"
    echo ""
    echo "  Check Keylime Verifier logs:"
    echo "    tail -50 /tmp/keylime-verifier.log | grep -i error"
    echo ""
    ISSUE_FOUND=true
fi

if [ "$ISSUE_FOUND" = false ]; then
    echo -e "${GREEN}✓ No critical issues found!${NC}"
    echo ""
    echo "All components appear to be working correctly."
fi

echo ""
echo "For detailed logs, check:"
echo "  - SPIRE Agent: tail -f /tmp/spire-agent.log"
echo "  - TPM Plugin: tail -f /tmp/tpm-plugin-server.log"
echo "  - SPIRE Server: tail -f /tmp/spire-server.log"
echo "  - Keylime Verifier: tail -f /tmp/keylime-verifier.log"
