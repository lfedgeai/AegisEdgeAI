#!/bin/bash
# Rebuild SPIRE Agent with Option 5 fix (include quote in SovereignAttestation)
# This script rebuilds the SPIRE Agent binary with the new code that fetches
# the quote from rust-keylime agent and includes it in the SovereignAttestation payload

set -e

echo "============================================================"
echo "Rebuilding SPIRE Agent with Option 5 Fix"
echo "============================================================"
echo ""

# Get project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${PROJECT_DIR}"

echo "Step 1: Verify source code has new changes..."
if ! grep -q "RequestQuoteFromAgent" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go; then
    echo "❌ ERROR: Source code doesn't have RequestQuoteFromAgent function!"
    echo "   The file spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go is missing the new code."
    echo ""
    echo "   Copying from .UPDATED file..."
    cp spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go.UPDATED \
       spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go
    echo "   ✅ Source code updated"
fi

echo "✅ Source code has RequestQuoteFromAgent function"
echo ""

echo "Step 2: Verify go.mod has correct Go version..."
GO_VERSION=$(grep "^go " spire/go.mod | awk '{print $2}')
echo "   Current go.mod version: $GO_VERSION"

if [[ "$GO_VERSION" == "1.25.3" ]]; then
    echo "   ⚠ Invalid Go version 1.25.3, fixing to 1.21..."
    sed -i 's/^go 1.25.3/go 1.21/' spire/go.mod
    echo "   ✅ Fixed go.mod version to 1.21"
fi

echo "✅ go.mod has valid Go version"
echo ""

echo "Step 3: Check Go installation..."
if ! command -v go &> /dev/null; then
    echo "❌ ERROR: Go is not installed or not in PATH"
    echo "   Please install Go 1.21 or later"
    exit 1
fi

GO_INSTALLED_VERSION=$(go version | awk '{print $3}')
echo "✅ Go is installed: $GO_INSTALLED_VERSION"
echo ""

echo "Step 4: Remove old binary..."
if [ -f spire/bin/spire-agent ]; then
    OLD_SIZE=$(ls -lh spire/bin/spire-agent | awk '{print $5}')
    OLD_DATE=$(ls -lh spire/bin/spire-agent | awk '{print $6, $7, $8}')
    echo "   Old binary: $OLD_SIZE, $OLD_DATE"
    rm -f spire/bin/spire-agent
    echo "   ✅ Removed old binary"
else
    echo "   No old binary found"
fi
echo ""

echo "Step 5: Build SPIRE Agent..."
cd spire
mkdir -p bin

echo "   Running: go build -o bin/spire-agent ./cmd/spire-agent"
if go build -o bin/spire-agent ./cmd/spire-agent; then
    echo "   ✅ Build succeeded"
else
    echo "   ❌ Build failed"
    exit 1
fi

cd ..
echo ""

echo "Step 6: Verify new binary..."
if [ ! -f spire/bin/spire-agent ]; then
    echo "❌ ERROR: Binary not created!"
    exit 1
fi

NEW_SIZE=$(ls -lh spire/bin/spire-agent | awk '{print $5}')
NEW_DATE=$(ls -lh spire/bin/spire-agent | awk '{print $6, $7, $8}')
echo "   New binary: $NEW_SIZE, $NEW_DATE"

# Verify new code is in binary
if strings spire/bin/spire-agent | grep -q "Requesting quote from rust-keylime agent"; then
    echo "   ✅ New code is in binary (verified with strings)"
else
    echo "   ❌ WARNING: New code not found in binary!"
    echo "      This might be a problem. Check the build output."
fi
echo ""

echo "Step 7: Test binary..."
if spire/bin/spire-agent --version &> /dev/null; then
    VERSION=$(spire/bin/spire-agent --version 2>&1)
    echo "   ✅ Binary is executable: $VERSION"
else
    echo "   ❌ WARNING: Binary might not be executable"
fi
echo ""

echo "============================================================"
echo "✅ SPIRE Agent Rebuild Complete!"
echo "============================================================"
echo ""
echo "Binary location: ${PROJECT_DIR}/spire/bin/spire-agent"
echo "Binary size: $NEW_SIZE"
echo "Binary date: $NEW_DATE"
echo ""
echo "Next steps:"
echo "  1. Stop any running SPIRE Agent:"
echo "     pkill spire-agent"
echo ""
echo "  2. Run the full test:"
echo "     ./test_complete_control_plane.sh --no-pause"
echo "     ./test_complete.sh --no-pause"
echo ""
echo "  3. Check SPIRE Agent logs for new messages:"
echo "     tail -f /tmp/spire-agent.log | grep 'Requesting quote'"
echo ""
echo "     You should see:"
echo "     'Unified-Identity - Verification: Requesting quote from rust-keylime agent'"
echo ""
echo "  4. Check Verifier logs to confirm it's NOT fetching quote:"
echo "     tail -f /tmp/keylime-verifier.log | grep 'quote'"
echo ""
echo "     You should NOT see:"
echo "     'Requesting quote from agent'"
echo ""
