#!/bin/bash
# Quick Start - Get Unified Identity System Running
# Run this after a fresh boot or when services are down

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Quick Start: Unified Identity System ==="
echo ""

# Step 1: Stop everything first
echo -e "${YELLOW}[1/9] Stopping existing services...${NC}"
pkill -f spire-agent 2>/dev/null || true
pkill -f spire-server 2>/dev/null || true
pkill -f keylime_agent 2>/dev/null || true
pkill -f tpm_plugin_server 2>/dev/null || true
pkill -f "keylime.cmd.verifier" 2>/dev/null || true
pkill -f "keylime.cmd.registrar" 2>/dev/null || true
pkill -f "service.py.*9050" 2>/dev/null || true
sleep 2
echo -e "${GREEN}Done${NC}"

# Step 2: Setup directories and clean TPM
echo -e "${YELLOW}[2/9] Setting up directories and cleaning TPM...${NC}"
mkdir -p /opt/spire/data/server /opt/spire/data/agent
mkdir -p /tmp/spire-server/private /tmp/spire-agent/public
mkdir -p /tmp/spire-data/tpm-plugin /tmp/keylime-agent/cv_ca /tmp/keylime

# Clean up old agent data to force fresh registration
rm -f /tmp/keylime-agent/agent_data.json 2>/dev/null || true
rm -f /tmp/keylime-agent/*.ctx 2>/dev/null || true
rm -f /tmp/spire-data/tpm-plugin/*.ctx 2>/dev/null || true

# Clear TPM transient handles and flush context
tpm2_flushcontext -t 2>/dev/null || true
tpm2_flushcontext -l 2>/dev/null || true
tpm2_flushcontext -s 2>/dev/null || true

# Clear stale NV indices used by keylime (if any)
# Keylime uses indices in the 0x1410000 and 0x1880000 ranges
for nv_index in 0x1410001 0x1410002 0x1410004 0x1880001 0x1880011; do
    tpm2_nvundefine "$nv_index" 2>/dev/null || true
done

# Mount tmpfs for secure storage
if ! mount | grep -q "/tmp/keylime-agent/secure"; then
    sudo mkdir -p /tmp/keylime-agent/secure
    sudo mount -t tmpfs -o size=1m,mode=0700 tmpfs /tmp/keylime-agent/secure
    sudo chown -R $(whoami):$(whoami) /tmp/keylime-agent
fi
echo -e "${GREEN}Done${NC}"

# Step 3: Generate TLS certificates if needed
echo -e "${YELLOW}[3/9] Setting up TLS certificates...${NC}"
cd "$SCRIPT_DIR/keylime"
if [ ! -f "cv_ca/cacert.crt" ]; then
    mkdir -p cv_ca
    openssl genrsa -out cv_ca/ca-private.pem 2048 2>/dev/null
    openssl req -new -x509 -key cv_ca/ca-private.pem -out cv_ca/cacert.crt -days 365 \
        -subj "/C=US/O=Keylime/CN=Keylime CA" 2>/dev/null
    openssl genrsa -out cv_ca/server-private.pem 2048 2>/dev/null
    openssl req -new -key cv_ca/server-private.pem -out cv_ca/server.csr \
        -subj "/C=US/O=Keylime/CN=server" 2>/dev/null
    openssl x509 -req -in cv_ca/server.csr -CA cv_ca/cacert.crt -CAkey cv_ca/ca-private.pem \
        -CAcreateserial -out cv_ca/server-cert.crt -days 365 2>/dev/null
    openssl genrsa -out cv_ca/client-private.pem 2048 2>/dev/null
    openssl req -new -key cv_ca/client-private.pem -out cv_ca/client.csr \
        -subj "/C=US/O=Keylime/CN=client" 2>/dev/null
    openssl x509 -req -in cv_ca/client.csr -CA cv_ca/cacert.crt -CAkey cv_ca/ca-private.pem \
        -CAcreateserial -out cv_ca/client-cert.crt -days 365 2>/dev/null
    rm -f cv_ca/*.csr cv_ca/*.srl 2>/dev/null
    echo "  Generated new certificates"
fi
cp -r cv_ca/* /tmp/keylime-agent/cv_ca/ 2>/dev/null || true
cd "$SCRIPT_DIR"
echo -e "${GREEN}Done${NC}"

# Step 4: Start Keylime Verifier
echo -e "${YELLOW}[4/9] Starting Keylime Verifier...${NC}"
export KEYLIME_DIR="$SCRIPT_DIR/keylime"
export KEYLIME_VERIFIER_DATABASE_URL="sqlite:////tmp/keylime/cv_data.sqlite"
# Disable agent mTLS requirement since rust-keylime agent has mTLS disabled
export KEYLIME_VERIFIER_ENABLE_AGENT_MTLS="False"
nohup python3 -m keylime.cmd.verifier > /tmp/keylime-verifier.log 2>&1 &
sleep 5
if netstat -tuln 2>/dev/null | grep -q ":8881 "; then
    echo -e "${GREEN}Done (port 8881)${NC}"
else
    echo -e "${RED}FAILED - check /tmp/keylime-verifier.log${NC}"; exit 1
fi

# Step 5: Start Keylime Registrar
echo -e "${YELLOW}[5/9] Starting Keylime Registrar...${NC}"
export KEYLIME_REGISTRAR_DATABASE_URL="sqlite:////tmp/keylime/reg_data.sqlite"
export KEYLIME_REGISTRAR_TLS_DIR="$SCRIPT_DIR/keylime/cv_ca"
export KEYLIME_REGISTRAR_SERVER_KEY="server-private.pem"
export KEYLIME_REGISTRAR_SERVER_CERT="server-cert.crt"
export KEYLIME_REGISTRAR_TRUSTED_CLIENT_CA="all"
export KEYLIME_REGISTRAR_IP="127.0.0.1"
export KEYLIME_REGISTRAR_PORT="8891"
export KEYLIME_REGISTRAR_TLS_PORT="8890"
export KEYLIME_REGISTRAR_AUTO_MIGRATE_DB="True"
nohup python3 -m keylime.cmd.registrar > /tmp/keylime-registrar.log 2>&1 &
sleep 5
if netstat -tuln 2>/dev/null | grep -q ":8890 "; then
    echo -e "${GREEN}Done (port 8890)${NC}"
else
    echo -e "${RED}FAILED - check /tmp/keylime-registrar.log${NC}"; exit 1
fi

# Step 6: Start rust-keylime Agent
echo -e "${YELLOW}[6/9] Starting rust-keylime Agent...${NC}"
export UNIFIED_IDENTITY_ENABLED=true
export TCTI="device:/dev/tpmrm0"
export KEYLIME_DIR="/tmp/keylime-agent"
export KEYLIME_AGENT_KEYLIME_DIR="/tmp/keylime-agent"
export KEYLIME_AGENT_RUN_AS="$(whoami):$(whoami)"
# Use HTTP port for registrar (8891) since mTLS setup is complex
export KEYLIME_AGENT_REGISTRAR_PORT="8891"
export KEYLIME_AGENT_ENABLE_AGENT_MTLS="false"
export KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD="true"
export KEYLIME_AGENT_PAYLOAD_SCRIPT=""
nohup ./rust-keylime/target/release/keylime_agent > /tmp/rust-keylime-agent.log 2>&1 &
sleep 5
if netstat -tuln 2>/dev/null | grep -q ":9002 "; then
    echo -e "${GREEN}Done (port 9002)${NC}"
    # Wait for agent to register with registrar
    echo "  Waiting for agent to register with Keylime..."
    for i in {1..30}; do
        if grep -q "Successfully registered" /tmp/rust-keylime-agent.log 2>/dev/null || \
           grep -q "Agent registered" /tmp/rust-keylime-agent.log 2>/dev/null || \
           grep -q "registered with registrar" /tmp/rust-keylime-agent.log 2>/dev/null; then
            echo -e "  ${GREEN}Agent registered with Keylime${NC}"
            break
        fi
        sleep 1
    done
    sleep 3  # Extra time for registration to complete
else
    echo -e "${RED}FAILED - check /tmp/rust-keylime-agent.log${NC}"; exit 1
fi

# Step 7: Start TPM Plugin Server
echo -e "${YELLOW}[7/9] Starting TPM Plugin Server...${NC}"
cp "$SCRIPT_DIR/tpm-plugin/tpm_plugin_cli.py" /tmp/spire-data/tpm-plugin/
chmod +x /tmp/spire-data/tpm-plugin/tpm_plugin_cli.py
export UNIFIED_IDENTITY_ENABLED=true
nohup python3 "$SCRIPT_DIR/tpm-plugin/tpm_plugin_server.py" \
    --socket-path /tmp/spire-data/tpm-plugin/tpm-plugin.sock \
    --work-dir /tmp/spire-data/tpm-plugin > /tmp/tpm-plugin-server.log 2>&1 &
sleep 3
if [ -S /tmp/spire-data/tpm-plugin/tpm-plugin.sock ]; then
    echo -e "${GREEN}Done (socket ready)${NC}"
else
    echo -e "${RED}FAILED - check /tmp/tpm-plugin-server.log${NC}"; exit 1
fi

# Step 8: Start SPIRE Server
echo -e "${YELLOW}[8/9] Starting SPIRE Server...${NC}"
export KEYLIME_VERIFIER_URL="https://localhost:8881"
nohup ./spire/bin/spire-server run -config ./python-app-demo/spire-server.conf > /tmp/spire-server.log 2>&1 &
sleep 5
if [ -S /tmp/spire-server/private/api.sock ]; then
    echo -e "${GREEN}Done (socket ready)${NC}"
else
    echo -e "${RED}FAILED - check /tmp/spire-server.log${NC}"; exit 1
fi

# Export trust bundle
./spire/bin/spire-server bundle show -socketPath /tmp/spire-server/private/api.sock > /tmp/bundle.pem
echo "  Trust bundle exported to /tmp/bundle.pem"

# Step 9: Start SPIRE Agent
echo -e "${YELLOW}[9/9] Starting SPIRE Agent...${NC}"
export TPM_PLUGIN_CLI_PATH="/tmp/spire-data/tpm-plugin/tpm_plugin_cli.py"
export TPM_PLUGIN_ENDPOINT="unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
export UNIFIED_IDENTITY_ENABLED="true"
nohup ./spire/bin/spire-agent run -config ./python-app-demo/spire-agent.conf > /tmp/spire-agent.log 2>&1 &

echo "  Waiting for attestation (up to 60s)..."
for i in {1..60}; do
    if [ -S /tmp/spire-agent/public/api.sock ]; then
        echo -e "${GREEN}Done - Agent attested!${NC}"
        break
    fi
    sleep 1
done

if [ ! -S /tmp/spire-agent/public/api.sock ]; then
    echo -e "${RED}FAILED - check /tmp/spire-agent.log${NC}"
    tail -20 /tmp/spire-agent.log
    exit 1
fi

# Create workload entry
echo ""
echo -e "${YELLOW}Creating workload registration entry...${NC}"
sleep 2
AGENT_ID=$(grep -o 'spiffe://example.org/spire/agent/[^"]*' /tmp/spire-agent.log | tail -1)
if [ -n "$AGENT_ID" ]; then
    ./spire/bin/spire-server entry create \
        -socketPath /tmp/spire-server/private/api.sock \
        -parentID "$AGENT_ID" \
        -spiffeID "spiffe://example.org/workload/test" \
        -selector unix:uid:$(id -u) 2>/dev/null || true
    echo -e "${GREEN}Done${NC}"
fi

echo ""
echo "=== All Services Running ==="
echo "Test with: ./spire/bin/spire-agent api fetch x509 -socketPath /tmp/spire-agent/public/api.sock"
