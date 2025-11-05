#!/bin/bash
# Simple integration test for sovereign attestation
# Tests that binaries build correctly with Unified-Identity feature

set -e

echo "=== Integration Test: Binary Build Verification ==="
echo ""

cd "$(dirname "$0")/spire"

echo "1. Building SPIRE Server..."
go build -o /tmp/spire-server-test ./cmd/spire-server
if [ $? -eq 0 ]; then
    echo "   ✅ SPIRE Server built successfully"
else
    echo "   ❌ SPIRE Server build failed"
    exit 1
fi

echo ""
echo "2. Building SPIRE Agent..."
go build -o /tmp/spire-agent-test ./cmd/spire-agent
if [ $? -eq 0 ]; then
    echo "   ✅ SPIRE Agent built successfully"
else
    echo "   ❌ SPIRE Agent build failed"
    exit 1
fi

echo ""
echo "3. Verifying binaries exist and are executable..."
if [ -f /tmp/spire-server-test ] && [ -x /tmp/spire-server-test ]; then
    echo "   ✅ SPIRE Server binary exists and is executable"
else
    echo "   ❌ SPIRE Server binary missing or not executable"
    exit 1
fi

if [ -f /tmp/spire-agent-test ] && [ -x /tmp/spire-agent-test ]; then
    echo "   ✅ SPIRE Agent binary exists and is executable"
else
    echo "   ❌ SPIRE Agent binary missing or not executable"
    exit 1
fi

echo ""
echo "4. Testing binary versions..."
SERVER_VERSION=$(/tmp/spire-server-test --version 2>&1 | head -1)
AGENT_VERSION=$(/tmp/spire-agent-test --version 2>&1 | head -1)
echo "   Server: $SERVER_VERSION"
echo "   Agent: $AGENT_VERSION"

echo ""
echo "=========================================="
echo "✅ Integration Test: PASSED"
echo "=========================================="
echo ""
echo "Note: Full end-to-end testing requires:"
echo "  - Running SPIRE Server with feature flag in config"
echo "  - Running SPIRE Agent with feature flag in config"
echo "  - Sending workload requests with sovereign attestation"
