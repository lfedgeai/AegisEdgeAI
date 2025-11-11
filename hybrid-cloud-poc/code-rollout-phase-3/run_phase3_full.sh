#!/bin/bash
# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
# Wrapper script to perform the full Cleanup → Start → Test → Generate SVID flow
# Mirrors the behaviour of test_phase3_complete.sh with a single entry point.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
TEST_SCRIPT="${PROJECT_ROOT}/test_phase3_complete.sh"

if [ ! -x "${TEST_SCRIPT}" ]; then
    echo "Unified-Identity - Phase 3: test_phase3_complete.sh not found or not executable" >&2
    exit 1
fi

# Ensure feature flag is enabled for the run (can be overridden by caller)
export UNIFIED_IDENTITY_ENABLED="${UNIFIED_IDENTITY_ENABLED:-true}"

SHOW_HELP=false
USER_SKIP_CLEAN=false
USER_CLEAN_ONLY=false

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            SHOW_HELP=true
            ;;
        --skip-cleanup)
            USER_SKIP_CLEAN=true
            ;;
        --cleanup-only)
            USER_CLEAN_ONLY=true
            ;;
    esac
done

if [ "$SHOW_HELP" = true ]; then
    "${TEST_SCRIPT}" --help
    exit 0
fi

if [ "$USER_CLEAN_ONLY" = true ]; then
    echo "[Phase 0] Running cleanup only..."
    exec "${TEST_SCRIPT}" --cleanup-only
fi

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Unified-Identity - Phase 3: Full End-to-End Execution        ║"
echo "║  (Cleanup → Start → Test → Generate Sovereign SVID)            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ "$USER_SKIP_CLEAN" = true ]; then
    echo "[Phase 0] Skipping automatic cleanup (requested)."
else
    echo "[Phase 0] Ensuring clean start..."
    "${TEST_SCRIPT}" --cleanup-only >/dev/null 2>&1 || true
fi

echo "[Phase 1] Executing complete Phase 3 workflow..."
"${TEST_SCRIPT}" "$@"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Unified-Identity - Phase 3: Full workflow completed           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
