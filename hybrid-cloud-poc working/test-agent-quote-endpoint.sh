#!/bin/bash
# Test rust-keylime agent quote endpoint directly
# This helps diagnose why Keylime Verifier cannot fetch quotes

set -euo pipefail

AGENT_IP="${1:-127.0.0.1}"
AGENT_PORT="${2:-9002}"
NONCE="${3:-test-nonce-12345}"

echo "Testing rust-keylime agent quote endpoint..."
echo "Agent: ${AGENT_IP}:${AGENT_PORT}"
echo "Nonce: ${NONCE}"
echo ""

# Test 1: Check if agent is listening
echo "[1] Checking if agent is listening on port ${AGENT_PORT}..."
if netstat -tln 2>/dev/null | grep -q ":${AGENT_PORT} "; then
    echo "✓ Agent is listening on port ${AGENT_PORT}"
else
    echo "✗ Agent is NOT listening on port ${AGENT_PORT}"
    echo "  Run: netstat -tln | grep ${AGENT_PORT}"
    exit 1
fi
echo ""

# Test 2: Try HTTP connection (no mTLS)
echo "[2] Testing HTTP connection (no mTLS)..."
HTTP_URL="http://${AGENT_IP}:${AGENT_PORT}/v2.4/quotes/identity?nonce=${NONCE}"
echo "URL: ${HTTP_URL}"
if curl -v -X GET "${HTTP_URL}" 2>&1 | head -20; then
    echo "✓ HTTP connection successful"
else
    echo "✗ HTTP connection failed"
fi
echo ""

# Test 3: Try HTTPS connection (with mTLS)
echo "[3] Testing HTTPS connection (with mTLS)..."
HTTPS_URL="https://${AGENT_IP}:${AGENT_PORT}/v2.4/quotes/identity?nonce=${NONCE}"
echo "URL: ${HTTPS_URL}"

# Check if certificates exist
KEYLIME_DIR="/tmp/keylime-agent"
if [ ! -f "${KEYLIME_DIR}/cv_ca/cacert.crt" ]; then
    echo "✗ CA certificate not found: ${KEYLIME_DIR}/cv_ca/cacert.crt"
    echo "  Agent may not have mTLS enabled"
else
    echo "Found CA certificate: ${KEYLIME_DIR}/cv_ca/cacert.crt"
    
    # Try with CA cert
    if curl -v --cacert "${KEYLIME_DIR}/cv_ca/cacert.crt" \
         -X GET "${HTTPS_URL}" 2>&1 | head -20; then
        echo "✓ HTTPS connection successful (with CA cert)"
    else
        echo "✗ HTTPS connection failed (with CA cert)"
    fi
fi
echo ""

# Test 4: Check agent configuration
echo "[4] Checking agent configuration..."
AGENT_CONF="rust-keylime/keylime-agent.conf"
if [ -f "${AGENT_CONF}" ]; then
    echo "Agent mTLS enabled:"
    grep "enable_agent_mtls" "${AGENT_CONF}" || echo "  (not found)"
    echo "Agent IP/Port:"
    grep -E "^ip =|^port =" "${AGENT_CONF}" || echo "  (not found)"
else
    echo "✗ Agent config not found: ${AGENT_CONF}"
fi
echo ""

# Test 5: Check verifier configuration
echo "[5] Checking verifier configuration..."
VERIFIER_CONF="keylime/verifier.conf.minimal"
if [ -f "${VERIFIER_CONF}" ]; then
    echo "Verifier agent mTLS enabled:"
    grep "enable_agent_mtls" "${VERIFIER_CONF}" || echo "  (not found)"
    echo "Agent quote timeout:"
    grep "agent_quote_timeout" "${VERIFIER_CONF}" || echo "  (using default: 30s)"
else
    echo "✗ Verifier config not found: ${VERIFIER_CONF}"
fi
echo ""

# Test 6: Check recent agent logs for quote requests
echo "[6] Checking recent agent logs for quote requests..."
if [ -f "/tmp/rust-keylime-agent.log" ]; then
    echo "Recent quote-related log entries:"
    grep -E "quote|GET.*quotes" /tmp/rust-keylime-agent.log | tail -10 || echo "  (no quote requests found)"
else
    echo "✗ Agent log not found: /tmp/rust-keylime-agent.log"
fi
echo ""

# Test 7: Check recent verifier logs for connection errors
echo "[7] Checking recent verifier logs for connection errors..."
if [ -f "/tmp/keylime-verifier.log" ]; then
    echo "Recent connection error log entries:"
    grep -E "599|timeout|connection.*failed|agent retrieval failed" /tmp/keylime-verifier.log | tail -10 || echo "  (no connection errors found)"
else
    echo "✗ Verifier log not found: /tmp/keylime-verifier.log"
fi
echo ""

echo "Diagnostic complete."
echo ""
echo "Next steps:"
echo "1. If HTTP works but HTTPS fails: Check mTLS certificate configuration"
echo "2. If both fail: Check if agent is running and listening on correct port"
echo "3. If connection times out: Increase agent_quote_timeout in verifier config"
echo "4. Check logs for detailed error messages"
