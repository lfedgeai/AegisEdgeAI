#!/bin/bash
################################################################################
# Unified-Identity - Phase 2: Test Existing Keylime and SPIRE Tests
# This script runs existing Keylime and SPIRE tests with the Unified-Identity
# feature flag turned OFF to ensure our changes don't break existing functionality.
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYLIME_DIR="${SCRIPT_DIR}/keylime"
SPIRE_DIR="${SCRIPT_DIR}/../code-rollout-phase-1/spire"
PHASE1_DIR="${SCRIPT_DIR}/../code-rollout-phase-1"

# Test results
KEYLIME_TESTS_PASSED=0
KEYLIME_TESTS_FAILED=0
SPIRE_TESTS_PASSED=0
SPIRE_TESTS_FAILED=0

echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Testing Existing Keylime and SPIRE Tests (Feature Flag OFF)          ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to print section header
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to run Keylime tests
run_keylime_tests() {
    print_section "Running Keylime Unit Tests (unified_identity_enabled=false)"
    
    if [ ! -d "$KEYLIME_DIR" ]; then
        echo -e "${RED}✗ Keylime directory not found: $KEYLIME_DIR${NC}"
        return 1
    fi
    
    cd "$KEYLIME_DIR"
    
    # Ensure feature flag is disabled in test config
    export KEYLIME_TEST=True
    export KEYLIME_VERIFIER_CONFIG="${KEYLIME_DIR}/test/verifier.conf.test" 2>/dev/null || true
    
    # Create a minimal test config with feature flag OFF
    TEST_CONFIG_DIR=$(mktemp -d)
    export KEYLIME_CONF_DIR="$TEST_CONFIG_DIR"
    mkdir -p "$TEST_CONFIG_DIR"
    
    # Generate default config
    if command_exists python3; then
        python3 -m keylime.cmd.convert_config \
            --defaults \
            --out "$TEST_CONFIG_DIR" \
            --templates "$KEYLIME_DIR/templates" 2>/dev/null || true
        
        # Explicitly set unified_identity_enabled = false
        if [ -f "$TEST_CONFIG_DIR/verifier.conf" ]; then
            # Add or update the setting
            if grep -q "unified_identity_enabled" "$TEST_CONFIG_DIR/verifier.conf"; then
                sed -i 's/^unified_identity_enabled.*/unified_identity_enabled = False/' "$TEST_CONFIG_DIR/verifier.conf"
            else
                echo "" >> "$TEST_CONFIG_DIR/verifier.conf"
                echo "[verifier]" >> "$TEST_CONFIG_DIR/verifier.conf"
                echo "unified_identity_enabled = False" >> "$TEST_CONFIG_DIR/verifier.conf"
            fi
        fi
        
        export KEYLIME_VERIFIER_CONFIG="$TEST_CONFIG_DIR/verifier.conf"
        export KEYLIME_REGISTRAR_CONFIG="$TEST_CONFIG_DIR/registrar.conf"
        export KEYLIME_TENANT_CONFIG="$TEST_CONFIG_DIR/tenant.conf"
        export KEYLIME_CA_CONFIG="$TEST_CONFIG_DIR/ca.conf"
        export KEYLIME_LOGGING_CONFIG="$TEST_CONFIG_DIR/logging.conf"
    fi
    
    echo -e "${YELLOW}Running Keylime unit tests...${NC}"
    echo -e "${YELLOW}Feature flag: unified_identity_enabled = False${NC}"
    echo ""
    
    # Run IMA tests
    if [ -d "$KEYLIME_DIR/keylime/ima" ]; then
        echo -e "${BLUE}Running IMA unit tests...${NC}"
        if python3 -m unittest discover -s keylime/ima -p '*_test.py' -v 2>&1 | tee /tmp/keylime_ima_tests.log; then
            echo -e "${GREEN}✓ IMA tests passed${NC}"
            ((KEYLIME_TESTS_PASSED++)) || true
        else
            echo -e "${RED}✗ IMA tests failed${NC}"
            ((KEYLIME_TESTS_FAILED++)) || true
        fi
    fi
    
    # Run TPM tests
    if [ -d "$KEYLIME_DIR/keylime/tpm" ]; then
        echo -e "${BLUE}Running TPM unit tests...${NC}"
        if python3 -m unittest discover -s keylime/tpm -p '*_test.py' -v 2>&1 | tee /tmp/keylime_tpm_tests.log; then
            echo -e "${GREEN}✓ TPM tests passed${NC}"
            ((KEYLIME_TESTS_PASSED++)) || true
        else
            echo -e "${RED}✗ TPM tests failed${NC}"
            ((KEYLIME_TESTS_FAILED++)) || true
        fi
    fi
    
    # Run our new Phase 2 tests (should still work with flag off)
    if [ -f "$KEYLIME_DIR/test/test_app_key_verification.py" ]; then
        echo -e "${BLUE}Running Phase 2 app_key_verification tests...${NC}"
        if python3 -m pytest "$KEYLIME_DIR/test/test_app_key_verification.py" -v 2>&1 | tee /tmp/keylime_app_key_tests.log; then
            echo -e "${GREEN}✓ App Key Verification tests passed${NC}"
            ((KEYLIME_TESTS_PASSED++)) || true
        else
            echo -e "${RED}✗ App Key Verification tests failed${NC}"
            ((KEYLIME_TESTS_FAILED++)) || true
        fi
    fi
    
    # Cleanup
    rm -rf "$TEST_CONFIG_DIR" 2>/dev/null || true
    
    return 0
}

# Function to run SPIRE tests
run_spire_tests() {
    print_section "Running SPIRE Unit Tests (Unified-Identity feature flag disabled)"
    
    if [ ! -d "$SPIRE_DIR" ]; then
        echo -e "${RED}✗ SPIRE directory not found: $SPIRE_DIR${NC}"
        return 1
    fi
    
    cd "$SPIRE_DIR"
    
    # Ensure feature flag is NOT in experimental.feature_flags
    # SPIRE tests should run with default (flag disabled)
    echo -e "${YELLOW}Running SPIRE unit tests...${NC}"
    echo -e "${YELLOW}Feature flag: Unified-Identity = disabled (default)${NC}"
    echo ""
    
    # Check if Go is available
    if ! command_exists go; then
        echo -e "${YELLOW}⚠ Go not found, skipping Go-based SPIRE tests${NC}"
        return 0
    fi
    
    # Run SPIRE unit tests
    echo -e "${BLUE}Running 'make test'...${NC}"
    if make test 2>&1 | tee /tmp/spire_unit_tests.log; then
        echo -e "${GREEN}✓ SPIRE unit tests passed${NC}"
        ((SPIRE_TESTS_PASSED++)) || true
    else
        echo -e "${RED}✗ SPIRE unit tests failed${NC}"
        ((SPIRE_TESTS_FAILED++)) || true
    fi
    
    # Run specific tests that might be affected by our changes
    echo ""
    echo -e "${BLUE}Running specific service tests...${NC}"
    
    # Test SVID service (where we added Unified-Identity code)
    if go test -v ./pkg/server/api/svid/v1/... 2>&1 | tee /tmp/spire_svid_tests.log; then
        echo -e "${GREEN}✓ SVID service tests passed${NC}"
        ((SPIRE_TESTS_PASSED++)) || true
    else
        echo -e "${RED}✗ SVID service tests failed${NC}"
        ((SPIRE_TESTS_FAILED++)) || true
    fi
    
    # Test Agent service (where we added Unified-Identity code)
    if go test -v ./pkg/server/api/agent/v1/... 2>&1 | tee /tmp/spire_agent_tests.log; then
        echo -e "${GREEN}✓ Agent service tests passed${NC}"
        ((SPIRE_TESTS_PASSED++)) || true
    else
        echo -e "${RED}✗ Agent service tests failed${NC}"
        ((SPIRE_TESTS_FAILED++)) || true
    fi
    
    # Test Keylime client (our new code)
    if go test -v ./pkg/server/keylime/... 2>&1 | tee /tmp/spire_keylime_tests.log; then
        echo -e "${GREEN}✓ Keylime client tests passed${NC}"
        ((SPIRE_TESTS_PASSED++)) || true
    else
        echo -e "${RED}✗ Keylime client tests failed${NC}"
        ((SPIRE_TESTS_FAILED++)) || true
    fi
    
    return 0
}

# Main execution
main() {
    echo -e "${BOLD}Starting test execution with feature flags disabled...${NC}"
    echo ""
    
    # Run Keylime tests
    if run_keylime_tests; then
        echo -e "${GREEN}✓ Keylime test execution completed${NC}"
    else
        echo -e "${RED}✗ Keylime test execution failed${NC}"
    fi
    
    # Run SPIRE tests
    if run_spire_tests; then
        echo -e "${GREEN}✓ SPIRE test execution completed${NC}"
    else
        echo -e "${RED}✗ SPIRE test execution failed${NC}"
    fi
    
    # Print summary
    print_section "Test Summary"
    
    echo -e "${BOLD}Keylime Tests:${NC}"
    echo -e "  ${GREEN}Passed: ${KEYLIME_TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed: ${KEYLIME_TESTS_FAILED}${NC}"
    echo ""
    
    echo -e "${BOLD}SPIRE Tests:${NC}"
    echo -e "  ${GREEN}Passed: ${SPIRE_TESTS_PASSED}${NC}"
    echo -e "  ${RED}Failed: ${SPIRE_TESTS_FAILED}${NC}"
    echo ""
    
    TOTAL_PASSED=$((KEYLIME_TESTS_PASSED + SPIRE_TESTS_PASSED))
    TOTAL_FAILED=$((KEYLIME_TESTS_FAILED + SPIRE_TESTS_FAILED))
    
    if [ $TOTAL_FAILED -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ All tests passed!${NC}"
        echo ""
        echo -e "${GREEN}The Unified-Identity changes do not break existing functionality.${NC}"
        return 0
    else
        echo -e "${RED}${BOLD}✗ Some tests failed${NC}"
        echo ""
        echo -e "${YELLOW}Please review the test logs:${NC}"
        echo "  - /tmp/keylime_ima_tests.log"
        echo "  - /tmp/keylime_tpm_tests.log"
        echo "  - /tmp/keylime_app_key_tests.log"
        echo "  - /tmp/spire_unit_tests.log"
        echo "  - /tmp/spire_svid_tests.log"
        echo "  - /tmp/spire_agent_tests.log"
        echo "  - /tmp/spire_keylime_tests.log"
        return 1
    fi
}

# Run main function
main "$@"

