#!/bin/bash
# Simple SPIRE build script - bypasses Makefile issues

set -e

echo "=== Building SPIRE Agent and Server ==="

cd ~/dhanush/hybrid-cloud-poc-backup/spire

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "❌ Go is not installed"
    echo "Install with: sudo apt update && sudo apt install golang-go"
    exit 1
fi

echo "✓ Go version: $(go version)"

# Create bin directory
mkdir -p bin

echo ""
echo "Building SPIRE Agent..."
go build -o bin/spire-agent ./cmd/spire-agent
if [ $? -eq 0 ]; then
    echo "✓ SPIRE Agent built successfully"
    ls -lh bin/spire-agent
else
    echo "❌ SPIRE Agent build failed"
    exit 1
fi

echo ""
echo "Building SPIRE Server..."
go build -o bin/spire-server ./cmd/spire-server
if [ $? -eq 0 ]; then
    echo "✓ SPIRE Server built successfully"
    ls -lh bin/spire-server
else
    echo "❌ SPIRE Server build failed"
    exit 1
fi

echo ""
echo "=== Build Complete ==="
echo ""
echo "Binaries created:"
ls -lh bin/spire-agent bin/spire-server

echo ""
echo "Test with:"
echo "  ./bin/spire-agent --version"
echo "  ./bin/spire-server --version"
