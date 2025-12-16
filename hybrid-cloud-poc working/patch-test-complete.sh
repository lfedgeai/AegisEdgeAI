#!/bin/bash
# Patch test_complete.sh to disable tpm2-abrmd startup
# This fixes the TPM resource conflict

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_FILE="${SCRIPT_DIR}/test_complete.sh"

echo "Patching test_complete.sh to disable tpm2-abrmd..."

# Backup first
if [ ! -f "${TARGET_FILE}.backup" ]; then
    cp "$TARGET_FILE" "${TARGET_FILE}.backup"
    echo "✓ Backup created: ${TARGET_FILE}.backup"
fi

# Comment out the entire tpm2-abrmd startup section (lines 1405-1423)
# We'll use sed to add a comment marker at the beginning of each line in that range

sed -i '1405,1423 s/^/# DISABLED_TPM_CONFLICT: /' "$TARGET_FILE"

echo "✓ Disabled tpm2-abrmd startup section (lines 1405-1423)"

# Verify the change
echo ""
echo "Verification - these lines should now be commented:"
sed -n '1405,1415p' "$TARGET_FILE" | head -5

echo ""
echo "✓ Patch complete!"
echo ""
echo "To restore original: cp ${TARGET_FILE}.backup ${TARGET_FILE}"
