#!/bin/bash
# Quick test script for Phase 1 Unified Identity implementation

set -e

echo "=== Phase 1 Unified Identity - Test Script ==="
echo ""

cd "$(dirname "$0")/spire"

echo "1. Building SPIRE Server..."
go build ./cmd/spire-server
echo "   ✅ Server built successfully"
echo ""

echo "2. Building SPIRE Agent..."
go build ./cmd/spire-agent
echo "   ✅ Agent built successfully"
echo ""

echo "3. Running Keylime client tests..."
go test ./pkg/server/sovereign/keylime/... -v
echo ""

echo "4. Running Policy evaluation tests..."
go test ./pkg/server/sovereign/policy_test.go -v
echo ""

echo "5. Running Agent sovereign tests..."
go test ./pkg/agent/endpoints/workload/... -run Sovereign -v
echo ""

echo "✅ All tests passed!"
