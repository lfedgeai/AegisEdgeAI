#!/bin/bash

# Cleanup All Agents Script
# This script removes all existing agents from the system

# Parse command line arguments
FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-f|--force] [-h|--help]"
            echo ""
            echo "Options:"
            echo "  -f, --force    Skip confirmation prompt"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0              # Interactive mode with confirmation"
            echo "  $0 --force      # Force cleanup without confirmation"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "🧹 Cleaning up all existing agents..."
echo "====================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if agents directory exists
if [ ! -d "agents" ]; then
    echo -e "${YELLOW}No agents directory found. Nothing to clean up.${NC}"
    exit 0
fi

# Find all agent directories
AGENT_DIRS=$(find agents -maxdepth 1 -type d -name "agent-*" 2>/dev/null)

if [ -z "$AGENT_DIRS" ]; then
    echo -e "${YELLOW}No agent directories found. Nothing to clean up.${NC}"
    exit 0
fi

echo -e "${BLUE}Found agent directories:${NC}"
for dir in $AGENT_DIRS; do
    echo "   • $dir"
done
echo ""

# Confirm deletion (skip if force mode)
if [ "$FORCE" = true ]; then
    echo -e "${YELLOW}⚠️  FORCE MODE: Skipping confirmation prompt${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete all agents!${NC}"
    echo ""
    read -p "Continue? (y/n): " confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${YELLOW}Operation cancelled.${NC}"
        exit 0
    fi
fi

echo ""
echo -e "${BLUE}Starting cleanup...${NC}"

# Counter for deleted agents
DELETED_COUNT=0

# Clean up each agent
for agent_dir in $AGENT_DIRS; do
    agent_name=$(basename "$agent_dir")
    echo -n "   Cleaning up $agent_name... "
    
    # Remove agent directory
    if rm -rf "$agent_dir" 2>/dev/null; then
        echo -e "${GREEN}✅${NC}"
        DELETED_COUNT=$((DELETED_COUNT + 1))
    else
        echo -e "${RED}❌${NC}"
    fi
done

echo ""

# Clean up TPM files for all agents
echo -e "${BLUE}Cleaning up TPM files...${NC}"

# Find and remove agent-specific TPM files
TPM_FILES=$(find tpm -name "agent-*" -type f 2>/dev/null)

if [ -n "$TPM_FILES" ]; then
    echo "   Found TPM files to remove:"
    for file in $TPM_FILES; do
        echo -n "     Removing $file... "
        if rm -f "$file" 2>/dev/null; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${RED}❌${NC}"
        fi
    done
else
    echo "   No agent-specific TPM files found."
fi

echo ""

# Clean up collector allowlist
echo -e "${BLUE}Cleaning up collector allowlist...${NC}"

if [ -f "collector/allowed_agents.json" ]; then
    echo -n "   Resetting allowlist... "
    
    # Create empty allowlist
    echo '[]' > "collector/allowed_agents.json"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌${NC}"
    fi
else
    echo "   No allowlist file found."
fi

# Clean up gateway allowlist
echo -e "${BLUE}Cleaning up gateway allowlist...${NC}"

if [ -f "gateway/allowed_agents.json" ]; then
    echo -n "   Resetting allowlist... "
    
    # Create empty allowlist
    echo '[]' > "gateway/allowed_agents.json"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌${NC}"
    fi
else
    echo "   No allowlist file found."
fi

echo ""

# Clean up temporary files
echo -e "${BLUE}Cleaning up temporary files...${NC}"

# Remove temporary files that might have been created
TEMP_FILES=(
    "/tmp/debug_data_to_sign.json"
    "/tmp/debug_nonce.txt"
    "/tmp/tmp*.pem"
    "/tmp/tmp*.key"
)

for pattern in "${TEMP_FILES[@]}"; do
    if ls $pattern 1> /dev/null 2>&1; then
        echo -n "   Removing $pattern... "
        if rm -f $pattern 2>/dev/null; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${RED}❌${NC}"
        fi
    fi
done

echo ""

# Summary
echo -e "${GREEN}🎉 Cleanup completed!${NC}"
echo -e "${BLUE}Summary:${NC}"
echo "   • Deleted $DELETED_COUNT agent directories"
echo "   • Removed agent-specific TPM files"
echo "   • Reset collector allowlist"
echo "   • Reset gateway allowlist"
echo "   • Cleaned up temporary files"

echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "   • Create new agents: python create_agent.py agent-001"
echo "   • Start services: python start_services.py"
echo "   • Test system: ./test_end_to_end_flow.sh"

echo ""
echo -e "${YELLOW}Note: Default TPM files (app.ctx, app.pub, etc.) are preserved.${NC}"
echo -e "${YELLOW}Only agent-specific files have been removed.${NC}"
