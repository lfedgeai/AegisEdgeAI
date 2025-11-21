#!/bin/bash
# Test script to verify Keylime Verifier can call mobile sensor microservice

set -e

TEST_PORT=9053
TEST_DB="/tmp/test-verifier-microservice.db"
TEST_LOG="/tmp/test-verifier-microservice.log"

echo "=== Testing Keylime Verifier → Mobile Sensor Microservice ==="
echo ""

# Clean up
pkill -f "service.py.*${TEST_PORT}" 2>/dev/null || true
rm -f "${TEST_DB}" 2>/dev/null || true
sleep 1

# Start microservice
echo "1. Starting mobile sensor microservice on port ${TEST_PORT}..."
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-3/mobile-sensor-microservice
export MOBILE_SENSOR_DB="${TEST_DB}"
export CAMARA_BYPASS=true
python3 service.py --host 127.0.0.1 --port "${TEST_PORT}" > "${TEST_LOG}" 2>&1 &
SERVICE_PID=$!
sleep 3

# Verify service is running
if ! curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:${TEST_PORT}/verify > /dev/null 2>&1; then
    echo "  ✗ Service failed to start"
    cat "${TEST_LOG}"
    exit 1
fi
echo "  ✓ Service is running (PID: ${SERVICE_PID})"
echo ""

# Test 1: Simulate what verifier sends
echo "2. Testing with verifier-style request..."
VERIFIER_PAYLOAD='{"sensor_id": "12d1:1433"}'
echo "  Payload: ${VERIFIER_PAYLOAD}"

RESPONSE=$(curl -s -X POST "http://127.0.0.1:${TEST_PORT}/verify" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "${VERIFIER_PAYLOAD}")

echo "  Response: ${RESPONSE}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://127.0.0.1:${TEST_PORT}/verify" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "${VERIFIER_PAYLOAD}")

echo "  HTTP Code: ${HTTP_CODE}"

if echo "${RESPONSE}" | grep -q '"verification_result":true'; then
    echo "  ✓ Test PASSED"
else
    echo "  ✗ Test FAILED"
    echo "  Service logs:"
    tail -20 "${TEST_LOG}" | sed 's/^/    /'
fi
echo ""

# Test 2: Check what the service received
echo "3. Checking service logs for received request..."
echo "  Recent service logs:"
tail -30 "${TEST_LOG}" | grep -E "(Received|Parsed|sensor_id|error|ERROR)" | sed 's/^/    /'
echo ""

# Cleanup
kill "${SERVICE_PID}" 2>/dev/null || true
echo "=== Test Complete ==="

