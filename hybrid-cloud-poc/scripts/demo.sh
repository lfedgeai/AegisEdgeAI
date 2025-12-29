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

# Unified-Identity: Demo - Generate Sovereign SVID
# This script demonstrates the complete workflow for generating a Sovereign SVID
# with TPM attestation and geolocation claims.
#
# Prerequisites: All services must be running (SPIRE Server/Agent, Keylime Verifier, rust-keylime Agent)
# This script can be called standalone or reused by test_agents.sh
#
# Usage:
#   ./scripts/demo.sh          # Standalone mode with full output
#   ./scripts/demo.sh --quiet  # Quiet mode for integration (suppresses header)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# If this script is in scripts/, go up one level to project root
if [ "$(basename "${SCRIPT_DIR}")" = "scripts" ]; then
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
    PROJECT_ROOT="${SCRIPT_DIR}"
fi
# All components are now consolidated in the root directory
PHASE1_DIR="${PROJECT_ROOT}"
PHASE2_DIR="${PROJECT_ROOT}"

# Check for quiet mode
QUIET_MODE=false
if [ "${1:-}" = "--quiet" ]; then
    QUIET_MODE=true
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
    GREEN=""
    RED=""
    YELLOW=""
    CYAN=""
    NC=""
fi

if [ "$QUIET_MODE" = false ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Unified-Identity: Sovereign SVID Demo                       ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "This demo generates a Sovereign SVID with:"
    echo "  • TPM App Key attestation"
    echo "  • Geolocation claims (TPM-bound via PCR 17)"
    echo "  • Unified Identity claims (grc.* format)"
    echo ""
    echo "Workflow:"
    echo "  1. Workload requests SVID with SovereignAttestation"
    echo "  2. SPIRE Agent TPM plugin generates App Key and Quote"
    echo "  3. SPIRE Agent TPM plugin requests certificate from rust-keylime agent"
    echo "  4. SPIRE Agent sends SovereignAttestation to SPIRE Server"
    echo "  5. SPIRE Server calls Keylime Verifier"
    echo "  6. Keylime Verifier validates and returns AttestedClaims"
    echo "  7. SPIRE Server evaluates policy and returns AttestedClaims"
    echo "  8. Workload receives SVID + AttestedClaims"
    echo ""
fi

# Check if services are running
echo -e "${CYAN}Checking prerequisites...${NC}"
MISSING_SERVICES=0

if ! pgrep -f "spire-server" >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ SPIRE Server is not running${NC}"
    MISSING_SERVICES=$((MISSING_SERVICES + 1))
else
    echo -e "${GREEN}  ✓ SPIRE Server is running${NC}"
fi

if ! pgrep -f "spire-agent" >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ SPIRE Agent is not running${NC}"
    MISSING_SERVICES=$((MISSING_SERVICES + 1))
else
    echo -e "${GREEN}  ✓ SPIRE Agent is running${NC}"
fi

# Check for Keylime Verifier - it can be started as python3 -m keylime.cmd.verifier
if ! pgrep -f "python.*keylime.*verifier\|keylime.cmd.verifier\|keylime_verifier\|nohup.*keylime.*verifier" >/dev/null 2>&1; then
    # Also check if the port is listening (verifier might be running but process name different)
    if ! netstat -tuln 2>/dev/null | grep -q ":8881" && ! ss -tuln 2>/dev/null | grep -q ":8881"; then
        echo -e "${YELLOW}  ⚠ Keylime Verifier is not running${NC}"
        MISSING_SERVICES=$((MISSING_SERVICES + 1))
    else
        echo -e "${GREEN}  ✓ Keylime Verifier is running (port 8881 is listening)${NC}"
    fi
else
    echo -e "${GREEN}  ✓ Keylime Verifier is running${NC}"
fi

if ! pgrep -f "keylime_agent" >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ rust-keylime Agent is not running${NC}"
    MISSING_SERVICES=$((MISSING_SERVICES + 1))
else
    echo -e "${GREEN}  ✓ rust-keylime Agent is running${NC}"
fi

if [ "$MISSING_SERVICES" -gt 0 ]; then
    if [ "$QUIET_MODE" = true ]; then
        # In quiet mode, just log a warning and continue (test script is responsible for services)
        echo -e "${YELLOW}  ⚠ Warning: $MISSING_SERVICES service(s) are not running (continuing anyway in quiet mode)${NC}"
    else
        # In standalone mode, prompt the user
        echo ""
        echo -e "${YELLOW}⚠ Warning: $MISSING_SERVICES service(s) are not running${NC}"
        echo "  Please start all services before running this demo."
        echo "  You can use: ./test_phase3_complete.sh (which will start everything)"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

echo ""
echo -e "${CYAN}Generating Sovereign SVID...${NC}"
echo ""

cd "${PHASE1_DIR}/python-app-demo"
if [ -f "./fetch-sovereign-svid-grpc.py" ]; then
    python3 fetch-sovereign-svid-grpc.py
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Sovereign SVID generated successfully${NC}"

        # Check if SVID was created
        if [ -f "/tmp/svid-dump/svid.pem" ]; then
            echo ""
            echo "To view the SVID certificate with Unified Identity claims extension:"
            if [ -f "${PHASE2_DIR}/dump-svid-attested-claims.sh" ]; then
                echo "  ${PHASE2_DIR}/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem"
            else
                echo "  openssl x509 -in /tmp/svid-dump/svid.pem -text -noout | grep -A 2 \"1.3.6.1.4.1.99999\""
            fi
        fi

        echo ""
        echo -e "${GREEN}Demo completed successfully!${NC}"
        exit 0
    else
        echo ""
        echo -e "${RED}✗ Sovereign SVID generation failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ fetch-sovereign-svid-grpc.py not found${NC}"
    exit 1
fi
