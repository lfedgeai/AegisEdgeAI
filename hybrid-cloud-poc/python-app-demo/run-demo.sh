#!/bin/bash

# Copyright 2025 AegisSovereignAI Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Unified-Identity - Unified-Identity & Unified-Identity: Complete demo script with Real Keylime Verifier
# Sets up SPIRE, creates registration entry, fetches SVID, and dumps it

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SPIRE_DIR="${PROJECT_ROOT}/spire"
PHASE2_DIR="${PROJECT_ROOT}"
cd "$SCRIPT_DIR"

# ANSI color codes for step headers
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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
echo "║  Unified-Identity - Unified-Identity & Unified-Identity: Python App Demo         ║"
echo "║  Using Real Keylime Verifier (Unified-Identity)                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "ℹ This demo uses the real Keylime Verifier with Unified-Identity implementation"
echo ""

# Step 0: Cleanup any existing setup
echo -e "${BOLD}${CYAN}Step 0: Cleaning up any existing setup...${RESET}"
echo "  (This removes SPIRE data directory to ensure no entries persist)"
echo ""

# Clean up registration entries FIRST (while server might still be running)
SERVER_SOCKET="/tmp/spire-server/private/api.sock"
if [ -S "$SERVER_SOCKET" ] && [ -f "${SPIRE_DIR}/bin/spire-server" ]; then
    echo "  Cleaning up SPIRE registration entries..."
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

# Stop processes using Unified-Identity stop script
if [ -f "${PROJECT_ROOT}/scripts/stop-unified-identity-phase2.sh" ]; then
    "${PROJECT_ROOT}/scripts/stop-unified-identity-phase2.sh" >/dev/null 2>&1 || true
fi

# Additional cleanup
pkill -f "spire-server" >/dev/null 2>&1 || true
pkill -f "spire-agent" >/dev/null 2>&1 || true
pkill -f "keylime" >/dev/null 2>&1 || true

sleep 2

# Clean up log files
rm -f /tmp/spire-server.log /tmp/spire-agent.log /tmp/keylime-verifier.log 2>/dev/null || true

# Step 1: Setup SPIRE and Real Keylime Verifier
echo -e "${BOLD}${CYAN}Step 1: Setting up SPIRE and Real Keylime Verifier (Unified-Identity)...${RESET}"
echo ""

# Check if Unified-Identity is available
if [ ! -d "${PHASE2_DIR}" ]; then
    echo -e "${RED}Error: Unified-Identity directory not found at ${PHASE2_DIR}${RESET}"
    exit 1
fi

# Set Keylime Verifier URL for SPIRE Server
export KEYLIME_VERIFIER_URL="${KEYLIME_VERIFIER_URL:-http://localhost:8881}"

echo "  Using Keylime Verifier URL: ${KEYLIME_VERIFIER_URL}"
echo ""

# Start SPIRE and Keylime using Unified-Identity script
"${PROJECT_ROOT}/scripts/start-unified-identity-phase2.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to start SPIRE stack${RESET}"
    exit 1
fi

prompt_continue

# Step 2: Create Registration Entry
echo -e "${BOLD}${CYAN}Step 2: Creating registration entry...${RESET}"
echo ""

./create-registration-entry.sh

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create registration entry${RESET}"
    exit 1
fi

prompt_continue

# Step 3: Fetch Sovereign SVID
echo -e "${BOLD}${CYAN}Step 3: Fetching Sovereign SVID with AttestedClaims...${RESET}"
echo ""
echo "  This will:"
echo "    1. Connect to SPIRE Agent Workload API"
echo "    2. Agent sends SovereignAttestation to Server"
echo "    3. Server calls Real Keylime Verifier (Unified-Identity)"
echo "    4. Keylime Verifier validates and returns AttestedClaims"
echo "    5. Server evaluates policy and returns AttestedClaims"
echo "    6. Agent passes AttestedClaims to Python app"
echo ""

python3 fetch-sovereign-svid-grpc.py

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to fetch SVID${RESET}"
    exit 1
fi

prompt_continue

# Step 4: Display Results
echo -e "${BOLD}${CYAN}Step 4: Displaying results...${RESET}"
echo ""

if [ -f /tmp/svid-dump/svid.pem ]; then
    echo -e "${GREEN}✓ SVID saved to /tmp/svid-dump/svid.pem${RESET}"
    echo ""
    echo "Certificate details:"
    openssl x509 -in /tmp/svid-dump/svid.pem -text -noout | grep -E "Subject:|Issuer:|Not Before|Not After" | head -4
    echo ""
else
    echo -e "${YELLOW}⚠ SVID file not found${RESET}"
fi

if [ -f /tmp/svid-dump/attested_claims.json ]; then
    echo -e "${GREEN}✓ AttestedClaims saved to /tmp/svid-dump/attested_claims.json${RESET}"
    echo ""
    echo "AttestedClaims from Real Keylime Verifier (Unified-Identity):"
    cat /tmp/svid-dump/attested_claims.json | python3 -m json.tool 2>/dev/null || cat /tmp/svid-dump/attested_claims.json
    echo ""
else
    echo -e "${YELLOW}⚠ AttestedClaims file not found${RESET}"
fi

# Step 5: Show Logs
echo -e "${BOLD}${CYAN}Step 5: Unified-Identity Logs${RESET}"
echo ""

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  SPIRE Server Logs - Unified-Identity                         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
if [ -f /tmp/spire-server.log ]; then
    grep -i "unified-identity" /tmp/spire-server.log | tail -15 || echo "⚠ No Unified-Identity logs found"
else
    echo "⚠ SPIRE Server log file not found: /tmp/spire-server.log"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  SPIRE Agent Logs - Unified-Identity                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
if [ -f /tmp/spire-agent.log ]; then
    grep -i "unified-identity" /tmp/spire-agent.log | tail -15 || echo "⚠ No Unified-Identity logs found"
else
    echo "⚠ SPIRE Agent log file not found: /tmp/spire-agent.log"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Keylime Verifier Logs - Unified-Identity (Unified-Identity)           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
if [ -f /tmp/keylime-verifier.log ]; then
    grep -i "unified-identity.*Unified-Identity" /tmp/keylime-verifier.log | tail -15 || echo "⚠ No Unified-Identity Unified-Identity logs found"
else
    echo "⚠ Keylime Verifier log file not found: /tmp/keylime-verifier.log"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Demo Complete                                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Files created:"
echo "  SVID:           /tmp/svid-dump/svid.pem"
echo "  AttestedClaims: /tmp/svid-dump/attested_claims.json"
echo ""
echo "Log files:"
echo "  SPIRE Server:     /tmp/spire-server.log"
echo "  SPIRE Agent:      /tmp/spire-agent.log"
echo "  Keylime Verifier: /tmp/keylime-verifier.log"
echo ""
echo "To view logs in real-time:"
echo "  tail -f /tmp/spire-server.log"
echo "  tail -f /tmp/spire-agent.log"
echo "  tail -f /tmp/keylime-verifier.log"
echo ""
echo "To stop all services:"
echo "  ${PROJECT_ROOT}/scripts/stop-unified-identity-phase2.sh"
echo ""
