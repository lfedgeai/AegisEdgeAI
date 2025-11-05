#!/bin/bash
set -e

echo "=========================================="
echo "Phase 1: Comprehensive Test Suite"
echo "=========================================="
echo ""

SPIRE_DIR="spire"
KEYLIME_DIR="keylime-stub"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    echo -e "${YELLOW}[TEST]${NC} $test_name"
    if eval "$test_cmd" > /tmp/test_output.log 2>&1; then
        echo -e "${GREEN}[PASS]${NC} $test_name"
        ((PASS_COUNT++))
        ((TEST_COUNT++))
        return 0
    else
        echo -e "${RED}[FAIL]${NC} $test_name"
        cat /tmp/test_output.log | tail -20
        ((FAIL_COUNT++))
        ((TEST_COUNT++))
        return 1
    fi
}

echo "=== Feature Flag System Tests ==="
cd "$SPIRE_DIR"
run_test "Feature Flag System" "go test -v ./pkg/common/fflag/..."
echo ""

echo "=== Unified Identity Tests (Feature Flag Disabled) ==="
run_test "Policy Engine Tests" "go test -v ./pkg/server/unifiedidentity/... -run 'TestEvaluatePolicy|TestMatchesGeolocationPattern'"
run_test "Feature Flag Disabled Tests" "go test -v ./pkg/server/unifiedidentity/... -run TestFeatureFlagDisabled"
echo ""

echo "=== Unified Identity Tests (Feature Flag Enabled) ==="
run_test "Feature Flag Enabled Tests" "go test -v ./pkg/server/unifiedidentity/... -run TestFeatureFlagEnabled"
run_test "Keylime Client Tests" "go test -v ./pkg/server/unifiedidentity/... -run 'TestFeatureFlag.*Keylime'"
echo ""

echo "=== All Unified Identity Tests ==="
run_test "Complete Unified Identity Suite" "go test -v ./pkg/server/unifiedidentity/..."
echo ""

echo "=== Keylime Stub Tests ==="
cd "../$KEYLIME_DIR"
if [ -f "verifier_test.go" ]; then
    run_test "Keylime Stub Verifier" "go test -v ."
else
    echo -e "${YELLOW}[SKIP]${NC} Keylime stub tests not found"
fi
echo ""

cd "../$SPIRE_DIR"

echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total Tests: $TEST_COUNT"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}Failed: $FAIL_COUNT${NC}"
else
    echo "Failed: 0"
fi

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "\n${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}❌ Some tests failed${NC}"
    exit 1
fi
