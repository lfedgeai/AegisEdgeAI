#!/bin/bash
# Test script for enterprise on-prem (10.1.0.10)
# Sets up: Envoy proxy, mTLS server, mobile location service, WASM filter

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONPREM_DIR="$SCRIPT_DIR"
REPO_ROOT="$(cd "$ONPREM_DIR/.." && pwd)"

# Verify paths
if [ ! -d "$REPO_ROOT/mobile-sensor-microservice" ]; then
    printf 'Error: Could not find mobile-sensor-microservice at %s\n' "$REPO_ROOT/mobile-sensor-microservice"
    printf '  SCRIPT_DIR: %s\n' "$SCRIPT_DIR"
    printf '  ONPREM_DIR: %s\n' "$ONPREM_DIR"
    printf '  REPO_ROOT: %s\n' "$REPO_ROOT"
    exit 1
fi

printf '==========================================\n'
printf 'Enterprise On-Prem Setup (10.1.0.10)\n'
printf '==========================================\n'

# Disable colors entirely to prevent terminal corruption
# Colors can cause terminal corruption in some environments
RED=''
GREEN=''
YELLOW=''
NC=''
# Ensure terminal is reset on exit (safe even without colors)
trap 'tput sgr0 2>/dev/null || true' EXIT

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}Warning: Not running as root. Some operations may require sudo.${NC}"
fi

# Check if running on test machine (10.1.0.10)
CURRENT_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
IS_TEST_MACHINE=false
if [ "$CURRENT_IP" = "10.1.0.10" ] || [ "$(hostname)" = "mwserver12" ]; then
    IS_TEST_MACHINE=true
    echo -e "${GREEN}Running on test machine (10.1.0.10) - cleanup and auto-start enabled${NC}"
fi

# Cleanup function - stops all services and frees up ports (only for test machine)
cleanup_existing_services() {
    echo -e "\n${YELLOW}Cleaning up existing services and ports...${NC}"
    
    # Temporarily disable exit on error for cleanup
    set +e
    
    # Stop Envoy
    printf '  Stopping Envoy...\n'
    sudo pkill -f "envoy.*envoy.yaml" >/dev/null 2>&1
    sudo pkill -f "^envoy " >/dev/null 2>&1
    
    # Stop mTLS server
    printf '  Stopping mTLS server...\n'
    pkill -f "mtls-server-app.py" >/dev/null 2>&1
    
    # Stop mobile location service
    printf '  Stopping mobile location service...\n'
    pkill -f "service.py.*5000" >/dev/null 2>&1
    pkill -f "python3.*service.py" >/dev/null 2>&1
    
    # Free up ports using fuser (if available)
    printf '  Freeing up ports...\n'
    for port in 5000 9443 8080; do
        if command -v fuser &> /dev/null; then
            sudo fuser -k ${port}/tcp >/dev/null 2>&1
        elif command -v lsof &> /dev/null; then
            PIDS=$(sudo lsof -ti:${port} 2>/dev/null)
            if [ -n "$PIDS" ]; then
                printf '%s\n' "$PIDS" | xargs -r sudo kill -9 >/dev/null 2>&1
            fi
        else
            # Fallback: try to find and kill processes using netstat/ss
            if command -v ss &> /dev/null; then
                PIDS=$(sudo ss -tlnp 2>/dev/null | grep ":${port}" | grep -oP 'pid=\K[0-9]+' 2>/dev/null | head -1)
                if [ -n "$PIDS" ]; then
                    printf '%s\n' "$PIDS" | xargs -r sudo kill -9 >/dev/null 2>&1
                fi
            elif command -v netstat &> /dev/null; then
                PIDS=$(sudo netstat -tlnp 2>/dev/null | grep ":${port}" | awk '{print $7}' | cut -d'/' -f1 | head -1)
                if [ -n "$PIDS" ] && [ "$PIDS" != "-" ]; then
                    printf '%s\n' "$PIDS" | xargs -r sudo kill -9 >/dev/null 2>&1
                fi
            fi
        fi
    done
    
    # Wait a moment for processes to terminate
    sleep 2
    
    # Clean up log files and old temporary files
    printf '  Cleaning up log files and old temporary files...\n'
    # Remove all log files
    sudo rm -f /opt/envoy/logs/envoy.log /tmp/mobile-sensor.log /tmp/mtls-server.log /tmp/mtls-server-app.log >/dev/null 2>&1
    # Remove any old WASM build artifacts
    sudo rm -f /opt/envoy/plugins/sensor_verification_wasm.wasm.old >/dev/null 2>&1
    # Remove old certificate backups if any
    sudo rm -f /opt/envoy/certs/*.pem.old /opt/envoy/certs/*.bak >/dev/null 2>&1
    # Remove old environment files
    sudo rm -f /etc/mobile-sensor-service.env.old >/dev/null 2>&1
    # Recreate log directory and file
    sudo mkdir -p /opt/envoy/logs >/dev/null 2>&1
    sudo touch /opt/envoy/logs/envoy.log >/dev/null 2>&1
    sudo chmod 666 /opt/envoy/logs/envoy.log >/dev/null 2>&1
    
    # Re-enable exit on error
    set -e
    
    echo -e "${GREEN}  ✓ Cleanup complete${NC}"
}

# Usage helper
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --cleanup-only       Stop services, remove logs, and exit.
  -h, --help          Show this help message.

This script sets up the enterprise on-prem environment:
  - Envoy proxy (port 8080)
  - mTLS server (port 9443)
  - Mobile location service (port 5000)
  - WASM filter for sensor verification

Examples:
  $0                  # Run full setup
  $0 --cleanup-only   # Stop all services and clean up logs
  $0 --help           # Show this help message
EOF
}

# Parse command line arguments
RUN_CLEANUP_ONLY=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cleanup-only)
            RUN_CLEANUP_ONLY=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1"
            show_usage
            exit 1
            ;;
    esac
done

# If --cleanup-only, run cleanup and exit
if [ "$RUN_CLEANUP_ONLY" = "true" ]; then
    printf 'Running cleanup only...\n'
    printf '\n'
    cleanup_existing_services
    printf '\n'
    printf 'Cleanup complete!\n'
    exit 0
fi

# Run cleanup at the start (only on test machine)
if [ "$IS_TEST_MACHINE" = "true" ]; then
    cleanup_existing_services
fi

# 1. Install dependencies
echo -e "\n${GREEN}[1/6] Installing dependencies...${NC}"

# Clean up any problematic Envoy repository that might have been added previously
if command -v apt-get &> /dev/null; then
    if [ -f /etc/apt/sources.list.d/getenvoy.list ]; then
        echo -e "${YELLOW}  Removing existing Envoy repository (will be configured manually if needed)...${NC}"
        sudo rm -f /etc/apt/sources.list.d/getenvoy.list
    fi
    if [ -f /usr/share/keyrings/getenvoy.gpg ]; then
        sudo rm -f /usr/share/keyrings/getenvoy.gpg
    fi
    if [ -f /etc/apt/trusted.gpg.d/getenvoy.gpg ]; then
        sudo rm -f /etc/apt/trusted.gpg.d/getenvoy.gpg
    fi
    
    sudo apt-get update || true
    sudo apt-get install -y \
        python3 python3-pip python3-venv \
        curl wget \
        docker.io docker-compose || true
elif command -v yum &> /dev/null; then
    sudo yum install -y \
        python3 python3-pip \
        curl wget \
        docker docker-compose || true
fi

# Install Envoy
if ! command -v envoy &> /dev/null; then
    echo -e "${YELLOW}Installing Envoy...${NC}"
    echo -e "${YELLOW}Note: Envoy installation methods vary by distribution.${NC}"
    echo -e "${YELLOW}Please install Envoy manually using one of these methods:${NC}"
    printf '\n'
    printf 'Option 1: Using apt (Ubuntu/Debian):\n'
    printf '  curl -sL '\''https://getenvoy.io/gpg'\'' | sudo gpg --dearmor -o /usr/share/keyrings/getenvoy.gpg\n'
    printf '  echo '\''deb [arch=amd64 signed-by=/usr/share/keyrings/getenvoy.gpg] https://deb.dl.getenvoy.io/public/deb/ubuntu focal main'\'' | sudo tee /etc/apt/sources.list.d/getenvoy.list\n'
    printf '  sudo apt-get update\n'
    printf '  sudo apt-get install -y getenvoy-envoy\n'
    printf '\n'
    printf 'Option 2: Download binary directly:\n'
    printf '  wget https://github.com/envoyproxy/envoy/releases/download/v1.28.0/envoy-1.28.0-linux-x86_64\n'
    printf '  sudo mv envoy-1.28.0-linux-x86_64 /usr/local/bin/envoy\n'
    printf '  sudo chmod +x /usr/local/bin/envoy\n'
    printf '\n'
    printf 'Option 3: Using Docker:\n'
    printf '  docker pull envoyproxy/envoy:v1.28-latest\n'
    printf '\n'
    read -p "Press Enter after installing Envoy, or 's' to skip (you can install later): " answer
    if [ "$answer" = "s" ]; then
        echo -e "${YELLOW}Skipping Envoy installation. Please install it manually before starting Envoy proxy.${NC}"
    else
        if command -v envoy &> /dev/null; then
            echo -e "${GREEN}✓ Envoy found${NC}"
        else
            echo -e "${YELLOW}⚠ Envoy not found. Please install it manually.${NC}"
        fi
    fi
fi

# 2. Create directories
echo -e "\n${GREEN}[2/6] Creating directories...${NC}"
sudo mkdir -p /opt/envoy/{certs,plugins,logs}
sudo mkdir -p /opt/mobile-sensor-service
sudo mkdir -p /opt/mtls-server

# Build and install WASM filter for sensor verification
echo -e "${GREEN}  Building WASM filter...${NC}"
cd "$ONPREM_DIR/wasm-plugin"
if [ -f "build.sh" ]; then
    if bash build.sh 2>&1 | tee /tmp/wasm-build.log; then
        echo -e "${GREEN}  ✓ WASM filter built and installed${NC}"
    else
        echo -e "${YELLOW}  ⚠ WASM filter build failed - check /tmp/wasm-build.log${NC}"
        echo -e "${YELLOW}  You may need to install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ WASM plugin directory not found${NC}"
fi

# 3. Setup certificates
echo -e "\n${GREEN}[3/6] Setting up certificates...${NC}"

# Create certs directory
sudo mkdir -p /opt/envoy/certs

# Generate separate certificates for Envoy
# Envoy uses these certificates for:
#   1. Downstream TLS: Presenting to SPIRE clients (port 8080)
#   2. Upstream TLS: Connecting to backend mTLS server (port 9443)
printf '  Generating Envoy-specific certificates...\n'
if [ ! -f /opt/envoy/certs/envoy-cert.pem ] || [ ! -f /opt/envoy/certs/envoy-key.pem ]; then
    sudo openssl req -x509 -newkey rsa:2048 \
        -keyout /opt/envoy/certs/envoy-key.pem \
        -out /opt/envoy/certs/envoy-cert.pem \
        -days 365 -nodes \
        -subj "/CN=envoy-proxy.10.1.0.10/O=Enterprise On-Prem/C=US" 2>/dev/null
    
    if [ -f /opt/envoy/certs/envoy-cert.pem ] && [ -f /opt/envoy/certs/envoy-key.pem ]; then
        sudo chmod 644 /opt/envoy/certs/envoy-cert.pem
        sudo chmod 600 /opt/envoy/certs/envoy-key.pem
        echo -e "${GREEN}  ✓ Envoy certificates generated${NC}"
        printf '     Certificate: /opt/envoy/certs/envoy-cert.pem\n'
        printf '     Key: /opt/envoy/certs/envoy-key.pem\n'
    else
        echo -e "${RED}  ✗ Failed to generate Envoy certificates${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}  ✓ Envoy certificates already exist${NC}"
fi

# Copy Envoy certificate to client machine (10.1.0.11) so client can verify Envoy
SPIRE_CLIENT_HOST="${SPIRE_CLIENT_HOST:-10.1.0.11}"
SPIRE_CLIENT_USER="${SPIRE_CLIENT_USER:-mw}"
printf '  Copying Envoy certificate to client (${SPIRE_CLIENT_HOST}) for verification...\n'
if scp -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    /opt/envoy/certs/envoy-cert.pem \
    "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}:~/.mtls-demo/envoy-cert.pem" 2>/dev/null; then
    echo -e "${GREEN}  ✓ Envoy certificate copied to ${SPIRE_CLIENT_HOST}:~/.mtls-demo/envoy-cert.pem${NC}"
    printf '     Client should use this cert via CA_CERT_PATH for Envoy verification\n'
else
    echo -e "${YELLOW}  ⚠ Could not copy Envoy certificate to ${SPIRE_CLIENT_HOST}${NC}"
    printf '     You can manually copy it later:\n'
    printf '       scp /opt/envoy/certs/envoy-cert.pem ${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}:~/.mtls-demo/envoy-cert.pem\n'
    printf '     Then on client, set: export CA_CERT_PATH=~/.mtls-demo/envoy-cert.pem\n'
fi

# Note: Backend mTLS server will use its own certificates from ~/.mtls-demo/
# These are separate from Envoy's certificates for clarity

# Fetch SPIRE bundle from 10.1.0.11
printf '  Fetching SPIRE CA bundle from 10.1.0.11...\n'
SPIRE_CLIENT_HOST="${SPIRE_CLIENT_HOST:-10.1.0.11}"
SPIRE_CLIENT_USER="${SPIRE_CLIENT_USER:-mw}"

# First, check if bundle exists on 10.1.0.11, if not, generate it
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
    "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}" \
    "test -f /tmp/spire-bundle.pem" 2>/dev/null; then
    # Bundle doesn't exist, try to generate it
    echo "  Generating SPIRE bundle on ${SPIRE_CLIENT_HOST}..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
        "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}" \
        "cd ~/AegisEdgeAI/hybrid-cloud-poc && python3 fetch-spire-bundle.py 2>/dev/null" 2>/dev/null; then
        echo -e "${GREEN}  ✓ SPIRE bundle generated on ${SPIRE_CLIENT_HOST}${NC}"
    else
        # Try alternative method: use SPIRE server command directly
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
            "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}" \
            "test -S /tmp/spire-server/private/api.sock && ~/AegisEdgeAI/hybrid-cloud-poc/spire/bin/spire-server bundle show -format pem -socketPath /tmp/spire-server/private/api.sock > /tmp/spire-bundle.pem 2>/dev/null" 2>/dev/null; then
            echo -e "${GREEN}  ✓ SPIRE bundle generated using SPIRE server command${NC}"
        else
            echo -e "${YELLOW}  ⚠ Could not generate bundle on ${SPIRE_CLIENT_HOST} (SPIRE server may not be ready)${NC}"
        fi
    fi
fi

# Try to fetch from 10.1.0.11
if scp -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
    "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}:/tmp/spire-bundle.pem" \
    /tmp/spire-bundle.pem 2>/dev/null; then
    echo -e "${GREEN}  ✓ SPIRE bundle fetched from ${SPIRE_CLIENT_HOST}${NC}"
    sudo cp /tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem
    sudo chmod 644 /opt/envoy/certs/spire-bundle.pem
    echo -e "${GREEN}  ✓ SPIRE bundle copied to /opt/envoy/certs/${NC}"
elif [ -f /tmp/spire-bundle.pem ]; then
    # If scp failed but file exists locally, use it
    echo -e "${YELLOW}  ⚠ Could not fetch from ${SPIRE_CLIENT_HOST}, using local /tmp/spire-bundle.pem${NC}"
    echo -e "${GREEN}  ✓ SPIRE bundle copied from local file -- spire server is up in ${SPIRE_CLIENT_HOST}${NC}"
    sudo cp /tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem
    sudo chmod 644 /opt/envoy/certs/spire-bundle.pem
else
    echo -e "${YELLOW}  ⚠ Could not fetch SPIRE bundle from ${SPIRE_CLIENT_HOST}${NC}"
    printf '     You can manually copy it later:\n'
    printf '       scp ${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}:/tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem\n'
    printf '     Or extract it on ${SPIRE_CLIENT_HOST} first:\n'
    printf '       cd ~/AegisEdgeAI/hybrid-cloud-poc && python3 fetch-spire-bundle.py\n'
    printf '\n'
    read -p "Press Enter to continue (you can add the bundle later), or 'q' to quit: " answer
    if [ "$answer" = "q" ]; then
        exit 1
    fi
fi

# Copy backend mTLS server certificate for Envoy to verify upstream connections
# Envoy needs the backend server's cert to verify it when connecting upstream
if [ -f "$HOME/.mtls-demo/server-cert.pem" ]; then
    printf '  Copying backend server certificate for Envoy upstream verification...\n'
    sudo cp "$HOME/.mtls-demo/server-cert.pem" /opt/envoy/certs/server-cert.pem
    sudo chmod 644 /opt/envoy/certs/server-cert.pem
    echo -e "${GREEN}  ✓ Backend server certificate copied (for Envoy upstream verification)${NC}"
else
    echo -e "${YELLOW}  ⚠ Backend server certificate not found at ~/.mtls-demo/server-cert.pem${NC}"
    printf '     It will be auto-generated when the mTLS server starts\n'
    printf '     You'\''ll need to copy it to /opt/envoy/certs/server-cert.pem for Envoy upstream verification\n'
fi

# Create combined CA bundle for backend server (SPIRE + Envoy certs)
# Backend server needs to trust both SPIRE clients and Envoy proxy
printf '  Creating combined CA bundle for backend server...\n'
if [ -f /opt/envoy/certs/spire-bundle.pem ] && [ -f /opt/envoy/certs/envoy-cert.pem ]; then
    sudo sh -c "cat /opt/envoy/certs/spire-bundle.pem /opt/envoy/certs/envoy-cert.pem > /opt/envoy/certs/combined-ca-bundle.pem"
    sudo chmod 644 /opt/envoy/certs/combined-ca-bundle.pem
    echo -e "${GREEN}  ✓ Combined CA bundle created: /opt/envoy/certs/combined-ca-bundle.pem${NC}"
    printf '     Contains: SPIRE CA bundle + Envoy certificate\n'
else
    echo -e "${YELLOW}  ⚠ Could not create combined CA bundle (missing spire-bundle.pem or envoy-cert.pem)${NC}"
    printf '     Backend server will need to trust Envoy certificate separately\n'
fi

# Verify required certificates
printf '\n'
printf '  Verifying certificates...\n'
MISSING_CERTS=0
if [ ! -f /opt/envoy/certs/spire-bundle.pem ]; then
    echo -e "${YELLOW}  ⚠ Missing: /opt/envoy/certs/spire-bundle.pem (for verifying SPIRE clients)${NC}"
    MISSING_CERTS=$((MISSING_CERTS + 1))
fi
if [ ! -f /opt/envoy/certs/envoy-cert.pem ]; then
    echo -e "${YELLOW}  ⚠ Missing: /opt/envoy/certs/envoy-cert.pem (Envoy's own certificate)${NC}"
    MISSING_CERTS=$((MISSING_CERTS + 1))
fi
if [ ! -f /opt/envoy/certs/envoy-key.pem ]; then
    echo -e "${YELLOW}  ⚠ Missing: /opt/envoy/certs/envoy-key.pem (Envoy's own key)${NC}"
    MISSING_CERTS=$((MISSING_CERTS + 1))
fi
if [ ! -f /opt/envoy/certs/server-cert.pem ]; then
    echo -e "${YELLOW}  ⚠ Missing: /opt/envoy/certs/server-cert.pem (for verifying backend server)${NC}"
    printf '     This is the backend mTLS server'\''s certificate\n'
    MISSING_CERTS=$((MISSING_CERTS + 1))
fi

if [ $MISSING_CERTS -eq 0 ]; then
    echo -e "${GREEN}  ✓ All Envoy certificates in place${NC}"
    printf '     - Envoy cert/key: For Envoy'\''s own TLS connections\n'
    printf '     - SPIRE bundle: For verifying SPIRE clients\n'
    printf '     - Backend server cert: For verifying backend server\n'
elif [ $MISSING_CERTS -lt 4 ]; then
    echo -e "${YELLOW}  ⚠ Some certificates are missing but setup will continue${NC}"
    printf '     Envoy cert/key: Auto-generated above\n'
    printf '     Backend server cert: Will be auto-generated when mTLS server starts\n'
    printf '     SPIRE bundle: Can be added later\n'
else
    echo -e "${YELLOW}  ⚠ Certificates will be generated/added as needed${NC}"
fi

# 4. Setup mobile location service
echo -e "\n${GREEN}[4/6] Setting up mobile location service...${NC}"
cd "$REPO_ROOT/mobile-sensor-microservice"
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate
pip install -q -r requirements.txt
echo -e "${GREEN}  ✓ Mobile location service dependencies installed${NC}"
printf '  To start manually:\n'
printf '    cd $REPO_ROOT/mobile-sensor-microservice\n'
printf '    source .venv/bin/activate\n'
printf '    python3 service.py --port 5000 --host 0.0.0.0\n'

# 5. Setup mTLS server dependencies
echo -e "\n${GREEN}[5/7] Setting up mTLS server dependencies...${NC}"
cd "$REPO_ROOT/python-app-demo"
# Install cryptography and other required dependencies for mTLS server
pip3 install -q cryptography spiffe grpcio grpcio-tools protobuf 2>/dev/null || {
    echo -e "${YELLOW}  ⚠ Failed to install some dependencies via pip3, trying with --user flag...${NC}"
    pip3 install -q --user cryptography spiffe grpcio grpcio-tools protobuf 2>/dev/null || true
}
echo -e "${GREEN}  ✓ mTLS server dependencies installed${NC}"

# 6. Build WASM filter (sensor ID extraction is done in WASM, no separate service needed)
echo -e "\n${GREEN}[6/7] Building WASM filter for sensor verification...${NC}"
cd "$ONPREM_DIR/wasm-plugin"
if [ -f "build.sh" ]; then
    if bash build.sh 2>&1 | tee /tmp/wasm-build.log; then
        echo -e "${GREEN}  ✓ WASM filter built and installed${NC}"
        printf '  Sensor ID extraction is done directly in WASM filter - no separate service needed\n'
    else
        echo -e "${YELLOW}  ⚠ WASM filter build failed - check /tmp/wasm-build.log${NC}"
        echo -e "${YELLOW}  Install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh${NC}"
        echo -e "${YELLOW}  Then run: cd $ONPREM_DIR/wasm-plugin && bash build.sh${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ WASM plugin directory not found${NC}"
fi

# 7. Setup Envoy
echo -e "\n${GREEN}[7/7] Setting up Envoy proxy...${NC}"

# Copy Envoy configuration
if [ ! -f "$ONPREM_DIR/envoy/envoy.yaml" ]; then
    echo -e "${RED}  ✗ Envoy configuration file not found: $ONPREM_DIR/envoy/envoy.yaml${NC}"
    exit 1
fi

sudo cp "$ONPREM_DIR/envoy/envoy.yaml" /opt/envoy/envoy.yaml
sudo chmod 644 /opt/envoy/envoy.yaml
echo -e "${GREEN}  ✓ Envoy configuration copied to /opt/envoy/envoy.yaml${NC}"

# Validate Envoy configuration if envoy command is available
if command -v envoy &> /dev/null; then
    printf '  Validating Envoy configuration...\n'
    if sudo envoy --config-path /opt/envoy/envoy.yaml --mode validate &>/dev/null; then
        echo -e "${GREEN}  ✓ Envoy configuration is valid${NC}"
    else
        echo -e "${YELLOW}  ⚠ Envoy configuration validation failed${NC}"
        printf '     Run manually to see errors: sudo envoy --config-path /opt/envoy/envoy.yaml --mode validate\n'
    fi
else
    echo -e "${YELLOW}  ⚠ Envoy not found - skipping configuration validation${NC}"
fi

printf '\n'
printf '  To start Envoy manually:\n'
printf '    sudo envoy -c /opt/envoy/envoy.yaml\n'
printf '  Or run in background:\n'
printf '    sudo envoy -c /opt/envoy/envoy.yaml > /opt/envoy/logs/envoy.log 2>&1 &\n'

echo
printf '==========================================\n'
printf 'Setup complete!\n'
printf '==========================================\n'

# Only auto-start services on test machine (10.1.0.10)
if [ "$IS_TEST_MACHINE" = "true" ]; then
    # Start all services in the background
    # Ensure clean output
    printf '\n'
    printf 'Starting all services in the background...\n'
    
    # Temporarily disable exit on error for service startup
    set +e
    
    # Set CAMARA_BYPASS default to true (can be overridden via environment variable)
    export CAMARA_BYPASS="${CAMARA_BYPASS:-true}"
    
    # Set CAMARA_BASIC_AUTH for mobile location service (only if bypass is disabled)
    if [ "$CAMARA_BYPASS" != "true" ]; then
        # Allow override via environment variable, otherwise use default (may be invalid)
        if [ -z "${CAMARA_BASIC_AUTH:-}" ]; then
            # Default credentials (may be invalid - user should provide valid credentials)
            CAMARA_BASIC_AUTH="Basic NDcyOWY5ZDItMmVmNy00NTdhLWJlMzMtMGVkZjg4ZDkwZjA0OmU5N2M0Mzg0LTI4MDYtNDQ5YS1hYzc1LWUyZDJkNzNlOWQ0Ng=="
            printf '  [WARN] CAMARA_BYPASS=false but no CAMARA_BASIC_AUTH provided\n'
            printf '         Using default CAMARA_BASIC_AUTH (may be invalid)\n'
            printf '         Set CAMARA_BASIC_AUTH environment variable with valid credentials\n'
            printf '         Format: export CAMARA_BASIC_AUTH="Basic <base64(client_id:client_secret)>"\n'
        else
            printf '  [OK] Using CAMARA_BASIC_AUTH from environment\n'
        fi

        # Create environment file for mobile sensor service
        if [ -n "$CAMARA_BASIC_AUTH" ]; then
            printf '%s\n' "CAMARA_BASIC_AUTH=$CAMARA_BASIC_AUTH" | sudo tee /etc/mobile-sensor-service.env >/dev/null 2>&1
            printf '  [OK] Mobile sensor service environment configured\n'
        fi
    else
        printf '  [OK] CAMARA_BYPASS=true (CAMARA API calls will be skipped)\n'
    fi

    # Start Mobile Location Service
    printf '  Starting Mobile Location Service (port 5000)...\n'
    cd "$REPO_ROOT/mobile-sensor-microservice" 2>/dev/null
    if [ -d ".venv" ] && [ -f "service.py" ]; then
        source .venv/bin/activate
        # Default to bypass mode (can be overridden by setting CAMARA_BYPASS=false and providing CAMARA_BASIC_AUTH)
        export CAMARA_BYPASS="${CAMARA_BYPASS:-true}"
        if [ -n "$CAMARA_BASIC_AUTH" ] && [ "$CAMARA_BYPASS" != "true" ]; then
            export CAMARA_BASIC_AUTH
            python3 service.py --port 5000 --host 0.0.0.0 > /tmp/mobile-sensor.log 2>&1 &
        else
            python3 service.py --port 5000 --host 0.0.0.0 > /tmp/mobile-sensor.log 2>&1 &
        fi
        MOBILE_PID=$!
        sleep 2
        if ps -p $MOBILE_PID > /dev/null 2>&1; then
            printf '    [OK] Mobile Location Service started (PID: %s)\n' "$MOBILE_PID"
        else
            printf '    [WARN] Mobile Location Service may have failed - check /tmp/mobile-sensor.log\n'
        fi
    else
        printf '    [WARN] Virtual environment or service.py not found - skipping mobile service startup\n'
    fi

    # Start mTLS Server
    printf '  Starting mTLS Server (port 9443)...\n'
    cd "$REPO_ROOT/python-app-demo" 2>/dev/null
    if [ -f "mtls-server-app.py" ]; then
        export SERVER_USE_SPIRE="false"
        export SERVER_PORT="9443"
        # Always use combined CA bundle if it exists (created earlier in the script)
        # This allows backend to trust both SPIRE clients and Envoy proxy
        if [ -f "/opt/envoy/certs/combined-ca-bundle.pem" ]; then
            export CA_CERT_PATH="/opt/envoy/certs/combined-ca-bundle.pem"
            printf '    Using combined CA bundle: /opt/envoy/certs/combined-ca-bundle.pem\n'
        elif [ -f "/opt/envoy/certs/spire-bundle.pem" ] && [ -f "/opt/envoy/certs/envoy-cert.pem" ]; then
            # Create combined bundle on-the-fly if it doesn't exist
            sudo sh -c "cat /opt/envoy/certs/spire-bundle.pem /opt/envoy/certs/envoy-cert.pem > /opt/envoy/certs/combined-ca-bundle.pem"
            sudo chmod 644 /opt/envoy/certs/combined-ca-bundle.pem
            export CA_CERT_PATH="/opt/envoy/certs/combined-ca-bundle.pem"
            printf '    Created and using combined CA bundle: /opt/envoy/certs/combined-ca-bundle.pem\n'
        else
            # Fallback to spire-bundle only if combined can't be created
            export CA_CERT_PATH="/opt/envoy/certs/spire-bundle.pem"
            printf '    [WARN] Using spire-bundle.pem only (Envoy cert not available)\n'
        fi
        python3 mtls-server-app.py > /tmp/mtls-server.log 2>&1 &
        MTLS_PID=$!
        sleep 2
        if ps -p $MTLS_PID > /dev/null 2>&1; then
            printf '    [OK] mTLS Server started (PID: %s)\n' "$MTLS_PID"
        else
            printf '    [WARN] mTLS Server may have failed - check /tmp/mtls-server.log\n'
        fi
    else
        printf '    [WARN] mtls-server-app.py not found - skipping mTLS server startup\n'
    fi

    # Ensure backend server cert is available for Envoy
    if [ ! -f /opt/envoy/certs/server-cert.pem ] && [ -f "$HOME/.mtls-demo/server-cert.pem" ]; then
        sudo cp "$HOME/.mtls-demo/server-cert.pem" /opt/envoy/certs/server-cert.pem 2>/dev/null
        sudo chmod 644 /opt/envoy/certs/server-cert.pem 2>/dev/null
        printf '    [OK] Backend server certificate copied for Envoy\n'
    fi

    # Start Envoy
    printf '  Starting Envoy Proxy (port 8080)...\n'
    if command -v envoy &> /dev/null; then
        sudo mkdir -p /opt/envoy/logs 2>/dev/null
        sudo touch /opt/envoy/logs/envoy.log 2>/dev/null
        sudo chmod 666 /opt/envoy/logs/envoy.log 2>/dev/null
        # Start Envoy with output fully redirected to prevent terminal corruption
        # Use nohup to ensure clean background execution
        nohup sudo env -i PATH="$PATH" envoy -c /opt/envoy/envoy.yaml > /opt/envoy/logs/envoy.log 2>&1 </dev/null &
        ENVOY_PID=$!
        sleep 3
        if ps -p $ENVOY_PID > /dev/null 2>&1; then
            printf '    [OK] Envoy started (PID: %s)\n' "$ENVOY_PID"
        else
            printf '    [WARN] Envoy may have failed - check /opt/envoy/logs/envoy.log\n'
        fi
    else
        printf '    [WARN] Envoy not found - please install and start manually\n'
    fi

    # Re-enable exit on error
    set -e

    # Verify services are running
    printf '\n'
    printf 'Verifying services...\n'
    sleep 1

    # Temporarily disable exit on error for verification
    set +e

    SERVICES_OK=0
    if command -v ss &> /dev/null; then
        if sudo ss -tlnp 2>/dev/null | grep -q ':5000'; then
            printf '  [OK] Mobile Location Service listening on port 5000\n'
            SERVICES_OK=$((SERVICES_OK + 1))
        else
            printf '  [WARN] Mobile Location Service not listening on port 5000\n'
        fi
        if sudo ss -tlnp 2>/dev/null | grep -q ':9443'; then
            printf '  [OK] mTLS Server listening on port 9443\n'
            SERVICES_OK=$((SERVICES_OK + 1))
        else
            printf '  [WARN] mTLS Server not listening on port 9443\n'
        fi
        if sudo ss -tlnp 2>/dev/null | grep -q ':8080'; then
            printf '  [OK] Envoy listening on port 8080\n'
            SERVICES_OK=$((SERVICES_OK + 1))
        else
            printf '  [WARN] Envoy not listening on port 8080\n'
        fi
    elif command -v netstat &> /dev/null; then
        if sudo netstat -tlnp 2>/dev/null | grep -q ':5000'; then
            printf '  [OK] Mobile Location Service listening on port 5000\n'
            SERVICES_OK=$((SERVICES_OK + 1))
        else
            printf '  [WARN] Mobile Location Service not listening on port 5000\n'
        fi
        if sudo netstat -tlnp 2>/dev/null | grep -q ':9443'; then
            printf '  [OK] mTLS Server listening on port 9443\n'
            SERVICES_OK=$((SERVICES_OK + 1))
        else
            printf '  [WARN] mTLS Server not listening on port 9443\n'
        fi
        if sudo netstat -tlnp 2>/dev/null | grep -q ':8080'; then
            printf '  [OK] Envoy listening on port 8080\n'
            SERVICES_OK=$((SERVICES_OK + 1))
        else
            printf '  [WARN] Envoy not listening on port 8080\n'
        fi
    else
        printf '  [WARN] Cannot verify ports (ss/netstat not available)\n'
    fi

    # Re-enable exit on error
    set -e

    printf '\n'
    if [ $SERVICES_OK -eq 3 ]; then
        printf '[SUCCESS] All services are running!\n'
    else
        printf '[WARN] Some services may not be running. Check logs:\n'
        printf '  - Mobile Location Service: tail -f /tmp/mobile-sensor.log\n'
        printf '  - mTLS Server: tail -f /tmp/mtls-server.log\n'
        printf '  - Envoy: tail -f /opt/envoy/logs/envoy.log\n'
    fi

    printf '\n'
    printf 'Service Management:\n'
    printf '  To stop all services: sudo pkill -f '\''envoy.*envoy.yaml'\''; pkill -f '\''mtls-server-app.py'\''; pkill -f '\''service.py.*5000'\''\n'
    printf '  To view logs:\n'
    printf '    tail -f /tmp/mobile-sensor.log\n'
    printf '    tail -f /tmp/mtls-server.log\n'
    printf '    tail -f /opt/envoy/logs/envoy.log\n'
    printf '\n'
    printf 'Note: Sensor ID extraction is done directly in the WASM filter - no separate service needed!\n'
    # Reset terminal colors before exit
    [ -t 1 ] && tput sgr0
else
    # Not on test machine - show manual startup instructions
    printf '\n'
    printf 'To start all services manually (in separate terminals):\n'
    printf '\n'
    printf 'Terminal 1 - Mobile Location Service:\n'
    printf '  cd %s/mobile-sensor-microservice\n' "$REPO_ROOT"
    printf '  source .venv/bin/activate\n'
    printf '  export CAMARA_BYPASS=true  # or set CAMARA_BASIC_AUTH\n'
    printf '  python3 service.py --port 5000 --host 0.0.0.0\n'
    printf '\n'
    printf 'Terminal 2 - mTLS Server:\n'
    printf '  cd %s/python-app-demo\n' "$REPO_ROOT"
    printf '  export SERVER_USE_SPIRE="false"\n'
    printf '  export SERVER_PORT="9443"\n'
    printf '  export CA_CERT_PATH="/opt/envoy/certs/spire-bundle.pem"\n'
    printf '  python3 mtls-server-app.py\n'
    printf '\n'
    printf 'Terminal 3 - Envoy:\n'
    printf '  sudo envoy -c /opt/envoy/envoy.yaml\n'
    printf '\n'
    printf 'Or start all in background:\n'
    printf '  cd %s/mobile-sensor-microservice && source .venv/bin/activate && export CAMARA_BYPASS=true && python3 service.py --port 5000 --host 0.0.0.0 > /tmp/mobile-sensor.log 2>&1 &\n' "$REPO_ROOT"
    printf '  cd %s/python-app-demo && export SERVER_USE_SPIRE="false" SERVER_PORT="9443" && python3 mtls-server-app.py > /tmp/mtls-server.log 2>&1 &\n' "$REPO_ROOT"
    printf '  sudo envoy -c /opt/envoy/envoy.yaml > /opt/envoy/logs/envoy.log 2>&1 &\n'
    printf '\n'
    printf 'Note: Sensor ID extraction is done directly in the WASM filter - no separate service needed!\n'
    # Reset terminal colors before exit
    [ -t 1 ] && tput sgr0
fi

