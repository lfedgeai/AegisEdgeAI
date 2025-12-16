#!/bin/bash
# Script to copy updated files from Windows to Linux remote machine
# Run this on your Windows machine (Git Bash or WSL)

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Copy Updated Files to Remote Linux Machine                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
REMOTE_USER="dell"
REMOTE_HOST="vso"
REMOTE_IP="172.26.1.77"
REMOTE_DIR="~/dhanush/hybrid-cloud-poc-backup"

# Files to copy
FILES_TO_COPY=(
    "keylime/verifier.conf.minimal"
    "test_complete.sh"
    "python-app-demo/fetch-sovereign-svid-grpc.py"
    "patch-test-complete.sh"
    "fix-tpm-resource-conflict.sh"
    "SYNC_AND_FIX_GUIDE.md"
    "EXACT_LINES_TO_DISABLE.md"
    "FIX_TPM_RESOURCE_CONFLICT.md"
    "QUICK_FIX_TPM_CONFLICT.md"
)

echo -e "${CYAN}Files to copy:${NC}"
for file in "${FILES_TO_COPY[@]}"; do
    echo "  - $file"
done
echo ""

# Check if we can reach the remote machine
echo -e "${CYAN}Checking connection to ${REMOTE_USER}@${REMOTE_IP}...${NC}"
if ! ping -c 1 -W 2 "$REMOTE_IP" >/dev/null 2>&1; then
    echo -e "${RED}✗ Cannot reach remote machine at $REMOTE_IP${NC}"
    echo "  Please check network connection"
    exit 1
fi
echo -e "${GREEN}✓ Remote machine is reachable${NC}"
echo ""

# Option 1: Using SCP (if you have SSH access)
echo -e "${BOLD}Option 1: Copy via SCP${NC}"
echo ""
echo "Run these commands:"
echo ""
for file in "${FILES_TO_COPY[@]}"; do
    echo "scp \"$file\" ${REMOTE_USER}@${REMOTE_IP}:${REMOTE_DIR}/$file"
done
echo ""

# Option 2: Manual copy instructions
echo -e "${BOLD}Option 2: Manual Copy (if no SSH)${NC}"
echo ""
echo "1. On Windows, copy these files to a USB drive or shared folder:"
for file in "${FILES_TO_COPY[@]}"; do
    echo "   - $file"
done
echo ""
echo "2. On Linux machine, copy them to: ${REMOTE_DIR}"
echo ""

# Option 3: Generate a single tar file
echo -e "${BOLD}Option 3: Create TAR Archive${NC}"
echo ""
echo "Creating tar archive..."

TAR_FILE="updated-files-$(date +%Y%m%d-%H%M%S).tar.gz"

# Create tar with only existing files
EXISTING_FILES=()
for file in "${FILES_TO_COPY[@]}"; do
    if [ -f "$file" ]; then
        EXISTING_FILES+=("$file")
    else
        echo -e "${YELLOW}⚠ File not found: $file${NC}"
    fi
done

if [ ${#EXISTING_FILES[@]} -gt 0 ]; then
    tar -czf "$TAR_FILE" "${EXISTING_FILES[@]}"
    echo -e "${GREEN}✓ Created: $TAR_FILE${NC}"
    echo ""
    echo "To extract on remote machine:"
    echo "  1. Copy $TAR_FILE to remote machine"
    echo "  2. Run: cd ${REMOTE_DIR}"
    echo "  3. Run: tar -xzf $TAR_FILE"
else
    echo -e "${RED}✗ No files found to archive${NC}"
fi

echo ""
echo -e "${BOLD}After copying files to remote machine:${NC}"
echo ""
echo "1. SSH to remote machine:"
echo "   ssh ${REMOTE_USER}@${REMOTE_IP}"
echo ""
echo "2. Navigate to project directory:"
echo "   cd ${REMOTE_DIR}"
echo ""
echo "3. Make scripts executable:"
echo "   chmod +x patch-test-complete.sh fix-tpm-resource-conflict.sh"
echo ""
echo "4. Follow instructions in SYNC_AND_FIX_GUIDE.md"
echo ""
