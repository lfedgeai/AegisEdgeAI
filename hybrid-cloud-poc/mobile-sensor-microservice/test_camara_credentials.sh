#!/bin/bash
# Test script to verify CAMARA credentials loading logic

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_SENSOR_DIR="$SCRIPT_DIR"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Testing CAMARA Credentials Loading Logic"
echo "=========================================="
echo ""

# Test 1: Check if file reading logic exists in test_onprem.sh
echo "Test 1: Verifying test_onprem.sh has file reading logic..."
if grep -q "camara_basic_auth.txt" "$REPO_ROOT/enterprise-private-cloud/test_onprem.sh"; then
    echo "✓ PASS: test_onprem.sh contains file reading logic"
else
    echo "✗ FAIL: test_onprem.sh does not contain file reading logic"
    exit 1
fi

# Test 2: Check if hardcoded credentials are removed
echo ""
echo "Test 2: Verifying hardcoded credentials are removed from test_onprem.sh..."
if grep -q "NDcyOWY5ZDItMmVmNy00NTdhLWJlMzMtMGVkZjg4ZDkwZjA0OmU5N2M0Mzg0LTI4MDYtNDQ5YS1hYzc1LWUyZDJkNzNlOWQ0Ng==" "$REPO_ROOT/enterprise-private-cloud/test_onprem.sh"; then
    echo "✗ FAIL: Hardcoded credentials still present in test_onprem.sh"
    exit 1
else
    echo "✓ PASS: Hardcoded credentials removed from test_onprem.sh"
fi

# Test 3: Check test_complete_control_plane.sh
echo ""
echo "Test 3: Verifying test_complete_control_plane.sh has file reading logic..."
if grep -q "camara_basic_auth.txt" "$REPO_ROOT/test_complete_control_plane.sh"; then
    echo "✓ PASS: test_complete_control_plane.sh contains file reading logic"
else
    echo "✗ FAIL: test_complete_control_plane.sh does not contain file reading logic"
    exit 1
fi

# Test 4: Check if hardcoded credentials are removed from test_complete_control_plane.sh
echo ""
echo "Test 4: Verifying hardcoded credentials are removed from test_complete_control_plane.sh..."
if grep -q "NDcyOWY5ZDItMmVmNy00NTdhLWJlMzMtMGVkZjg4ZDkwZjA0OmU5N2M0Mzg0LTI4MDYtNDQ5YS1hYzc1LWUyZDJkNzNlOWQ0Ng==" "$REPO_ROOT/test_complete_control_plane.sh"; then
    echo "✗ FAIL: Hardcoded credentials still present in test_complete_control_plane.sh"
    exit 1
else
    echo "✓ PASS: Hardcoded credentials removed from test_complete_control_plane.sh"
fi

# Test 5: Test file reading function (simulate)
echo ""
echo "Test 5: Testing file reading logic..."
TEST_FILE="$REPO_ROOT/mobile-sensor-microservice/camara_basic_auth.txt.test"
TEST_VALUE="Basic dGVzdF9jbGllbnRfaWQ6dGVzdF9jbGllbnRfc2VjcmV0"

# Create test file
mkdir -p "$(dirname "$TEST_FILE")"
echo "$TEST_VALUE" > "$TEST_FILE"
chmod 600 "$TEST_FILE"

# Test reading (using same logic as scripts)
if [ -f "$TEST_FILE" ]; then
    READ_VALUE=$(cat "$TEST_FILE" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 200)
    if [ "$READ_VALUE" = "$TEST_VALUE" ]; then
        echo "✓ PASS: File reading works correctly"
    else
        echo "✗ FAIL: File reading returned incorrect value"
        echo "  Expected: $TEST_VALUE"
        echo "  Got: $READ_VALUE"
        exit 1
    fi
else
    echo "✗ FAIL: Could not create test file"
    exit 1
fi

# Cleanup test file
rm -f "$TEST_FILE"
echo "  Cleaned up test file"

# Test 6: Verify file locations are checked
echo ""
echo "Test 6: Verifying file location checks..."
LOCATIONS_FOUND=0

# Check test_onprem.sh locations
if grep -q "\$REPO_ROOT/mobile-sensor-microservice/camara_basic_auth.txt" "$REPO_ROOT/enterprise-private-cloud/test_onprem.sh"; then
    LOCATIONS_FOUND=$((LOCATIONS_FOUND + 1))
fi
if grep -q "\$REPO_ROOT/camara_basic_auth.txt" "$REPO_ROOT/enterprise-private-cloud/test_onprem.sh"; then
    LOCATIONS_FOUND=$((LOCATIONS_FOUND + 1))
fi

# Check test_complete_control_plane.sh locations
if grep -q "\${MOBILE_SENSOR_DIR}/camara_basic_auth.txt" "$REPO_ROOT/test_complete_control_plane.sh"; then
    LOCATIONS_FOUND=$((LOCATIONS_FOUND + 1))
fi
if grep -q "\${SCRIPT_DIR}/camara_basic_auth.txt" "$REPO_ROOT/test_complete_control_plane.sh"; then
    LOCATIONS_FOUND=$((LOCATIONS_FOUND + 1))
fi

if [ $LOCATIONS_FOUND -ge 2 ]; then
    echo "✓ PASS: Multiple file locations are checked ($LOCATIONS_FOUND found)"
else
    echo "✗ FAIL: Not enough file locations checked (found $LOCATIONS_FOUND)"
    exit 1
fi

# Test 7: Verify error handling
echo ""
echo "Test 7: Verifying error messages are present..."
if grep -q "CAMARA_BYPASS=false but CAMARA_BASIC_AUTH is not set" "$REPO_ROOT/enterprise-private-cloud/test_onprem.sh"; then
    echo "✓ PASS: Error message present in test_onprem.sh"
else
    echo "✗ FAIL: Error message missing in test_onprem.sh"
    exit 1
fi

if grep -q "CAMARA_BYPASS=false but CAMARA_BASIC_AUTH is not set" "$REPO_ROOT/test_complete_control_plane.sh"; then
    echo "✓ PASS: Error message present in test_complete_control_plane.sh"
else
    echo "✗ FAIL: Error message missing in test_complete_control_plane.sh"
    exit 1
fi

# Test 8: Verify environment variable priority
echo ""
echo "Test 8: Verifying environment variable takes priority..."
if grep -q "Using CAMARA_BASIC_AUTH from environment" "$REPO_ROOT/enterprise-private-cloud/test_onprem.sh"; then
    echo "✓ PASS: Environment variable priority is handled"
else
    echo "✗ FAIL: Environment variable priority not handled"
    exit 1
fi

# Test 9: Verify bypass mode still works
echo ""
echo "Test 9: Verifying bypass mode is still supported..."
if grep -q "CAMARA_BYPASS.*true" "$REPO_ROOT/enterprise-private-cloud/test_onprem.sh"; then
    echo "✓ PASS: Bypass mode is still supported"
else
    echo "✗ FAIL: Bypass mode may not be working"
    exit 1
fi

echo ""
echo "=========================================="
echo "All tests passed! ✓"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - Hardcoded credentials removed from both scripts"
echo "  - File reading logic implemented"
echo "  - Multiple file locations checked"
echo "  - Error handling in place"
echo "  - Environment variable priority maintained"
echo "  - Bypass mode still supported"
echo ""

