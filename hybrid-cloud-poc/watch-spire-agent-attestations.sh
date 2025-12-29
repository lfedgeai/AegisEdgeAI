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

# Watch SPIRE Agent attestation events in real-time
# Filters for attestation-related log entries
# Usage: ./watch-spire-agent-attestations.sh

LOG_FILE="/tmp/spire-agent.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Disable colors if output is not a terminal
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
    GREEN=""
    YELLOW=""
    CYAN=""
    BOLD=""
    NC=""
fi

echo "=========================================="
echo "Watching SPIRE Agent Attestation Events"
echo "=========================================="
echo "Log file: $LOG_FILE"
echo "Filtering for: TPM Plugin, SovereignAttestation, TPM Quote, Agent SVID, Workload, Unified-Identity, attest"
echo "Press Ctrl+C to stop"
echo "=========================================="
echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo "Warning: Log file not found: $LOG_FILE"
    echo "Waiting for log file to be created..."
    while [ ! -f "$LOG_FILE" ]; do
        sleep 1
    done
    echo "Log file created, starting to watch..."
fi

# Initialize reattestation count
REATTEST_COUNT=$(grep -c 'level=info msg="Successfully reattested node"' "$LOG_FILE" 2>/dev/null || echo "0")
echo -e "${CYAN}Initial reattestation count: ${BOLD}$REATTEST_COUNT${NC}"
echo "=========================================="
echo ""

# Watch log file and update count when reattestation occurs
tail -f "$LOG_FILE" | while IFS= read -r line; do
    # Check if this line matches our filter
    if echo "$line" | grep -qE "TPM Plugin|SovereignAttestation|TPM Quote|certificate|Agent SVID|Workload|Unified-Identity|attest|python-app|BatchNewX509SVID"; then
        # If this is a reattestation message, update count first
        if echo "$line" | grep -q 'level=info msg="Successfully reattested node"'; then
            REATTEST_COUNT=$((REATTEST_COUNT + 1))
            echo ""
            echo -e "${GREEN}${BOLD}>>> [Reattestation #$REATTEST_COUNT]${NC} ${YELLOW}$line${NC}"
            echo ""
        else
            echo "$line"
        fi
    fi
done
