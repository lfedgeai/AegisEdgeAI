#!/bin/bash
# Unified-Identity - Phase 1: Cleanup script for Python app demo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Unified-Identity - Phase 1: Cleaning up Python App Demo"
echo ""

QUIET=${QUIET:-0}

"${PROJECT_ROOT}/scripts/stop-unified-identity.sh"

if [ "$QUIET" -eq 0 ]; then
    echo "Removing SVID output files..."
fi
rm -rf /tmp/svid-dump /tmp/svid.pem /tmp/svid.key /tmp/svid_attested_claims.json 2>/dev/null || true

if [ "$QUIET" -eq 0 ]; then
    echo ""
    echo "✓ Cleanup complete"
fi


