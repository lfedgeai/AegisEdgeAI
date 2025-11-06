#!/bin/bash
# Unified-Identity - Phase 1: Complete demo script
# Sets up SPIRE, creates registration entry, fetches SVID, and dumps it

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Unified-Identity - Phase 1: Python App Demo                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Setup SPIRE
echo "Step 1: Setting up SPIRE and Keylime Stub..."
"${SCRIPT_DIR}/setup-spire.sh"
echo ""

# Step 2: Create registration entry
echo "Step 2: Creating registration entry..."
"${SCRIPT_DIR}/create-registration-entry.sh"
echo ""

# Step 3: Fetch sovereign SVID
echo "Step 3: Fetching Sovereign SVID with AttestedClaims..."
python3 "${SCRIPT_DIR}/fetch-sovereign-svid.py"
echo ""

# Step 4: Dump SVID
echo "Step 4: Dumping SVID with AttestedClaims..."
if [ -f /tmp/svid-dump/attested_claims.json ]; then
    "${SCRIPT_DIR}/../scripts/dump-svid" \
        -cert /tmp/svid-dump/svid.pem \
        -attested /tmp/svid-dump/attested_claims.json
else
    "${SCRIPT_DIR}/../scripts/dump-svid" \
        -cert /tmp/svid-dump/svid.pem
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Demo Complete!                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Files saved to: /tmp/svid-dump/"
echo "  - svid.pem (SVID certificate)"
echo "  - attested_claims.json (AttestedClaims, if available)"
echo ""

