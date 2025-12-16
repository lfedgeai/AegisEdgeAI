#!/bin/bash
# Configure Hybrid Cloud POC for Single Machine Setup
# This script modifies test_complete_integration.sh to run on a single machine

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Configure Single Machine Setup                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Get current machine IP
echo -e "${CYAN}Step 1: Detecting machine configuration...${NC}"
CURRENT_USER=$(whoami)
echo "  Current user: $CURRENT_USER"

# Try to get primary IP address
CURRENT_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
echo "  Detected IP: $CURRENT_IP"

# Ask user for confirmation
echo ""
echo -e "${YELLOW}Configuration options:${NC}"
echo "  1. Use localhost (127.0.0.1) - Recommended for single machine"
echo "  2. Use detected IP ($CURRENT_IP)"
echo "  3. Enter custom IP address"
echo ""
read -p "Select option [1-3] (default: 1): " OPTION
OPTION=${OPTION:-1}

case $OPTION in
    1)
        MACHINE_IP="127.0.0.1"
        echo "  Using localhost: $MACHINE_IP"
        ;;
    2)
        MACHINE_IP="$CURRENT_IP"
        echo "  Using detected IP: $MACHINE_IP"
        ;;
    3)
        read -p "Enter IP address: " CUSTOM_IP
        MACHINE_IP="$CUSTOM_IP"
        echo "  Using custom IP: $MACHINE_IP"
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${CYAN}Step 2: Checking test_complete_integration.sh...${NC}"

if [ ! -f "test_complete_integration.sh" ]; then
    echo -e "${RED}  ✗ test_complete_integration.sh not found${NC}"
    echo "    Please run this script from the hybrid-cloud-poc directory"
    exit 1
fi

echo -e "${GREEN}  ✓ Found test_complete_integration.sh${NC}"
echo ""

# Backup original file
echo -e "${CYAN}Step 3: Creating backup...${NC}"
if [ ! -f "test_complete_integration.sh.backup" ]; then
    cp test_complete_integration.sh test_complete_integration.sh.backup
    echo -e "${GREEN}  ✓ Backup created: test_complete_integration.sh.backup${NC}"
else
    echo -e "${YELLOW}  ⚠ Backup already exists, skipping${NC}"
fi
echo ""

# Modify the file
echo -e "${CYAN}Step 4: Updating IP addresses...${NC}"

# Create a temporary file with modifications
cat test_complete_integration.sh | \
    sed "s/CONTROL_PLANE_HOST=\"10\.1\.0\.11\"/CONTROL_PLANE_HOST=\"${MACHINE_IP}\"/" | \
    sed "s/ONPREM_HOST=\"10\.1\.0\.10\"/ONPREM_HOST=\"${MACHINE_IP}\"/" | \
    sed "s/SSH_USER=\"mw\"/SSH_USER=\"${CURRENT_USER}\"/" \
    > test_complete_integration.sh.tmp

mv test_complete_integration.sh.tmp test_complete_integration.sh
chmod +x test_complete_integration.sh

echo -e "${GREEN}  ✓ Updated CONTROL_PLANE_HOST to: $MACHINE_IP${NC}"
echo -e "${GREEN}  ✓ Updated ONPREM_HOST to: $MACHINE_IP${NC}"
echo -e "${GREEN}  ✓ Updated SSH_USER to: $CURRENT_USER${NC}"
echo ""

# Add logic to skip SSH for same machine
echo -e "${CYAN}Step 5: Adding same-machine detection logic...${NC}"

# Check if the logic already exists
if grep -q "# Single machine detection" test_complete_integration.sh; then
    echo -e "${YELLOW}  ⚠ Same-machine logic already exists, skipping${NC}"
else
    # We'll need to manually add this logic to the on-prem section
    echo -e "${YELLOW}  ⚠ Manual modification needed for SSH logic${NC}"
    echo "    You'll need to add same-machine detection in the on-prem section"
    echo "    See the instructions below"
fi
echo ""

# Setup passwordless SSH (if not localhost)
if [ "$MACHINE_IP" != "127.0.0.1" ] && [ "$MACHINE_IP" != "localhost" ]; then
    echo -e "${CYAN}Step 6: Setting up passwordless SSH...${NC}"
    
    if [ ! -f ~/.ssh/id_rsa ]; then
        echo "  Generating SSH key..."
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N "" -q
        echo -e "${GREEN}  ✓ SSH key generated${NC}"
    else
        echo -e "${GREEN}  ✓ SSH key already exists${NC}"
    fi
    
    # Add to authorized_keys
    if ! grep -q "$(cat ~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys 2>/dev/null; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        echo -e "${GREEN}  ✓ Added key to authorized_keys${NC}"
    else
        echo -e "${GREEN}  ✓ Key already in authorized_keys${NC}"
    fi
    
    # Test SSH
    echo "  Testing SSH connection..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 ${CURRENT_USER}@${MACHINE_IP} "echo 'SSH test successful'" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Passwordless SSH is working${NC}"
    else
        echo -e "${RED}  ✗ Passwordless SSH test failed${NC}"
        echo "    You may need to manually configure SSH"
    fi
else
    echo -e "${CYAN}Step 6: Skipping SSH setup (using localhost)${NC}"
    echo "  No SSH needed for localhost"
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Configuration Complete                                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}✓ Single machine configuration applied${NC}"
echo ""
echo "Configuration:"
echo "  Machine IP: $MACHINE_IP"
echo "  SSH User: $CURRENT_USER"
echo "  Control Plane: $MACHINE_IP"
echo "  On-Prem: $MACHINE_IP"
echo ""
echo "Next steps:"
echo "  1. Review the changes: diff test_complete_integration.sh.backup test_complete_integration.sh"
echo "  2. Run the integration test: ./test_complete_integration.sh --no-pause"
echo ""
echo "To restore original configuration:"
echo "  mv test_complete_integration.sh.backup test_complete_integration.sh"
echo ""
echo -e "${YELLOW}Note: If using localhost, you may need to modify the on-prem section${NC}"
echo -e "${YELLOW}to avoid SSH to localhost. See manual instructions below.${NC}"
echo ""

# Show manual instructions
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Manual Modification Instructions (if needed)                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "If the test tries to SSH to localhost and fails, you need to modify"
echo "the on-prem section in test_complete_integration.sh:"
echo ""
echo "Find the section that runs on-prem setup (around line 100-200):"
echo ""
echo "  # OLD CODE:"
echo "  ssh \${SSH_USER}@\${ONPREM_HOST} \"cd ~/path && ./test_onprem.sh\""
echo ""
echo "  # NEW CODE (add this check):"
echo "  if [ \"\$CONTROL_PLANE_HOST\" == \"\$ONPREM_HOST\" ]; then"
echo "      # Same machine - run locally"
echo "      cd ~/AegisEdgeAI/hybrid-cloud-poc/enterprise-private-cloud"
echo "      ./test_onprem.sh --no-pause"
echo "  else"
echo "      # Different machine - SSH"
echo "      ssh \${SSH_USER}@\${ONPREM_HOST} \"cd ~/path && ./test_onprem.sh\""
echo "  fi"
echo ""
