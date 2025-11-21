#!/bin/bash
# Debug script for mobile sensor microservice

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DB="/tmp/test-mobile-sensor-debug.db"
TEST_LOG="/tmp/test-mobile-sensor-debug.log"
TEST_PORT=9052

echo "=== Mobile Sensor Microservice Debug Test ==="
echo ""

# Clean up
pkill -f "service.py.*${TEST_PORT}" 2>/dev/null || true
rm -f "${TEST_DB}" 2>/dev/null || true
sleep 1

# Test 1: With CAMARA_BYPASS=true (should always work)
echo "Test 1: CAMARA_BYPASS=true (should return true)"
export MOBILE_SENSOR_DB="${TEST_DB}"
export CAMARA_BYPASS=true
cd "${SCRIPT_DIR}"
python3 service.py --host 127.0.0.1 --port "${TEST_PORT}" > "${TEST_LOG}" 2>&1 &
SERVICE_PID=$!
sleep 3

echo "  Making request..."
RESPONSE=$(curl -s -X POST http://127.0.0.1:${TEST_PORT}/verify \
    -H "Content-Type: application/json" \
    -d '{"sensor_id": "12d1:1433"}')

echo "  Response: ${RESPONSE}"
VERIFICATION_RESULT=$(echo "${RESPONSE}" | grep -o '"verification_result":[^,}]*' | cut -d':' -f2 | tr -d ' "')
echo "  Verification result: ${VERIFICATION_RESULT}"

if [ "${VERIFICATION_RESULT}" = "true" ]; then
    echo "  ✓ Test 1 PASSED"
else
    echo "  ✗ Test 1 FAILED"
fi

kill "${SERVICE_PID}" 2>/dev/null || true
sleep 2

# Test 2: With CAMARA_BYPASS=false (should call CAMARA APIs)
echo ""
echo "Test 2: CAMARA_BYPASS=false (should call CAMARA APIs)"
rm -f "${TEST_DB}"
export MOBILE_SENSOR_DB="${TEST_DB}"
export CAMARA_BYPASS=false
# Use the credentials from the user's manual test
export CAMARA_BASIC_AUTH="${CAMARA_BASIC_AUTH:-Basic NDcyOWY5ZDItMmVmNy00NTdhLWJlMzMtMGVkZjg4ZDkwZjA0OmU5N2M0Mzg0LTI4MDYtNDQ5YS1hYzc1LWUyZDJkNzNlOWQ0Ng==}"

python3 service.py --host 127.0.0.1 --port "${TEST_PORT}" > "${TEST_LOG}" 2>&1 &
SERVICE_PID=$!
sleep 3

echo "  Making request..."
RESPONSE=$(curl -s -X POST http://127.0.0.1:${TEST_PORT}/verify \
    -H "Content-Type: application/json" \
    -d '{"sensor_id": "12d1:1433"}')

echo "  Response: ${RESPONSE}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST http://127.0.0.1:${TEST_PORT}/verify \
    -H "Content-Type: application/json" \
    -d '{"sensor_id": "12d1:1433"}')
echo "  HTTP Code: ${HTTP_CODE}"

if echo "${RESPONSE}" | grep -q '"verification_result":true'; then
    echo "  ✓ Test 2 PASSED (CAMARA APIs returned true)"
elif echo "${RESPONSE}" | grep -q '"error"'; then
    echo "  ⚠ Test 2: CAMARA APIs returned error (check logs)"
    echo "  Recent logs:"
    tail -20 "${TEST_LOG}" | grep -E "(CAMARA|Step|error|ERROR)" | sed 's/^/    /'
else
    echo "  ✗ Test 2: Unexpected response"
fi

kill "${SERVICE_PID}" 2>/dev/null || true
sleep 2

echo ""
echo "=== Full service logs ==="
tail -50 "${TEST_LOG}" | sed 's/^/  /'

echo ""
echo "=== Test Summary ==="
echo "Test DB: ${TEST_DB}"
echo "Test Log: ${TEST_LOG}"
echo "Service was running on port: ${TEST_PORT}"

