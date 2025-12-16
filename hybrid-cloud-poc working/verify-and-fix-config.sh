#!/bin/bash
# Script to verify and fix Keylime Verifier configuration
# This ensures the config file has the correct format to avoid crashes

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Keylime Verifier Configuration Verification & Fix            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/keylime/verifier.conf.minimal"

echo -e "${CYAN}[1] Checking if config file exists...${NC}"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}✗ Config file not found: $CONFIG_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Config file found${NC}"
echo ""

echo -e "${CYAN}[2] Checking for [revocations] section...${NC}"
if ! grep -q "^\[revocations\]" "$CONFIG_FILE"; then
    echo -e "${RED}✗ [revocations] section missing${NC}"
    echo "  Adding [revocations] section..."
    cat >> "$CONFIG_FILE" << 'EOF'

[revocations]
# Revocation notifications configuration
# Empty list means no revocation notifications enabled
enabled_revocation_notifications = []
zmq_port = 5556
EOF
    echo -e "${GREEN}✓ [revocations] section added${NC}"
else
    echo -e "${GREEN}✓ [revocations] section exists${NC}"
fi
echo ""

echo -e "${CYAN}[3] Checking for enabled_revocation_notifications...${NC}"
if ! grep -q "^enabled_revocation_notifications" "$CONFIG_FILE"; then
    echo -e "${RED}✗ enabled_revocation_notifications missing${NC}"
    echo "  Adding enabled_revocation_notifications..."
    # Add after [revocations] section
    sed -i '/^\[revocations\]/a enabled_revocation_notifications = []' "$CONFIG_FILE"
    echo -e "${GREEN}✓ enabled_revocation_notifications added${NC}"
else
    # Check if it has the correct value (empty list)
    if grep -q "^enabled_revocation_notifications = \[\]" "$CONFIG_FILE"; then
        echo -e "${GREEN}✓ enabled_revocation_notifications = [] (correct)${NC}"
    else
        echo -e "${YELLOW}⚠ enabled_revocation_notifications has wrong value${NC}"
        echo "  Fixing value to []..."
        sed -i 's/^enabled_revocation_notifications = .*/enabled_revocation_notifications = []/' "$CONFIG_FILE"
        echo -e "${GREEN}✓ Fixed to enabled_revocation_notifications = []${NC}"
    fi
fi
echo ""

echo -e "${CYAN}[4] Verifying other required settings...${NC}"

# Check unified_identity_enabled
if grep -q "^unified_identity_enabled = true" "$CONFIG_FILE"; then
    echo -e "${GREEN}✓ unified_identity_enabled = true${NC}"
else
    echo -e "${YELLOW}⚠ unified_identity_enabled not set to true${NC}"
fi

# Check agent_quote_timeout_seconds
if grep -q "^agent_quote_timeout_seconds" "$CONFIG_FILE"; then
    TIMEOUT=$(grep "^agent_quote_timeout_seconds" "$CONFIG_FILE" | cut -d'=' -f2 | tr -d ' ')
    echo -e "${GREEN}✓ agent_quote_timeout_seconds = $TIMEOUT${NC}"
else
    echo -e "${YELLOW}⚠ agent_quote_timeout_seconds not set (will use default)${NC}"
fi

echo ""
echo -e "${CYAN}[5] Configuration Summary:${NC}"
echo "  Config file: $CONFIG_FILE"
echo ""
echo "  Key settings:"
grep -E "^(unified_identity_enabled|enabled_revocation_notifications|agent_quote_timeout_seconds|port)" "$CONFIG_FILE" | sed 's/^/    /'
echo ""

echo -e "${GREEN}✓ Configuration verification complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Copy this file to your Linux machine if you haven't already"
echo "  2. Run: ./test_complete_control_plane.sh --no-pause"
echo "  3. Then run: ./test_complete.sh --no-pause"
echo ""
