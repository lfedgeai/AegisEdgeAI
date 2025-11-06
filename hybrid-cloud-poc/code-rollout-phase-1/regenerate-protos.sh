#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Script to regenerate protobuf files after modifying .proto files

set -e

echo "Unified-Identity - Phase 1: Regenerating protobuf files..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Regenerate go-spiffe protobuf files
echo "Regenerating go-spiffe protobuf files..."
cd "$SCRIPT_DIR/go-spiffe"
if [ -f "Makefile" ]; then
    make generate
    echo "✓ go-spiffe protobuf files regenerated"
else
    echo "⚠ Makefile not found in go-spiffe, skipping..."
fi

# Regenerate spire-api-sdk protobuf files
echo "Regenerating spire-api-sdk protobuf files..."
cd "$SCRIPT_DIR/spire-api-sdk"
if [ -f "Makefile" ]; then
    make generate
    echo "✓ spire-api-sdk protobuf files regenerated"
else
    echo "⚠ Makefile not found in spire-api-sdk, skipping..."
fi

# Regenerate spire protobuf files
echo "Regenerating spire protobuf files..."
cd "$SCRIPT_DIR/spire"
if [ -f "Makefile" ]; then
    make generate
    echo "✓ spire protobuf files regenerated"
else
    echo "⚠ Makefile not found in spire, skipping..."
fi

echo ""
echo "Unified-Identity - Phase 1: Protobuf regeneration complete!"
echo ""
echo "Next steps:"
echo "1. Review any compilation errors"
echo "2. Run tests: cd spire && go test ./..."
echo "3. Verify feature flag behavior with tests"

