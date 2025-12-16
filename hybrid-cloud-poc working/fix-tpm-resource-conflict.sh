#!/bin/bash
# Fix: TPM Resource Conflict - Disable tpm2-abrmd for Direct Quote Mode
# This script fixes the conflict between tpm2-abrmd and rust-keylime agent

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Fix: TPM Resource Conflict (The Smoking Gun)                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="${SCRIPT_DIR}/test_complete.sh"

# Step 1: Check if test_complete.sh exists
echo -e "${CYAN}[1] Checking for test_complete.sh...${NC}"
if [ ! -f "$TEST_SCRIPT" ]; then
    echo -e "${RED}✗ test_complete.sh not found at: $TEST_SCRIPT${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Found test_complete.sh${NC}"
echo ""

# Step 2: Backup the original
echo -e "${CYAN}[2] Creating backup...${NC}"
if [ ! -f "${TEST_SCRIPT}.backup" ]; then
    cp "$TEST_SCRIPT" "${TEST_SCRIPT}.backup"
    echo -e "${GREEN}✓ Backup created: ${TEST_SCRIPT}.backup${NC}"
else
    echo -e "${YELLOW}⚠ Backup already exists, skipping${NC}"
fi
echo ""

# Step 3: Disable tpm2-abrmd startup
echo -e "${CYAN}[3] Disabling tpm2-abrmd in test_complete.sh...${NC}"

# Comment out the tpm2-abrmd startup section
# We need to be careful to only comment out the startup, not the cleanup
sed -i.tmp '/# Ensure tpm2-abrmd/,/^fi$/ {
    /pkill.*tpm2-abrmd/! {
        /tpm2-abrmd/ s/^/# DISABLED_BY_FIX: /
    }
}' "$TEST_SCRIPT"

# Also comment out the tpm2-abrmd checks in the agent startup section
sed -i.tmp2 '/elif command -v tpm2-abrmd/,/fi$/ {
    s/^/# DISABLED_BY_FIX: /
}' "$TEST_SCRIPT"

rm -f "${TEST_SCRIPT}.tmp" "${TEST_SCRIPT}.tmp2"

echo -e "${GREEN}✓ Disabled tpm2-abrmd startup${NC}"
echo ""

# Step 4: Verify changes
echo -e "${CYAN}[4] Verifying changes...${NC}"
DISABLED_COUNT=$(grep -c "DISABLED_BY_FIX" "$TEST_SCRIPT" || echo "0")
if [ "$DISABLED_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $DISABLED_COUNT disabled lines${NC}"
    echo ""
    echo "  Disabled sections:"
    grep -n "DISABLED_BY_FIX" "$TEST_SCRIPT" | head -5 | sed 's/^/    /'
else
    echo -e "${YELLOW}⚠ No lines were disabled (may already be commented out)${NC}"
fi
echo ""

# Step 5: Kill existing conflicts
echo -e "${CYAN}[5] Stopping conflicting processes...${NC}"
echo "  Stopping rust-keylime agent..."
pkill -f keylime_agent 2>/dev/null || true
echo "  Stopping tpm2-abrmd..."
pkill -f tpm2-abrmd 2>/dev/null || true
echo "  Stopping SPIRE Agent..."
pkill -f spire-agent 2>/dev/null || true
sleep 2
echo -e "${GREEN}✓ Processes stopped${NC}"
echo ""

# Step 6: Clean corrupted state
echo -e "${CYAN}[6] Cleaning corrupted agent state...${NC}"
if [ -d /tmp/keylime-agent ]; then
    echo "  Removing /tmp/keylime-agent..."
    rm -rf /tmp/keylime-agent
fi
mkdir -p /tmp/keylime-agent
echo -e "${GREEN}✓ Clean state created${NC}"
echo ""

# Step 7: Verify no tpm2-abrmd is running
echo -e "${CYAN}[7] Verifying tpm2-abrmd is not running...${NC}"
if pgrep -x tpm2-abrmd >/dev/null 2>&1; then
    echo -e "${RED}✗ tpm2-abrmd is still running!${NC}"
    echo "  Attempting to kill with sudo..."
    sudo pkill -9 tpm2-abrmd 2>/dev/null || true
    sleep 1
    if pgrep -x tpm2-abrmd >/dev/null 2>&1; then
        echo -e "${RED}✗ Failed to stop tpm2-abrmd${NC}"
        echo "  Please manually stop it: sudo systemctl stop tpm2-abrmd"
        exit 1
    fi
fi
echo -e "${GREEN}✓ tpm2-abrmd is not running${NC}"
echo ""

# Step 8: Instructions for manual test
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Fix Applied Successfully!                                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${BOLD}Next Steps:${NC}"
echo ""
echo -e "${CYAN}Option A: Test Agent Manually (Recommended First)${NC}"
echo ""
echo "  Run this in your current terminal:"
echo ""
echo "    export KEYLIME_DIR=\"/tmp/keylime-agent\""
echo "    export KEYLIME_AGENT_KEYLIME_DIR=\"/tmp/keylime-agent\""
echo "    export USE_TPM2_QUOTE_DIRECT=1"
echo "    export TCTI=\"device:/dev/tpmrm0\""
echo "    export UNIFIED_IDENTITY_ENABLED=true"
echo "    cd ${SCRIPT_DIR}"
echo "    ./rust-keylime/target/release/keylime_agent"
echo ""
echo "  Expected: Agent starts and shows 'Listening on https://127.0.0.1:9002'"
echo "            Agent should stay running (not exit)"
echo ""
echo "  Then in a NEW terminal, test the agent:"
echo ""
echo "    cd ${SCRIPT_DIR}"
echo "    ./test-agent-quote-endpoint.sh"
echo ""
echo "  Expected: ✅ SUCCESS: Agent responded with quote"
echo ""
echo -e "${CYAN}Option B: Run Full Test (After Manual Test Succeeds)${NC}"
echo ""
echo "  Stop the manual agent (Ctrl+C), then run:"
echo ""
echo "    ./test_complete_control_plane.sh --no-pause"
echo "    ./test_complete.sh --no-pause"
echo ""
echo -e "${YELLOW}Note:${NC} If you need to restore the original script:"
echo "  cp ${TEST_SCRIPT}.backup ${TEST_SCRIPT}"
echo ""
