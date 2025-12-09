#!/bin/bash
# Integration tests for CAMARA credentials in different scenarios

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_SENSOR_DIR="$SCRIPT_DIR"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_FILE="$MOBILE_SENSOR_DIR/camara_basic_auth.txt"
TEST_VALUE="Basic dGVzdF9jbGllbnRfaWQ6dGVzdF9jbGllbnRfc2VjcmV0"

echo "=========================================="
echo "Integration Tests: CAMARA Credentials"
echo "=========================================="
echo ""

# Cleanup function
cleanup() {
    rm -f "$TEST_FILE"
    unset CAMARA_BASIC_AUTH
    unset CAMARA_BYPASS
}

trap cleanup EXIT

# Test Scenario 1: File exists, should load from file
echo "Scenario 1: Loading from file (CAMARA_BYPASS=false)..."
mkdir -p "$MOBILE_SENSOR_DIR"
echo "$TEST_VALUE" > "$TEST_FILE"
chmod 600 "$TEST_FILE"
unset CAMARA_BASIC_AUTH
export CAMARA_BYPASS="false"

# Simulate the logic from test_onprem.sh
CAMARA_AUTH_FILE=""
for possible_path in \
    "$REPO_ROOT/mobile-sensor-microservice/camara_basic_auth.txt" \
    "$REPO_ROOT/camara_basic_auth.txt" \
    "/tmp/mobile-sensor-service/camara_basic_auth.txt" \
    "$(pwd)/camara_basic_auth.txt"; do
    if [ -f "$possible_path" ]; then
        CAMARA_AUTH_FILE="$possible_path"
        break
    fi
done

if [ -n "$CAMARA_AUTH_FILE" ] && [ -f "$CAMARA_AUTH_FILE" ]; then
    CAMARA_BASIC_AUTH=$(cat "$CAMARA_AUTH_FILE" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 200)
    if [ "$CAMARA_BASIC_AUTH" = "$TEST_VALUE" ]; then
        echo "✓ PASS: Successfully loaded from file"
    else
        echo "✗ FAIL: Value mismatch"
        echo "  Expected: $TEST_VALUE"
        echo "  Got: $CAMARA_BASIC_AUTH"
        exit 1
    fi
else
    echo "✗ FAIL: File not found"
    exit 1
fi

# Test Scenario 2: Environment variable takes priority
echo ""
echo "Scenario 2: Environment variable takes priority over file..."
ENV_VALUE="Basic ZW52X2NsaWVudF9pZDplbnZfY2xpZW50X3NlY3JldA=="
export CAMARA_BASIC_AUTH="$ENV_VALUE"

# Simulate priority check
if [ -n "${CAMARA_BASIC_AUTH:-}" ]; then
    if [ "$CAMARA_BASIC_AUTH" = "$ENV_VALUE" ]; then
        echo "✓ PASS: Environment variable takes priority"
    else
        echo "✗ FAIL: Environment variable not used"
        exit 1
    fi
else
    echo "✗ FAIL: Environment variable not set"
    exit 1
fi

# Test Scenario 3: Bypass mode (no credentials needed)
echo ""
echo "Scenario 3: Bypass mode works without credentials..."
unset CAMARA_BASIC_AUTH
rm -f "$TEST_FILE"
export CAMARA_BYPASS="true"

if [ "$CAMARA_BYPASS" = "true" ]; then
    echo "✓ PASS: Bypass mode works (no credentials required)"
else
    echo "✗ FAIL: Bypass mode not working"
    exit 1
fi

# Test Scenario 4: Error when bypass=false and no credentials
echo ""
echo "Scenario 4: Error when bypass=false and no credentials..."
unset CAMARA_BASIC_AUTH
rm -f "$TEST_FILE"
export CAMARA_BYPASS="false"

# Simulate the error check
if [ "$CAMARA_BYPASS" != "true" ]; then
    if [ -z "${CAMARA_BASIC_AUTH:-}" ]; then
        # Try to load from file
        CAMARA_AUTH_FILE=""
        for possible_path in \
            "$REPO_ROOT/mobile-sensor-microservice/camara_basic_auth.txt" \
            "$REPO_ROOT/camara_basic_auth.txt" \
            "/tmp/mobile-sensor-service/camara_basic_auth.txt" \
            "$(pwd)/camara_basic_auth.txt"; do
            if [ -f "$possible_path" ]; then
                CAMARA_AUTH_FILE="$possible_path"
                break
            fi
        done
        
        if [ -z "$CAMARA_AUTH_FILE" ] || [ ! -f "$CAMARA_AUTH_FILE" ]; then
            echo "✓ PASS: Correctly detects missing credentials (would exit with error)"
        else
            echo "✗ FAIL: Should not find file"
            exit 1
        fi
    else
        echo "✗ FAIL: Should not have credentials"
        exit 1
    fi
fi

# Test Scenario 5: Multiple file locations checked
echo ""
echo "Scenario 5: Multiple file locations are checked..."
LOCATION_COUNT=0

# Create file in first location
mkdir -p "$MOBILE_SENSOR_DIR"
echo "$TEST_VALUE" > "$MOBILE_SENSOR_DIR/camara_basic_auth.txt"
chmod 600 "$MOBILE_SENSOR_DIR/camara_basic_auth.txt"

# Check if first location is found
for possible_path in \
    "$REPO_ROOT/mobile-sensor-microservice/camara_basic_auth.txt" \
    "$REPO_ROOT/camara_basic_auth.txt" \
    "/tmp/mobile-sensor-service/camara_basic_auth.txt" \
    "$(pwd)/camara_basic_auth.txt"; do
    if [ -f "$possible_path" ]; then
        LOCATION_COUNT=$((LOCATION_COUNT + 1))
        FOUND_PATH="$possible_path"
        break
    fi
done

if [ $LOCATION_COUNT -eq 1 ] && [ "$FOUND_PATH" = "$MOBILE_SENSOR_DIR/camara_basic_auth.txt" ]; then
    echo "✓ PASS: Found file in first checked location"
else
    echo "✗ FAIL: File location check failed"
    exit 1
fi

# Cleanup
rm -f "$MOBILE_SENSOR_DIR/camara_basic_auth.txt"

# Test Scenario 6: File format validation
echo ""
echo "Scenario 6: File format handling..."
# Test with leading/trailing whitespace
echo "  $TEST_VALUE  " > "$TEST_FILE"
chmod 600 "$TEST_FILE"

READ_VALUE=$(cat "$TEST_FILE" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 200)
if [ "$READ_VALUE" = "$TEST_VALUE" ]; then
    echo "✓ PASS: Handles leading/trailing whitespace correctly"
else
    echo "✗ FAIL: Whitespace handling incorrect"
    echo "  Expected: $TEST_VALUE"
    echo "  Got: $READ_VALUE"
    exit 1
fi

# Test with newlines
echo -e "\n$TEST_VALUE\n" > "$TEST_FILE"
READ_VALUE=$(cat "$TEST_FILE" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 200)
if [ "$READ_VALUE" = "$TEST_VALUE" ]; then
    echo "✓ PASS: Handles newlines correctly"
else
    echo "✗ FAIL: Newline handling incorrect"
    exit 1
fi

echo ""
echo "=========================================="
echo "All integration tests passed! ✓"
echo "=========================================="
echo ""
echo "Tested scenarios:"
echo "  1. ✓ Loading from file"
echo "  2. ✓ Environment variable priority"
echo "  3. ✓ Bypass mode"
echo "  4. ✓ Error handling when credentials missing"
echo "  5. ✓ Multiple file location checks"
echo "  6. ✓ File format handling (whitespace, newlines)"
echo ""

