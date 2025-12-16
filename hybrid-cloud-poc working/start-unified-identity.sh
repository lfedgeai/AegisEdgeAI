#!/bin/bash
# Unified Identity - Complete Startup Script
# Starts all services for the TPM-backed identity system
# Usage: ./start-unified-identity.sh [--clean]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Unified Identity - TPM-Backed Workload Identity System        ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"

# Check for --clean flag
CLEAN_START=false
if [ "$1" = "--clean" ]; then
    CLEAN_START=true
    echo -e "${YELLOW}Clean start requested - will reset all data${NC}"
fi

# Function to check if a process is running
check_process() {
    pgrep -f "$1" > /dev/null 2>&1
}

# Function to wait for a port to be available
wait_for_port() {
    local port=$1
    local timeout=${2:-30}
    local count=0
    while ! netstat -tuln 2>/dev/null | grep -q ":$port "; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge $timeout ]; then
            return 1
        fi
    done
    return 0
}

# Function to wait for socket
wait_for_socket() {
    local socket=$1
    local timeout=${2:-30}
    local count=0
    while [ ! -S "$socket" ]; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge $timeout ]; then
            return 1
        fi
    done
    return 0
}

echo -e "\n${YELLOW}Step 1: Stopping existing services...${NC}"
pkill -f spire-agent 2>/dev/null || true
pkill -f spire-server 2>/dev/null || true
pkill -f keylime_agent 2>/dev/null || true
pkill -f tpm_plugin_server 2>/dev/null || true
pkill -f "keylime.cmd.verifier" 2>/dev/null || true
pkill -f "keylime.cmd.registrar" 2>/dev/null || true
sleep 3
echo -e "${GREEN}✓ Services stopped${NC}"

if [ "$CLEAN_START" = true ]; then
    echo -e "\n${YELLOW}Step 1b: Cleaning up data directories...${NC}"
    rm -rf /opt/spire/data/server/* 2>/dev/null || true
    rm -rf /opt/spire/data/agent/* 2>/dev/null || true
    rm -rf /tmp/keylime-agent/agent_data.json 2>/dev/null || true
    rm -rf /tmp/keylime-agent/*.ctx 2>/dev/null || true
    rm -rf /tmp/spire-data/tpm-plugin/*.ctx 2>/dev/null || true
    rm -rf /tmp/keylime/*.sqlite 2>/dev/null || true
    
    # Clear TPM handles
    tpm2_evictcontrol -C o -c 0x81010001 2>/dev/null || true
    tpm2_evictcontrol -C o -c 0x8101000a 2>/dev/null || true
    tpm2_evictcontrol -C o -c 0x8101000b 2>/dev/null || true
    tpm2_flushcontext -t 2>/dev/null || true
    echo -e "${GREEN}✓ Data cleaned${NC}"
fi

echo -e "\n${YELLOW}Step 2: Setting up directories...${NC}"
mkdir -p /opt/spire/data/server
mkdir -p /opt/spire/data/agent
mkdir -p /tmp/spire-server/private
mkdir -p /tmp/spire-agent/public
mkdir -p /tmp/spire-data/tpm-plugin
mkdir -p /tmp/keylime-agent/cv_ca
mkdir -p /tmp/keylime

# Setup tmpfs for secure storage if not mounted
if ! mount | grep -q "/tmp/keylime-agent/secure"; then
    echo "  Mounting tmpfs for secure storage..."
    sudo mkdir -p /tmp/keylime-agent/secure
    sudo mount -t tmpfs -o size=1m,mode=0700 tmpfs /tmp/keylime-agent/secure 2>/dev/null || true
    sudo chown -R $(whoami):$(whoami) /tmp/keylime-agent
fi
echo -e "${GREEN}✓ Directories ready${NC}"

echo -e "\n${YELLOW}Step 3: Setting up TLS certificates...${NC}"
cd "$SCRIPT_DIR/keylime"
export KEYLIME_DIR="$SCRIPT_DIR/keylime"

# Check if certificates already exist
if [ -d "cv_ca" ] && [ -f "cv_ca/cacert.crt" ]; then
    echo "  Using existing certificates in keylime/cv_ca"
else
    echo "  Generating new certificates..."
    # Use the same method as test_complete_control_plane.sh
    export KEYLIME_CA_PASSWORD="default"
    # Create minimal ca.conf if needed
    mkdir -p cv_ca
    
    # Generate using openssl directly (simpler than keylime ca tool)
    openssl genrsa -out cv_ca/ca-private.pem 2048 2>/dev/null
    openssl req -new -x509 -key cv_ca/ca-private.pem -out cv_ca/cacert.crt -days 365 \
        -subj "/C=US/O=Keylime/CN=Keylime CA" 2>/dev/null
    
    # Generate server cert
    openssl genrsa -out cv_ca/server-private.pem 2048 2>/dev/null
    openssl req -new -key cv_ca/server-private.pem -out cv_ca/server.csr \
        -subj "/C=US/O=Keylime/CN=server" 2>/dev/null
    openssl x509 -req -in cv_ca/server.csr -CA cv_ca/cacert.crt -CAkey cv_ca/ca-private.pem \
        -CAcreateserial -out cv_ca/server-cert.crt -days 365 2>/dev/null
    
    # Generate client cert
    openssl genrsa -out cv_ca/client-private.pem 2048 2>/dev/null
    openssl req -new -key cv_ca/client-private.pem -out cv_ca/client.csr \
        -subj "/C=US/O=Keylime/CN=client" 2>/dev/null
    openssl x509 -req -in cv_ca/client.csr -CA cv_ca/cacert.crt -CAkey cv_ca/ca-private.pem \
        -CAcreateserial -out cv_ca/client-cert.crt -days 365 2>/dev/null
    
    # Clean up CSR files
    rm -f cv_ca/*.csr cv_ca/*.srl 2>/dev/null
    
    echo "  ✓ Certificates generated"
fi

# Copy certs to agent directory
cp -r cv_ca/* /tmp/keylime-agent/cv_ca/ 2>/dev/null || true
echo -e "${GREEN}✓ TLS certificates generated${NC}"

echo -e "\n${YELLOW}Step 4: Starting Keylime Verifier...${NC}"
cd "$SCRIPT_DIR/keylime"
export KEYLIME_DIR="$SCRIPT_DIR/keylime"
export KEYLIME_VERIFIER_DATABASE_URL="sqlite:////tmp/keylime/cv_data.sqlite"
nohup python3 -m keylime.cmd.verifier > /tmp/keylime-verifier.log 2>&1 &
if wait_for_port 8881 30; then
    echo -e "${GREEN}✓ Keylime Verifier started (port 8881)${NC}"
else
    echo -e "${RED}✗ Keylime Verifier failed to start${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Step 5: Starting Keylime Registrar...${NC}"
export KEYLIME_REGISTRAR_DATABASE_URL="sqlite:////tmp/keylime/reg_data.sqlite"
python3 -m keylime.db.keylime_db --component registrar > /dev/null 2>&1 || true
nohup python3 -m keylime.cmd.registrar > /tmp/keylime-registrar.log 2>&1 &
if wait_for_port 8890 30; then
    echo -e "${GREEN}✓ Keylime Registrar started (port 8890)${NC}"
else
    echo -e "${RED}✗ Keylime Registrar failed to start${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Step 6: Starting rust-keylime Agent...${NC}"
cd "$SCRIPT_DIR"
export UNIFIED_IDENTITY_ENABLED=true
export TCTI="device:/dev/tpmrm0"
export KEYLIME_DIR="/tmp/keylime-agent"
export KEYLIME_AGENT_KEYLIME_DIR="/tmp/keylime-agent"
export KEYLIME_AGENT_RUN_AS="$(whoami):$(whoami)"
nohup ./rust-keylime/target/release/keylime_agent > /tmp/rust-keylime-agent.log 2>&1 &
if wait_for_port 9002 30; then
    echo -e "${GREEN}✓ rust-keylime Agent started (port 9002)${NC}"
else
    echo -e "${RED}✗ rust-keylime Agent failed to start${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Step 7: Starting TPM Plugin Server...${NC}"
export UNIFIED_IDENTITY_ENABLED=true
nohup python3 "$SCRIPT_DIR/tpm-plugin/tpm_plugin_server.py" \
    --socket-path /tmp/spire-data/tpm-plugin/tpm-plugin.sock \
    --work-dir /tmp/spire-data/tpm-plugin > /tmp/tpm-plugin-server.log 2>&1 &
if wait_for_socket /tmp/spire-data/tpm-plugin/tpm-plugin.sock 30; then
    echo -e "${GREEN}✓ TPM Plugin Server started${NC}"
else
    echo -e "${RED}✗ TPM Plugin Server failed to start${NC}"
    exit 1
fi

# Copy TPM plugin CLI to expected location
cp "$SCRIPT_DIR/tpm-plugin/tpm_plugin_cli.py" /tmp/spire-data/tpm-plugin/tpm_plugin_cli.py
chmod +x /tmp/spire-data/tpm-plugin/tpm_plugin_cli.py

echo -e "\n${YELLOW}Step 8: Starting SPIRE Server...${NC}"
export KEYLIME_VERIFIER_URL="https://localhost:8881"
nohup ./spire/bin/spire-server run -config ./python-app-demo/spire-server.conf > /tmp/spire-server.log 2>&1 &
if wait_for_socket /tmp/spire-server/private/api.sock 30; then
    echo -e "${GREEN}✓ SPIRE Server started${NC}"
else
    echo -e "${RED}✗ SPIRE Server failed to start${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Step 9: Exporting trust bundle...${NC}"
sleep 2
./spire/bin/spire-server bundle show -socketPath /tmp/spire-server/private/api.sock > /tmp/bundle.pem
echo -e "${GREEN}✓ Trust bundle exported${NC}"

echo -e "\n${YELLOW}Step 10: Starting SPIRE Agent...${NC}"
export TPM_PLUGIN_CLI_PATH="/tmp/spire-data/tpm-plugin/tpm_plugin_cli.py"
export TPM_PLUGIN_ENDPOINT="unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
export UNIFIED_IDENTITY_ENABLED="true"
nohup ./spire/bin/spire-agent run -config ./python-app-demo/spire-agent.conf > /tmp/spire-agent.log 2>&1 &

echo "  Waiting for SPIRE Agent to complete attestation..."
if wait_for_socket /tmp/spire-agent/public/api.sock 60; then
    echo -e "${GREEN}✓ SPIRE Agent started and attested${NC}"
else
    echo -e "${RED}✗ SPIRE Agent failed to start${NC}"
    echo "  Check logs: tail -50 /tmp/spire-agent.log"
    exit 1
fi

echo -e "\n${YELLOW}Step 11: Creating workload registration entry...${NC}"
# Get the agent SPIFFE ID from logs
sleep 3
AGENT_ID=$(grep -o 'spiffe://example.org/spire/agent/[^"]*' /tmp/spire-agent.log | tail -1)
if [ -n "$AGENT_ID" ]; then
    ./spire/bin/spire-server entry create \
        -socketPath /tmp/spire-server/private/api.sock \
        -parentID "$AGENT_ID" \
        -spiffeID "spiffe://example.org/workload/test" \
        -selector unix:uid:$(id -u) > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Workload entry created${NC}"
else
    echo -e "${YELLOW}⚠ Could not determine agent ID, skipping entry creation${NC}"
fi

echo -e "\n${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Unified Identity System Started Successfully!${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"

echo -e "\n${YELLOW}Services Running:${NC}"
echo "  ├── SPIRE Server      : /tmp/spire-server/private/api.sock"
echo "  ├── SPIRE Agent       : /tmp/spire-agent/public/api.sock"
echo "  ├── Keylime Verifier  : https://localhost:8881"
echo "  ├── Keylime Registrar : http://localhost:8890"
echo "  ├── rust-keylime Agent: https://localhost:9002"
echo "  └── TPM Plugin Server : /tmp/spire-data/tpm-plugin/tpm-plugin.sock"

echo -e "\n${YELLOW}Test Commands:${NC}"
echo "  # Fetch workload SVID"
echo "  ./spire/bin/spire-agent api fetch x509 -socketPath /tmp/spire-agent/public/api.sock"
echo ""
echo "  # Run demo"
echo "  ./demo-unified-identity.sh"
echo ""
echo "  # Watch re-attestation"
echo "  tail -f /tmp/spire-agent.log | grep -i 'reattested'"

echo -e "\n${YELLOW}Log Files:${NC}"
echo "  /tmp/spire-server.log"
echo "  /tmp/spire-agent.log"
echo "  /tmp/keylime-verifier.log"
echo "  /tmp/keylime-registrar.log"
echo "  /tmp/rust-keylime-agent.log"
echo "  /tmp/tpm-plugin-server.log"
