#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Comprehensive test script for all sovereign attestation components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${SCRIPT_DIR}/spire"

echo "=========================================="
echo "Sovereign Attestation Test Suite"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

test_package() {
    local package=$1
    local name=$2
    
    echo -n "Testing ${name}... "
    if go test -v "${package}" 2>&1 | tee /tmp/sovereign_test_${name//\//_}.log; then
        echo -e "${GREEN}PASSED${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}FAILED${NC}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

cd "${SPIRE_DIR}"

echo "Running unit tests for sovereign components..."
echo ""

# Test Keylime client
test_package "./pkg/server/sovereign/keylime" "Keylime Client"

# Test Policy engine
test_package "./pkg/server/sovereign" "Policy Engine"

# Test Server SVID service with sovereign attestation
test_package "./pkg/server/api/svid/v1" "Server SVID Service (Sovereign)"

# Test Agent workload handler
test_package "./pkg/agent/endpoints/workload" "Agent Workload Handler"

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: ${PASSED}${NC}"
if [ ${FAILED} -gt 0 ]; then
    echo -e "${RED}Failed: ${FAILED}${NC}"
    echo ""
    echo "Failed test logs are available in /tmp/sovereign_test_*.log"
    exit 1
else
    echo -e "${GREEN}Failed: ${FAILED}${NC}"
    echo ""
    echo "All tests passed!"
    exit 0
fi

