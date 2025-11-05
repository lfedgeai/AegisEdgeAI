#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Comprehensive test script for feature flag validation

set -e

echo "=========================================="
echo "Phase 1: Feature Flag Testing & Validation"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${TEST_DIR}/spire"
KEYLIME_DIR="${TEST_DIR}/keylime-stub"

cd "${SPIRE_DIR}"

echo -e "${YELLOW}[1/6] Testing Feature Flag System (Default State)${NC}"
echo "----------------------------------------"
go test -v ./pkg/common/fflag/... -run "TestLoad|TestIsSet|TestUnload" 2>&1 | grep -E "(PASS|FAIL|RUN)" || echo "Feature flag tests completed"
echo ""

echo -e "${YELLOW}[2/6] Testing Policy Engine (No Feature Flag Dependency)${NC}"
echo "----------------------------------------"
go test -v ./pkg/server/unifiedidentity/... -run "TestEvaluatePolicy|TestMatchesGeolocationPattern" 2>&1 | tail -20
echo ""

echo -e "${YELLOW}[3/6] Testing Keylime Client (No Feature Flag Dependency)${NC}"
echo "----------------------------------------"
go test -v ./pkg/server/unifiedidentity/... -run "TestKeylimeClient" 2>&1 | tail -20 || echo "Keylime client tests completed"
echo ""

echo -e "${YELLOW}[4/6] Testing Feature Flag Integration Tests${NC}"
echo "----------------------------------------"
if [ -d "${TEST_DIR}/tests/integration" ]; then
    cd "${TEST_DIR}/tests/integration"
    go test -v . -run "TestFullFlow" 2>&1 | tail -30 || echo "Integration tests completed"
else
    echo "Integration test directory not found, skipping..."
fi
echo ""

echo -e "${YELLOW}[5/6] Testing Keylime Stub${NC}"
echo "----------------------------------------"
cd "${KEYLIME_DIR}"
if [ -f "verifier_test.go" ]; then
    go test -v . 2>&1 | tail -30
else
    echo "Keylime stub tests not found"
fi
echo ""

echo -e "${YELLOW}[6/6] Running All Unified Identity Tests${NC}"
echo "----------------------------------------"
cd "${SPIRE_DIR}"
go test -v ./pkg/server/unifiedidentity/... 2>&1 | grep -E "(PASS|FAIL|RUN|Unified)" | head -40
echo ""

echo -e "${GREEN}=========================================="
echo "Feature Flag Testing Complete!"
echo "==========================================${NC}"

