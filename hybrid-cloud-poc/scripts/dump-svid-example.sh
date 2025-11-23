#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Example script showing how to use dump-svid to highlight Phase 1 additions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Unified-Identity - Phase 1: SVID Dump Example"
echo ""

# Check if dump-svid exists
if [ ! -f "./dump-svid" ]; then
    echo "Building dump-svid..."
    go build -o dump-svid dump-svid.go
fi

# Example 1: Dump SVID with color highlighting
echo "Example 1: Pretty format with color highlighting (default)"
echo "─────────────────────────────────────────────────────────"
if [ -f "svid.crt" ]; then
    if [ -f "svid_attested_claims.json" ]; then
        ./dump-svid -cert svid.crt -attested svid_attested_claims.json
    else
        ./dump-svid -cert svid.crt
    fi
else
    echo "⚠ svid.crt not found. Generate one first using:"
    echo "  ./generate-sovereign-svid -entryID <ENTRY_ID>"
fi

echo ""
echo "─────────────────────────────────────────────────────────"
echo ""

# Example 2: JSON format
echo "Example 2: JSON format"
echo "─────────────────────────────────────────────────────────"
if [ -f "svid.crt" ]; then
    if [ -f "svid_attested_claims.json" ]; then
        ./dump-svid -cert svid.crt -attested svid_attested_claims.json -format json | jq .
    else
        ./dump-svid -cert svid.crt -format json | jq .
    fi
else
    echo "⚠ svid.crt not found"
fi

echo ""
echo "─────────────────────────────────────────────────────────"
echo ""

# Example 3: Detailed format
echo "Example 3: Detailed format"
echo "─────────────────────────────────────────────────────────"
if [ -f "svid.crt" ]; then
    if [ -f "svid_attested_claims.json" ]; then
        ./dump-svid -cert svid.crt -attested svid_attested_claims.json -format detailed
    else
        ./dump-svid -cert svid.crt -format detailed
    fi
else
    echo "⚠ svid.crt not found"
fi

echo ""
echo "Usage:"
echo "  ./dump-svid -cert <certificate> [-attested <claims.json>] [-format pretty|json|detailed] [-color true|false]"

