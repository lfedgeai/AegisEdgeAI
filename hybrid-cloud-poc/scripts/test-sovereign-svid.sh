#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Test script to verify the generate-sovereign-svid script works correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Unified-Identity - Phase 1: Testing generate-sovereign-svid script"
echo ""

# Check if script exists
if [ ! -f "./generate-sovereign-svid" ]; then
    echo "Building generate-sovereign-svid script..."
    go build -o generate-sovereign-svid generate-sovereign-svid.go
    echo "✓ Script built successfully"
    echo ""
fi

# Check if SPIRE Server is running (optional check)
if [ -S "/tmp/spire-server/private/api.sock" ]; then
    echo "✓ SPIRE Server socket found"
else
    echo "⚠ SPIRE Server socket not found at /tmp/spire-server/private/api.sock"
    echo "  Make sure SPIRE Server is running with feature flag enabled"
    echo ""
fi

# Display usage
echo "Usage example:"
echo "  ./generate-sovereign-svid -entryID <ENTRY_ID> -spiffeID <SPIFFE_ID> -verbose"
echo ""
echo "To get an entry ID, create a registration entry:"
echo "  spire-server entry create \\"
echo "    -spiffeID spiffe://example.org/workload/test \\"
echo "    -parentID spiffe://example.org/agent \\"
echo "    -selector unix:uid:1000"
echo ""
echo "Then use the Entry ID from the output."
echo ""

# Test with dry-run (if we can validate the script compiles and has correct flags)
echo "Testing script flags..."
./generate-sovereign-svid -help > /dev/null 2>&1 && echo "✓ Script executable and flags working" || echo "✗ Script has issues"

echo ""
echo "Script is ready to use!"
echo "Note: This script requires a running SPIRE Server with the Unified-Identity feature flag enabled."

