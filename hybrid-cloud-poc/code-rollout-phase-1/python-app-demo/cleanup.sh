#!/bin/bash
# Unified-Identity - Phase 1: Cleanup script for Python app demo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Unified-Identity - Phase 1: Cleaning up Python App Demo"
echo ""

# Force QUIET=0 to ensure cleanup output is visible
export QUIET=0

"${PROJECT_ROOT}/scripts/stop-unified-identity.sh"

echo "Removing SVID output files..."
rm -rf /tmp/svid-dump /tmp/svid.pem /tmp/svid.key /tmp/svid_attested_claims.json 2>/dev/null || true

echo ""
echo "✓ Cleanup complete"


