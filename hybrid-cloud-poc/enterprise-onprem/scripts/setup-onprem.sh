#!/bin/bash
# Setup script for enterprise on-prem (10.1.0.10)
# Sets up: Envoy proxy, mTLS server, mobile location service, WASM filter

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONPREM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
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
    echo "  Stopping Envoy..."
    sudo pkill -f "envoy.*envoy.yaml" >/dev/null 2>&1
    sudo pkill -f "^envoy " >/dev/null 2>&1
    
    # Stop mTLS server
    echo "  Stopping mTLS server..."
    pkill -f "mtls-server-app.py" >/dev/null 2>&1
    
    # Stop mobile location service
    echo "  Stopping mobile location service..."
    pkill -f "service.py.*5000" >/dev/null 2>&1
    pkill -f "python3.*service.py" >/dev/null 2>&1
    
    # Free up ports using fuser (if available)
    echo "  Freeing up ports..."
    for port in 5000 9443 8080; do
        if command -v fuser &> /dev/null; then
            sudo fuser -k ${port}/tcp >/dev/null 2>&1
        elif command -v lsof &> /dev/null; then
            PIDS=$(sudo lsof -ti:${port} 2>/dev/null)
            if [ -n "$PIDS" ]; then
                echo "$PIDS" | xargs -r sudo kill -9 >/dev/null 2>&1
            fi
        else
            # Fallback: try to find and kill processes using netstat/ss
            if command -v ss &> /dev/null; then
                PIDS=$(sudo ss -tlnp 2>/dev/null | grep ":${port}" | grep -oP 'pid=\K[0-9]+' 2>/dev/null | head -1)
                if [ -n "$PIDS" ]; then
                    echo "$PIDS" | xargs -r sudo kill -9 >/dev/null 2>&1
                fi
            elif command -v netstat &> /dev/null; then
                PIDS=$(sudo netstat -tlnp 2>/dev/null | grep ":${port}" | awk '{print $7}' | cut -d'/' -f1 | head -1)
                if [ -n "$PIDS" ] && [ "$PIDS" != "-" ]; then
                    echo "$PIDS" | xargs -r sudo kill -9 >/dev/null 2>&1
                fi
            fi
        fi
    done
    
    # Wait a moment for processes to terminate
    sleep 2
    
    # Clean up log files
    printf '  Cleaning up log files...\n'
    sudo rm -f /opt/envoy/logs/envoy.log /tmp/mobile-sensor.log /tmp/mtls-server.log >/dev/null 2>&1
    sudo mkdir -p /opt/envoy/logs >/dev/null 2>&1
    sudo touch /opt/envoy/logs/envoy.log >/dev/null 2>&1
    sudo chmod 666 /opt/envoy/logs/envoy.log >/dev/null 2>&1
    
    # Re-enable exit on error
    set -e
    
    echo -e "${GREEN}  ✓ Cleanup complete${NC}"
}

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
    echo "Option 1: Using apt (Ubuntu/Debian):"
    echo "  curl -sL 'https://getenvoy.io/gpg' | sudo gpg --dearmor -o /usr/share/keyrings/getenvoy.gpg"
    echo "  echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/getenvoy.gpg] https://deb.dl.getenvoy.io/public/deb/ubuntu focal main' | sudo tee /etc/apt/sources.list.d/getenvoy.list"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install -y getenvoy-envoy"
    printf '\n'
    echo "Option 2: Download binary directly:"
    echo "  wget https://github.com/envoyproxy/envoy/releases/download/v1.28.0/envoy-1.28.0-linux-x86_64"
    echo "  sudo mv envoy-1.28.0-linux-x86_64 /usr/local/bin/envoy"
    echo "  sudo chmod +x /usr/local/bin/envoy"
    printf '\n'
    echo "Option 3: Using Docker:"
    echo "  docker pull envoyproxy/envoy:v1.28-latest"
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
echo "  Generating Envoy-specific certificates..."
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
        echo "     Certificate: /opt/envoy/certs/envoy-cert.pem"
        echo "     Key: /opt/envoy/certs/envoy-key.pem"
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
echo "  Copying Envoy certificate to client (${SPIRE_CLIENT_HOST}) for verification..."
if scp -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    /opt/envoy/certs/envoy-cert.pem \
    "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}:~/.mtls-demo/envoy-cert.pem" 2>/dev/null; then
    echo -e "${GREEN}  ✓ Envoy certificate copied to ${SPIRE_CLIENT_HOST}:~/.mtls-demo/envoy-cert.pem${NC}"
    echo "     Client should use this cert via CA_CERT_PATH for Envoy verification"
else
    echo -e "${YELLOW}  ⚠ Could not copy Envoy certificate to ${SPIRE_CLIENT_HOST}${NC}"
    echo "     You can manually copy it later:"
    echo "       scp /opt/envoy/certs/envoy-cert.pem ${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}:~/.mtls-demo/envoy-cert.pem"
    echo "     Then on client, set: export CA_CERT_PATH=~/.mtls-demo/envoy-cert.pem"
fi

# Note: Backend mTLS server will use its own certificates from ~/.mtls-demo/
# These are separate from Envoy's certificates for clarity

# Fetch SPIRE bundle from 10.1.0.11
echo "  Fetching SPIRE CA bundle from 10.1.0.11..."
SPIRE_CLIENT_HOST="${SPIRE_CLIENT_HOST:-10.1.0.11}"
SPIRE_CLIENT_USER="${SPIRE_CLIENT_USER:-mw}"

# Try to fetch from 10.1.0.11
if scp -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}:/tmp/spire-bundle.pem" \
    /tmp/spire-bundle.pem 2>/dev/null; then
    echo -e "${GREEN}  ✓ SPIRE bundle fetched from ${SPIRE_CLIENT_HOST}${NC}"
    sudo cp /tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem
    sudo chmod 644 /opt/envoy/certs/spire-bundle.pem
    echo -e "${GREEN}  ✓ SPIRE bundle copied to /opt/envoy/certs/${NC}"
elif [ -f /tmp/spire-bundle.pem ]; then
    # If scp failed but file exists locally, use it
    echo -e "${YELLOW}  ⚠ Could not fetch from ${SPIRE_CLIENT_HOST}, using local /tmp/spire-bundle.pem${NC}"
    sudo cp /tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem
    sudo chmod 644 /opt/envoy/certs/spire-bundle.pem
    echo -e "${GREEN}  ✓ SPIRE bundle copied from local file${NC}"
else
    echo -e "${YELLOW}  ⚠ Could not fetch SPIRE bundle from ${SPIRE_CLIENT_HOST}${NC}"
    echo "     You can manually copy it later:"
    echo "       scp ${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}:/tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem"
    echo "     Or extract it on ${SPIRE_CLIENT_HOST} first:"
    echo "       cd ~/AegisEdgeAI/hybrid-cloud-poc && python3 fetch-spire-bundle.py"
    printf '\n'
    read -p "Press Enter to continue (you can add the bundle later), or 'q' to quit: " answer
    if [ "$answer" = "q" ]; then
        exit 1
    fi
fi

# Copy backend mTLS server certificate for Envoy to verify upstream connections
# Envoy needs the backend server's cert to verify it when connecting upstream
if [ -f "$HOME/.mtls-demo/server-cert.pem" ]; then
    echo "  Copying backend server certificate for Envoy upstream verification..."
    sudo cp "$HOME/.mtls-demo/server-cert.pem" /opt/envoy/certs/server-cert.pem
    sudo chmod 644 /opt/envoy/certs/server-cert.pem
    echo -e "${GREEN}  ✓ Backend server certificate copied (for Envoy upstream verification)${NC}"
else
    echo -e "${YELLOW}  ⚠ Backend server certificate not found at ~/.mtls-demo/server-cert.pem${NC}"
    echo "     It will be auto-generated when the mTLS server starts"
    echo "     You'll need to copy it to /opt/envoy/certs/server-cert.pem for Envoy upstream verification"
fi

# Verify required certificates
printf '\n'
echo "  Verifying certificates..."
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
    echo "     This is the backend mTLS server's certificate"
    MISSING_CERTS=$((MISSING_CERTS + 1))
fi

if [ $MISSING_CERTS -eq 0 ]; then
    echo -e "${GREEN}  ✓ All Envoy certificates in place${NC}"
    echo "     - Envoy cert/key: For Envoy's own TLS connections"
    echo "     - SPIRE bundle: For verifying SPIRE clients"
    echo "     - Backend server cert: For verifying backend server"
elif [ $MISSING_CERTS -lt 4 ]; then
    echo -e "${YELLOW}  ⚠ Some certificates are missing but setup will continue${NC}"
    echo "     Envoy cert/key: Auto-generated above"
    echo "     Backend server cert: Will be auto-generated when mTLS server starts"
    echo "     SPIRE bundle: Can be added later"
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
echo "  To start manually:"
echo "    cd $REPO_ROOT/mobile-sensor-microservice"
echo "    source .venv/bin/activate"
echo "    python3 service.py --port 5000 --host 0.0.0.0"

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
        echo "  Sensor ID extraction is done directly in WASM filter - no separate service needed"
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
    echo "  Validating Envoy configuration..."
    if sudo envoy --config-path /opt/envoy/envoy.yaml --mode validate &>/dev/null; then
        echo -e "${GREEN}  ✓ Envoy configuration is valid${NC}"
    else
        echo -e "${YELLOW}  ⚠ Envoy configuration validation failed${NC}"
        echo "     Run manually to see errors: sudo envoy --config-path /opt/envoy/envoy.yaml --mode validate"
    fi
else
    echo -e "${YELLOW}  ⚠ Envoy not found - skipping configuration validation${NC}"
fi

printf '\n'
echo "  To start Envoy manually:"
echo "    sudo envoy -c /opt/envoy/envoy.yaml"
echo "  Or run in background:"
echo "    sudo envoy -c /opt/envoy/envoy.yaml > /opt/envoy/logs/envoy.log 2>&1 &"

echo
echo "=========================================="
echo "Setup complete!"
echo "=========================================="

# Only auto-start services on test machine (10.1.0.10)
if [ "$IS_TEST_MACHINE" = "true" ]; then
    # Start all services in the background
    # Ensure clean output - flush any pending output
    exec >&2  # Redirect to stderr temporarily to avoid buffering issues
    exec >&1  # Restore stdout
    printf '\n'
    printf 'Starting all services in the background...\n'
    
    # Temporarily disable exit on error for service startup
    set +e
    
    # Set CAMARA_BASIC_AUTH for mobile location service (test machine only)
    CAMARA_BASIC_AUTH="Basic NDcyOWY5ZDItMmVmNy00NTdhLWJlMzMtMGVkZjg4ZDkwZjA0OmU5N2M0Mzg0LTI4MDYtNDQ5YS1hYzc1LWUyZDJkNzNlOWQ0Ng=="

    # Create environment file for mobile sensor service
    if [ -n "$CAMARA_BASIC_AUTH" ]; then
        echo "CAMARA_BASIC_AUTH=$CAMARA_BASIC_AUTH" | sudo tee /etc/mobile-sensor-service.env >/dev/null 2>&1
        echo "  [OK] Mobile sensor service environment configured"
    fi

    # Start Mobile Location Service
    echo "  Starting Mobile Location Service (port 5000)..."
    cd "$REPO_ROOT/mobile-sensor-microservice" 2>/dev/null
    if [ -d ".venv" ] && [ -f "service.py" ]; then
        source .venv/bin/activate
        if [ -n "$CAMARA_BASIC_AUTH" ]; then
            export CAMARA_BASIC_AUTH
            python3 service.py --port 5000 --host 0.0.0.0 > /tmp/mobile-sensor.log 2>&1 &
        else
            export CAMARA_BYPASS=true
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
        export CA_CERT_PATH="/opt/envoy/certs/spire-bundle.pem"
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
        sudo envoy -c /opt/envoy/envoy.yaml > /opt/envoy/logs/envoy.log 2>&1 &
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
    # Ensure clean output before verification section
    exec 1>&1
    sync 2>/dev/null || true
    printf '\n'
    printf 'Verifying services...\n'
    # Force flush
    exec 1>&1
    sleep 2

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

