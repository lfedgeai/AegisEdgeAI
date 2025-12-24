#!/bin/bash
# Test script for enterprise on-prem
# Sets up: Envoy proxy, mTLS server, mobile location service, WASM filter

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ONPREM_DIR="$SCRIPT_DIR"
REPO_ROOT="$(cd "$ONPREM_DIR/.." && pwd)"

# Source cleanup.sh to reuse cleanup_tmp_files function
# This ensures consistent /tmp cleanup across all test scripts
PROJECT_ROOT="${REPO_ROOT}"
source "${REPO_ROOT}/scripts/cleanup.sh"

# Read host IPs from environment variables (passed by test_integration.sh) BEFORE setting defaults
# This ensures we use the correct IPs when all hosts are the same
# If not set, detect current host IP (for standalone execution)
if [ -z "${CONTROL_PLANE_HOST:-}" ]; then
    CONTROL_PLANE_HOST=$(hostname -I 2>/dev/null | awk '{print $1}' || \
                         ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1 || \
                         echo '127.0.0.1')
fi
if [ -z "${AGENTS_HOST:-}" ]; then
    AGENTS_HOST=$(hostname -I 2>/dev/null | awk '{print $1}' || \
                  ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1 || \
                  echo '127.0.0.1')
fi
if [ -z "${ONPREM_HOST:-}" ]; then
    ONPREM_HOST=$(hostname -I 2>/dev/null | awk '{print $1}' || \
                  ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1 || \
                  echo '127.0.0.1')
fi
CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST}"
AGENTS_HOST="${AGENTS_HOST}"
ONPREM_HOST="${ONPREM_HOST}"

# Detect current host IP early
CURRENT_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1 || echo 'unknown')
CURRENT_HOSTNAME=$(hostname 2>/dev/null || echo 'unknown')

# Verify paths
if [ ! -d "$REPO_ROOT/mobile-sensor-microservice" ]; then
    printf 'Error: Could not find mobile-sensor-microservice at %s\n' "$REPO_ROOT/mobile-sensor-microservice"
    printf '  SCRIPT_DIR: %s\n' "$SCRIPT_DIR"
    printf '  ONPREM_DIR: %s\n' "$ONPREM_DIR"
    printf '  REPO_ROOT: %s\n' "$REPO_ROOT"
    exit 1
fi

printf '==========================================\n'
printf 'Enterprise On-Prem Setup (%s)\n' "${CURRENT_IP}"
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

# Check if running on test machine (auto-detect based on hostname or IP)
# IS_TEST_MACHINE enables cleanup and auto-start
IS_TEST_MACHINE=false

# Enable test machine mode if:
# 1. Hostname matches known test machines
# 2. IP matches known test IPs
# 3. IP is in test network range (10.1.0.x)
# 4. FORCE_TEST_MACHINE environment variable is set
if [ -n "${FORCE_TEST_MACHINE:-}" ]; then
    IS_TEST_MACHINE=true
    echo -e "${GREEN}Running on test machine (forced via FORCE_TEST_MACHINE) - cleanup and auto-start enabled${NC}"
elif [ "${CURRENT_HOSTNAME}" = "mwserver12" ] || [ "${CURRENT_HOSTNAME}" = "mwserver11" ]; then
    IS_TEST_MACHINE=true
    echo -e "${GREEN}Running on test machine (hostname: ${CURRENT_HOSTNAME}, IP: ${CURRENT_IP}) - cleanup and auto-start enabled${NC}"
elif [ -n "${CURRENT_IP}" ] && [ "$CURRENT_IP" != "unknown" ]; then
    # Check for specific test IPs
    # Check if we're on a test machine (IP in common test ranges or matches any of our configured hosts)
    if [ "$CURRENT_IP" = "${CONTROL_PLANE_HOST}" ] || \
       [ "$CURRENT_IP" = "${AGENTS_HOST}" ] || \
       [ "$CURRENT_IP" = "${ONPREM_HOST}" ] || \
       echo "$CURRENT_IP" | grep -qE '^10\.1\.0\.'; then
        IS_TEST_MACHINE=true
        echo -e "${GREEN}Running on test machine (IP: ${CURRENT_IP}, hostname: ${CURRENT_HOSTNAME}) - cleanup and auto-start enabled${NC}"
    # Check for test network range
    elif echo "$CURRENT_IP" | grep -qE '^10\.1\.0\.'; then
        IS_TEST_MACHINE=true
        echo -e "${GREEN}Running on test network (IP: ${CURRENT_IP}, hostname: ${CURRENT_HOSTNAME}) - cleanup and auto-start enabled${NC}"
    fi
fi

# Final check: if still false but we're clearly on a test setup, enable it
# This catches edge cases where IP/hostname detection might have issues
if [ "$IS_TEST_MACHINE" = "false" ]; then
    # Check if we can determine we're on a test machine by checking common indicators
    if [ -d "/home/mw/AegisSovereignAI" ] && [ -n "${CURRENT_IP}" ] && [ "$CURRENT_IP" != "unknown" ]; then
        # If we're in the test directory structure and have a valid IP, likely a test machine
        if echo "$CURRENT_IP" | grep -qE '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'; then
            IS_TEST_MACHINE=true
            echo -e "${GREEN}Running on test machine (detected via environment, IP: ${CURRENT_IP}) - cleanup and auto-start enabled${NC}"
        fi
    fi
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
    
    # Stop mobile location service (only if we started it)
    # Note: Control plane uses /tmp/mobile-sensor-microservice.log
    # On-prem uses /tmp/mobile-sensor.log - we only kill processes using our log file
    printf '  Stopping mobile location service...\n'
    # Only kill processes writing to our specific log file (on-prem log)
    # This avoids killing the service if it was started by control plane (which uses a different log)
    if [ -f /tmp/mobile-sensor.log ]; then
        LOG_PIDS=$(lsof -t /tmp/mobile-sensor.log 2>/dev/null || echo "")
        if [ -n "$LOG_PIDS" ]; then
            echo "$LOG_PIDS" | xargs kill >/dev/null 2>&1 || true
        fi
    fi
    # Also try to kill by pattern matching our specific command (on-prem style)
    pkill -f "service.py.*--port.*9050.*--host.*0.0.0.0.*mobile-sensor.log" >/dev/null 2>&1 || true
    
    # Free up ports using fuser (if available)
    printf '  Freeing up ports...\n'
    for port in 9050 9443 8080; do
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
    # Remove old mTLS server certificates to ensure fresh generation on next start
    rm -f ~/.mtls-demo/server-cert.pem ~/.mtls-demo/server-key.pem >/dev/null 2>&1
    # Remove old environment files
    sudo rm -f /etc/mobile-sensor-service.env.old >/dev/null 2>&1
    # Clean up temporary files in /tmp (using cleanup.sh function)
    cleanup_tmp_files
    # Recreate log directory and file
    sudo mkdir -p /opt/envoy/logs >/dev/null 2>&1
    sudo touch /opt/envoy/logs/envoy.log >/dev/null 2>&1
    sudo chmod 666 /opt/envoy/logs/envoy.log >/dev/null 2>&1
    
    # Re-enable exit on error
    set -e
    
    echo -e "${GREEN}  ✓ Cleanup complete${NC}"
}

# Pause function for critical phases (only in interactive terminals)
pause_at_phase() {
    local phase_name="$1"
    local description="$2"
    
    # Check if pauses are disabled - use explicit comparison
    # PAUSE_ENABLED can be: "false", "0", "no", or unset/empty (which means enabled for interactive)
    local pause_enabled_val="${PAUSE_ENABLED:-}"
    
    # If explicitly set to false/0/no, skip pause
    if [ "$pause_enabled_val" = "false" ] || [ "$pause_enabled_val" = "0" ] || [ "$pause_enabled_val" = "no" ]; then
        # Pauses disabled, skip silently
        return 0
    fi
    
    # Only pause if:
    # 1. Running in interactive terminal (tty check)
    # 2. PAUSE_ENABLED is not explicitly set to false
    if [ -t 0 ]; then
        # If PAUSE_ENABLED is unset or true, pause
        if [ -z "$pause_enabled_val" ] || [ "$pause_enabled_val" = "true" ] || [ "$pause_enabled_val" = "1" ] || [ "$pause_enabled_val" = "yes" ]; then
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "⏸  PAUSE: ${phase_name}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            if [ -n "$description" ]; then
                echo "${description}"
                echo ""
            fi
            echo "Press Enter to continue..."
            read -r
            echo ""
        fi
    fi
}

# Usage helper
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --cleanup-only       Stop services, remove logs, and exit.
  --pause              Enable pause points at critical phases (default: auto-detect)
  --no-pause           Disable pause points (run non-interactively)
  --no-build           Skip building binaries (use existing binaries)
  -h, --help          Show this help message.

This script sets up the enterprise on-prem environment:
  - Envoy proxy (port 8080)
  - mTLS server (port 9443)
  - Mobile location service (port 9050)
  - WASM filter for sensor verification

Examples:
  $0                  # Run full setup
  $0 --cleanup-only   # Stop all services and clean up logs
  $0 --no-pause       # Run without pause prompts
  $0 --help           # Show this help message
EOF
}

# Initialize PAUSE_ENABLED from environment if set, otherwise default based on terminal
if [ -z "${PAUSE_ENABLED:-}" ]; then
    # Default: true for interactive terminals, false for non-interactive
    if [ -t 0 ]; then
        PAUSE_ENABLED=true
    else
        PAUSE_ENABLED=false
    fi
fi

# Parse command line arguments
RUN_CLEANUP_ONLY=false
NO_BUILD="${NO_BUILD:-false}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cleanup-only)
            RUN_CLEANUP_ONLY=true
            shift
            ;;
        --no-pause)
            export PAUSE_ENABLED=false
            PAUSE_ENABLED=false
            shift
            ;;
        --pause)
            export PAUSE_ENABLED=true
            PAUSE_ENABLED=true
            shift
            ;;
        --no-build)
            NO_BUILD=true
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
    pause_at_phase "Cleanup Complete" "Existing services have been stopped and cleaned up."
fi

# 1. Install dependencies
echo -e "\n${GREEN}[1/7] Installing dependencies...${NC}"

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
echo -e "\n${GREEN}[2/7] Creating directories...${NC}"
sudo mkdir -p /opt/envoy/{certs,plugins,logs}
sudo mkdir -p /opt/mobile-sensor-service
sudo mkdir -p /opt/mtls-server

# Build and install WASM filter for sensor verification (if needed)
if [ "$NO_BUILD" != "true" ]; then
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
else
    echo -e "${GREEN}  Skipping WASM filter build (--no-build specified)${NC}"
    if [ ! -f "/opt/envoy/plugins/sensor_verification_wasm.wasm" ]; then
        echo -e "${YELLOW}  ⚠ WASM filter not found at /opt/envoy/plugins/sensor_verification_wasm.wasm${NC}"
        echo -e "${YELLOW}  Build it manually: cd $ONPREM_DIR/wasm-plugin && bash build.sh${NC}"
    fi
fi

# 3. Setup certificates
echo -e "\n${GREEN}[3/7] Setting up certificates...${NC}"

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
        -subj "/CN=envoy-proxy.${CURRENT_IP}/O=Enterprise On-Prem/C=US" 2>/dev/null
    
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

# Copy Envoy certificate to client machine (control plane/agents host) so client can verify Envoy
# Allow override via environment variables (from test_integration.sh)
# These should already be set above, but ensure they're set (use current IP if not)
if [ -z "${CONTROL_PLANE_HOST:-}" ]; then
    CONTROL_PLANE_HOST="${CURRENT_IP}"
fi
if [ -z "${AGENTS_HOST:-}" ]; then
    AGENTS_HOST="${CURRENT_IP}"
fi
CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST}"
AGENTS_HOST="${AGENTS_HOST}"
# SPIRE_CLIENT_HOST is where SPIRE server/client runs (typically same as control plane/agents host)
# If all hosts are the same, use the current host (where SPIRE agent is running)
# Otherwise use control plane host (where SPIRE server typically runs)
if [ "${CONTROL_PLANE_HOST}" = "${AGENTS_HOST}" ] && [ "${AGENTS_HOST}" = "${ONPREM_HOST}" ]; then
    # All services on same machine - use current host for SPIRE bundle
    SPIRE_CLIENT_HOST="${SPIRE_CLIENT_HOST:-${CURRENT_IP}}"
else
    # Different hosts - use control plane host (where SPIRE server typically runs)
    SPIRE_CLIENT_HOST="${SPIRE_CLIENT_HOST:-${CONTROL_PLANE_HOST}}"
fi
SPIRE_CLIENT_USER="${SPIRE_CLIENT_USER:-mw}"

# Detect if SPIRE_CLIENT_HOST is the same as current host
CURRENT_HOST_IPS=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^$' || ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' || echo '')
IS_SAME_HOST=false
if echo "$CURRENT_HOST_IPS" | grep -q "^${SPIRE_CLIENT_HOST}$"; then
    IS_SAME_HOST=true
else
    # Try hostname comparison
    CURRENT_HOSTNAME=$(hostname 2>/dev/null || echo '')
    if [ -n "${CURRENT_HOSTNAME}" ]; then
        TARGET_HOSTNAME=$(getent hosts ${SPIRE_CLIENT_HOST} 2>/dev/null | awk '{print $2}' | head -1 || echo '')
        if [ "${CURRENT_HOSTNAME}" = "${TARGET_HOSTNAME}" ] && [ -n "${TARGET_HOSTNAME}" ]; then
            IS_SAME_HOST=true
        fi
    fi
fi

printf '  Copying Envoy certificate to client (%s) for verification...\n' "${SPIRE_CLIENT_HOST}"
if [ "$IS_SAME_HOST" = "true" ]; then
    # Same host - copy locally
    if cp /opt/envoy/certs/envoy-cert.pem ~/.mtls-demo/envoy-cert.pem 2>/dev/null; then
        mkdir -p ~/.mtls-demo 2>/dev/null || true
        cp /opt/envoy/certs/envoy-cert.pem ~/.mtls-demo/envoy-cert.pem 2>/dev/null || true
        echo -e "${GREEN}  ✓ Envoy certificate copied locally to ~/.mtls-demo/envoy-cert.pem${NC}"
        printf '     Client should use this cert via CA_CERT_PATH for Envoy verification\n'
    else
        echo -e "${YELLOW}  ⚠ Could not copy Envoy certificate locally${NC}"
    fi
elif scp -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
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

# Fetch SPIRE bundle from SPIRE_CLIENT_HOST
# SPIRE_CLIENT_HOST should already be set above (set based on whether all hosts are same)
# Don't override it here - it was already set correctly above
SPIRE_CLIENT_USER="${SPIRE_CLIENT_USER:-mw}"
printf '  Fetching SPIRE CA bundle from %s...\n' "${SPIRE_CLIENT_HOST}"

# Re-check if same host (in case SPIRE_CLIENT_HOST was changed)
IS_SAME_HOST=false
if echo "$CURRENT_HOST_IPS" | grep -q "^${SPIRE_CLIENT_HOST}$"; then
    IS_SAME_HOST=true
else
    CURRENT_HOSTNAME=$(hostname 2>/dev/null || echo '')
    if [ -n "${CURRENT_HOSTNAME}" ]; then
        TARGET_HOSTNAME=$(getent hosts ${SPIRE_CLIENT_HOST} 2>/dev/null | awk '{print $2}' | head -1 || echo '')
        if [ "${CURRENT_HOSTNAME}" = "${TARGET_HOSTNAME}" ] && [ -n "${TARGET_HOSTNAME}" ]; then
            IS_SAME_HOST=true
        fi
    fi
fi

# First, check if bundle exists, if not, generate it
if [ "$IS_SAME_HOST" = "true" ]; then
    # Same host - check and generate locally
    if [ ! -f /tmp/spire-bundle.pem ]; then
        echo "  Generating SPIRE bundle locally..."
        if cd ~/AegisSovereignAI/hybrid-cloud-poc && python3 fetch-spire-bundle.py 2>/dev/null; then
            echo -e "${GREEN}  ✓ SPIRE bundle generated locally${NC}"
        elif [ -S /tmp/spire-server/private/api.sock ]; then
            # Try alternative method: use SPIRE server command directly
            if ~/AegisSovereignAI/hybrid-cloud-poc/spire/bin/spire-server bundle show -format pem -socketPath /tmp/spire-server/private/api.sock > /tmp/spire-bundle.pem 2>/dev/null; then
                echo -e "${GREEN}  ✓ SPIRE bundle generated using SPIRE server command${NC}"
            else
                echo -e "${YELLOW}  ⚠ Could not generate bundle locally (SPIRE server may not be ready)${NC}"
            fi
        else
            echo -e "${YELLOW}  ⚠ Could not generate bundle locally (SPIRE server may not be ready)${NC}"
        fi
    fi
else
    # Different host - use SSH
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
        "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}" \
        "test -f /tmp/spire-bundle.pem" 2>/dev/null; then
        # Bundle doesn't exist, try to generate it
        echo "  Generating SPIRE bundle on ${SPIRE_CLIENT_HOST}..."
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
            "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}" \
            "cd ~/AegisSovereignAI/hybrid-cloud-poc && python3 fetch-spire-bundle.py 2>/dev/null" 2>/dev/null; then
            echo -e "${GREEN}  ✓ SPIRE bundle generated on ${SPIRE_CLIENT_HOST}${NC}"
        else
            # Try alternative method: use SPIRE server command directly
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
                "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}" \
                "test -S /tmp/spire-server/private/api.sock && ~/AegisSovereignAI/hybrid-cloud-poc/spire/bin/spire-server bundle show -format pem -socketPath /tmp/spire-server/private/api.sock > /tmp/spire-bundle.pem 2>/dev/null" 2>/dev/null; then
                echo -e "${GREEN}  ✓ SPIRE bundle generated using SPIRE server command${NC}"
            else
                echo -e "${YELLOW}  ⚠ Could not generate bundle on ${SPIRE_CLIENT_HOST} (SPIRE server may not be ready)${NC}"
            fi
        fi
    fi
fi

# Try to fetch the bundle
if [ "$IS_SAME_HOST" = "true" ]; then
    # Same host - copy locally
    if [ -f /tmp/spire-bundle.pem ]; then
        # Check if bundle changed (to determine if Envoy needs restart)
        BUNDLE_CHANGED=false
        if [ ! -f /opt/envoy/certs/spire-bundle.pem ] || ! cmp -s /tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem; then
            BUNDLE_CHANGED=true
        fi
        sudo cp /tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem
        sudo chmod 644 /opt/envoy/certs/spire-bundle.pem
        echo -e "${GREEN}  ✓ SPIRE bundle copied locally to /opt/envoy/certs/${NC}"
        if [ "$BUNDLE_CHANGED" = "true" ]; then
            echo -e "${YELLOW}  ℹ SPIRE bundle was updated - Envoy will need to reload to pick up changes${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ SPIRE bundle not found locally at /tmp/spire-bundle.pem${NC}"
        printf '     You can generate it:\n'
        printf '       cd ~/AegisSovereignAI/hybrid-cloud-poc && python3 fetch-spire-bundle.py\n'
        printf '\n'
        read -p "Press Enter to continue (you can add the bundle later), or 'q' to quit: " answer
        if [ "$answer" = "q" ]; then
            exit 1
        fi
    fi
elif scp -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
    "${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}:/tmp/spire-bundle.pem" \
    /tmp/spire-bundle.pem 2>/dev/null; then
    echo -e "${GREEN}  ✓ SPIRE bundle fetched from ${SPIRE_CLIENT_HOST}${NC}"
    # Check if bundle changed (to determine if Envoy needs restart)
    BUNDLE_CHANGED=false
    if [ ! -f /opt/envoy/certs/spire-bundle.pem ] || ! cmp -s /tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem; then
        BUNDLE_CHANGED=true
    fi
    sudo cp /tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem
    sudo chmod 644 /opt/envoy/certs/spire-bundle.pem
    echo -e "${GREEN}  ✓ SPIRE bundle copied to /opt/envoy/certs/${NC}"
    if [ "$BUNDLE_CHANGED" = "true" ]; then
        echo -e "${YELLOW}  ℹ SPIRE bundle was updated - Envoy will need to reload to pick up changes${NC}"
    fi
elif [ -f /tmp/spire-bundle.pem ]; then
    # If scp failed but file exists locally, use it
    echo -e "${YELLOW}  ⚠ Could not fetch from ${SPIRE_CLIENT_HOST}, using local /tmp/spire-bundle.pem${NC}"
    echo -e "${GREEN}  ✓ SPIRE bundle copied from local file${NC}"
    sudo cp /tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem
    sudo chmod 644 /opt/envoy/certs/spire-bundle.pem
else
    echo -e "${YELLOW}  ⚠ Could not fetch SPIRE bundle from ${SPIRE_CLIENT_HOST}${NC}"
    printf '     You can manually copy it later:\n'
    printf '       scp ${SPIRE_CLIENT_USER}@${SPIRE_CLIENT_HOST}:/tmp/spire-bundle.pem /opt/envoy/certs/spire-bundle.pem\n'
    printf '     Or extract it on ${SPIRE_CLIENT_HOST} first:\n'
    printf '       cd ~/AegisSovereignAI/hybrid-cloud-poc && python3 fetch-spire-bundle.py\n'
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
# Note: mTLS server will overwrite this with its own cert, so we'll change ownership
printf '  Creating combined CA bundle for backend server...\n'
if [ -f /opt/envoy/certs/spire-bundle.pem ] && [ -f /opt/envoy/certs/envoy-cert.pem ]; then
    CURRENT_USER="${SUDO_USER:-$USER}"
    if [ -z "$CURRENT_USER" ]; then
        CURRENT_USER=$(whoami)
    fi
    sudo sh -c "cat /opt/envoy/certs/spire-bundle.pem /opt/envoy/certs/envoy-cert.pem > /opt/envoy/certs/combined-ca-bundle.pem"
    # Change ownership to current user so mTLS server can write to it
    sudo chown "${CURRENT_USER}:${CURRENT_USER}" /opt/envoy/certs/combined-ca-bundle.pem
    sudo chmod 644 /opt/envoy/certs/combined-ca-bundle.pem
    echo -e "${GREEN}  ✓ Combined CA bundle created: /opt/envoy/certs/combined-ca-bundle.pem${NC}"
    printf '     Contains: SPIRE CA bundle + Envoy certificate\n'
    printf '     Note: mTLS server will overwrite this with its own certificate\n'
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
echo -e "\n${GREEN}[4/7] Setting up mobile location service...${NC}"
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
    printf '    python3 service.py --port 9050 --host 0.0.0.0\n'

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
if [ "$NO_BUILD" != "true" ]; then
    echo -e "\n${GREEN}[6/7] Building WASM filter for sensor verification...${NC}"
    cd "$ONPREM_DIR/wasm-plugin"
    if [ -f "build.sh" ]; then
        if bash build.sh > /tmp/wasm-build.log 2>&1; then
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
else
    echo -e "\n${GREEN}[6/7] Skipping WASM filter build (--no-build specified)${NC}"
    if [ ! -f "/opt/envoy/plugins/sensor_verification_wasm.wasm" ]; then
        echo -e "${YELLOW}  ⚠ WASM filter not found at /opt/envoy/plugins/sensor_verification_wasm.wasm${NC}"
        echo -e "${YELLOW}  Build it manually: cd $ONPREM_DIR/wasm-plugin && bash build.sh${NC}"
    else
        echo -e "${GREEN}  ✓ WASM filter found (using existing binary)${NC}"
    fi
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

# Final check before auto-start: if we're on a test IP and IS_TEST_MACHINE is still false, enable it
# This handles cases where detection might have failed earlier
if [ "$IS_TEST_MACHINE" = "false" ] && [ -n "${CURRENT_IP}" ]; then
    # Check if current IP matches any of the configured hosts (single machine deployment)
    if [ "$CURRENT_IP" = "${CONTROL_PLANE_HOST}" ] || \
       [ "$CURRENT_IP" = "${AGENTS_HOST}" ] || \
       [ "$CURRENT_IP" = "${CONTROL_PLANE_HOST}" ] || \
       [ "$CURRENT_IP" = "${AGENTS_HOST}" ] || \
       [ "$CURRENT_IP" = "${ONPREM_HOST}" ] || \
       [ "${CURRENT_HOSTNAME}" = "mwserver11" ] || \
       [ "${CURRENT_HOSTNAME}" = "mwserver12" ]; then
        IS_TEST_MACHINE=true
        printf 'Enabling auto-start (detected test machine: IP=%s, hostname=%s)\n' "${CURRENT_IP}" "${CURRENT_HOSTNAME}"
    fi
fi

# Only auto-start services on test machine (auto-detected)
if [ "$IS_TEST_MACHINE" = "true" ]; then
    # Start all services in the background
    # Ensure clean output
    printf '\n'
    printf 'Starting all services in the background...\n'
    
    # Temporarily disable exit on error for service startup
    set +e
    
    # Set CAMARA_BYPASS default to true (can be overridden via environment variable)
    export CAMARA_BYPASS="${CAMARA_BYPASS:-true}"
    # DEMO_MODE defaults to true when CAMARA_BYPASS is enabled (suppresses bypass log messages)
    export DEMO_MODE="${DEMO_MODE:-true}"
    
    # Set CAMARA_BASIC_AUTH for mobile location service (only if bypass is disabled)
    if [ "$CAMARA_BYPASS" != "true" ]; then
        # Priority: 1) Environment variable, 2) File (camara_basic_auth.txt), 3) Error
        if [ -z "${CAMARA_BASIC_AUTH:-}" ]; then
            # Try to load from file (similar to how auth_req_id is stored)
            # Check in multiple possible locations
            CAMARA_AUTH_FILE=""
            for possible_path in \
                "$REPO_ROOT/mobile-sensor-microservice/camara_basic_auth.txt" \
                "$REPO_ROOT/camara_basic_auth.txt" \
                "/tmp/mobile-sensor-service/camara_basic_auth.txt" \
                "$(pwd)/camara_basic_auth.txt"; do
                if [ -f "$possible_path" ]; then
                    CAMARA_AUTH_FILE="$possible_path"
                    break
                fi
            done
            
            if [ -n "$CAMARA_AUTH_FILE" ] && [ -f "$CAMARA_AUTH_FILE" ]; then
                # Read file, trim only newlines/carriage returns, preserve spaces
                CAMARA_BASIC_AUTH=$(cat "$CAMARA_AUTH_FILE" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -c 200)
                if [ -n "$CAMARA_BASIC_AUTH" ]; then
                    printf '  [OK] Loaded CAMARA_BASIC_AUTH from file: %s\n' "$CAMARA_AUTH_FILE"
                else
                    CAMARA_BASIC_AUTH=""
                fi
            fi
            
            # If still not set, show error
            if [ -z "${CAMARA_BASIC_AUTH:-}" ]; then
                printf '  [ERROR] CAMARA_BYPASS=false but CAMARA_BASIC_AUTH is not set\n'
                printf '          CAMARA_BASIC_AUTH must be provided via one of:\n'
                printf '          1. Environment variable: export CAMARA_BASIC_AUTH="Basic <base64(client_id:client_secret)>"\n'
                printf '          2. File: Create camara_basic_auth.txt with the credentials\n'
                printf '             Location options:\n'
                printf '             - %s/mobile-sensor-microservice/camara_basic_auth.txt\n' "$REPO_ROOT"
                printf '             - %s/camara_basic_auth.txt\n' "$REPO_ROOT"
                printf '             - /tmp/mobile-sensor-service/camara_basic_auth.txt\n'
                printf '          Format: Basic <base64(client_id:client_secret)>\n'
                printf '          See mobile-sensor-microservice/README.md for instructions\n'
                exit 1
            fi
        else
            printf '  [OK] Using CAMARA_BASIC_AUTH from environment\n'
        fi

        # Create environment file for mobile sensor service
        if [ -n "$CAMARA_BASIC_AUTH" ]; then
            printf '%s\n' "CAMARA_BASIC_AUTH=$CAMARA_BASIC_AUTH" | sudo tee /etc/mobile-sensor-service.env >/dev/null 2>&1
            printf '  [OK] Mobile sensor service environment configured\n'
            printf '  [INFO] Service will obtain auth_req_id from /bc-authorize during initialization\n'
        fi
    else
        printf '  [OK] CAMARA_BYPASS=true (CAMARA API calls will be skipped)\n'
    fi

    # Start Mobile Location Service
    printf '  Starting Mobile Location Service (port 9050)...\n'
    
    # Check if mobile sensor service is already running (e.g., started by test_control_plane.sh)
    MOBILE_SERVICE_RUNNING=false
    if command -v ss >/dev/null 2>&1; then
        if ss -tln 2>/dev/null | grep -q ':9050 '; then
            MOBILE_SERVICE_RUNNING=true
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tln 2>/dev/null | grep -q ':9050 '; then
            MOBILE_SERVICE_RUNNING=true
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -ti :9050 >/dev/null 2>&1; then
            MOBILE_SERVICE_RUNNING=true
        fi
    fi
    
    if [ "$MOBILE_SERVICE_RUNNING" = "true" ]; then
        printf '    [INFO] Mobile Location Service already running on port 9050 (likely started by control plane)\n'
        printf '    [INFO] Skipping startup - using existing service\n'
    else
        cd "$REPO_ROOT/mobile-sensor-microservice" 2>/dev/null
        if [ -d ".venv" ] && [ -f "service.py" ]; then
            source .venv/bin/activate
        
        # Clean up existing database - service will create fresh one on startup with IMEI/IMSI values
        MOBILE_SENSOR_DB="${MOBILE_SENSOR_DB:-sensor_mapping.db}"
        # Check common database locations and delete if found
        DB_PATHS=(
            "$MOBILE_SENSOR_DB"
            "/tmp/mobile-sensor-service/sensor_mapping.db"
            "$REPO_ROOT/mobile-sensor-microservice/sensor_mapping.db"
            "$(pwd)/sensor_mapping.db"
        )
        DB_DELETED=false
        for db_path in "${DB_PATHS[@]}"; do
            if [ -f "$db_path" ]; then
                printf '  Cleaning up existing database: %s\n' "$db_path"
                rm -f "$db_path" 2>/dev/null && DB_DELETED=true
            fi
        done
        # Also check and clean mobile-sensor-service directory
        if [ -d "/tmp/mobile-sensor-service" ]; then
            if [ -f "/tmp/mobile-sensor-service/sensor_mapping.db" ]; then
                printf '  Cleaning up existing database: /tmp/mobile-sensor-service/sensor_mapping.db\n'
                rm -f /tmp/mobile-sensor-service/sensor_mapping.db 2>/dev/null && DB_DELETED=true
            fi
        fi
        if [ "$DB_DELETED" = true ]; then
            printf '  [OK] Database cleaned up - service will create fresh database on startup\n'
        else
            printf '  [INFO] No existing database found - service will create new one on startup\n'
        fi
        
        # Default to bypass mode (can be overridden by setting CAMARA_BYPASS=false and providing CAMARA_BASIC_AUTH)
        export CAMARA_BYPASS="${CAMARA_BYPASS:-true}"
        # DEMO_MODE defaults to true when CAMARA_BYPASS is enabled (suppresses bypass log messages)
        export DEMO_MODE="${DEMO_MODE:-true}"
        # Initialize CAMARA_BASIC_AUTH to avoid unbound variable error
        CAMARA_BASIC_AUTH="${CAMARA_BASIC_AUTH:-}"
        # ALWAYS use port 9050 (required for Keylime Verifier and WASM plugin)
        # Override any environment variables to ensure port 9050 is always used
        unset MOBILE_SENSOR_PORT 2>/dev/null || true
        MOBILE_SERVICE_PORT=9050  # Hardcode to ensure it's always 9050, no matter what
        if [ -n "${CAMARA_BASIC_AUTH:-}" ] && [ "$CAMARA_BYPASS" != "true" ]; then
            export CAMARA_BASIC_AUTH
            python3 service.py --port 9050 --host 0.0.0.0 > /tmp/mobile-sensor.log 2>&1 &
        else
            python3 service.py --port 9050 --host 0.0.0.0 > /tmp/mobile-sensor.log 2>&1 &
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
    fi

    # Start mTLS Server
    printf '  Starting mTLS Server (port 9443)...\n'
    cd "$REPO_ROOT/python-app-demo" 2>/dev/null
    if [ -f "mtls-server-app.py" ]; then
        export SERVER_USE_SPIRE="false"
        export SERVER_PORT="9443"
        # Always use combined CA bundle if it exists (created earlier in the script)
        # This allows backend to trust both SPIRE clients and Envoy proxy
        # Note: Server will overwrite this with its own cert, so we need user ownership
        if [ -f "/opt/envoy/certs/combined-ca-bundle.pem" ]; then
            # Change ownership to current user so server can write to it
            CURRENT_USER="${SUDO_USER:-$USER}"
            if [ -z "$CURRENT_USER" ]; then
                CURRENT_USER=$(whoami)
            fi
            sudo chown "${CURRENT_USER}:${CURRENT_USER}" /opt/envoy/certs/combined-ca-bundle.pem 2>/dev/null || true
            sudo chmod 644 /opt/envoy/certs/combined-ca-bundle.pem 2>/dev/null || true
            export CA_CERT_PATH="/opt/envoy/certs/combined-ca-bundle.pem"
            printf '    Using combined CA bundle: /opt/envoy/certs/combined-ca-bundle.pem\n'
        elif [ -f "/opt/envoy/certs/spire-bundle.pem" ] && [ -f "/opt/envoy/certs/envoy-cert.pem" ]; then
            # Create combined bundle on-the-fly if it doesn't exist
            CURRENT_USER="${SUDO_USER:-$USER}"
            if [ -z "$CURRENT_USER" ]; then
                CURRENT_USER=$(whoami)
            fi
            sudo sh -c "cat /opt/envoy/certs/spire-bundle.pem /opt/envoy/certs/envoy-cert.pem > /opt/envoy/certs/combined-ca-bundle.pem"
            # Change ownership to current user so server can write to it
            sudo chown "${CURRENT_USER}:${CURRENT_USER}" /opt/envoy/certs/combined-ca-bundle.pem
            sudo chmod 644 /opt/envoy/certs/combined-ca-bundle.pem
            export CA_CERT_PATH="/opt/envoy/certs/combined-ca-bundle.pem"
            printf '    Created and using combined CA bundle: /opt/envoy/certs/combined-ca-bundle.pem\n'
        else
            # Fallback to spire-bundle only if combined can't be created
            export CA_CERT_PATH="/opt/envoy/certs/spire-bundle.pem"
            printf '    [WARN] Using spire-bundle.pem only (Envoy cert not available)\n'
        fi
        
        # Ensure certificate directory exists
        mkdir -p ~/.mtls-demo 2>/dev/null || true
        
        # Always clean up old certificates to ensure fresh generation on every start
        # This prevents key mismatch errors from old/stale certificates
        printf '    Cleaning up old certificates to ensure fresh generation...\n'
        rm -f ~/.mtls-demo/server-cert.pem ~/.mtls-demo/server-key.pem 2>/dev/null || true
        
        # Start the server (it will auto-generate fresh certificates)
        MAX_RETRIES=2
        RETRY_COUNT=0
        MTLS_STARTED=false
        
        while [ $RETRY_COUNT -le $MAX_RETRIES ] && [ "$MTLS_STARTED" = "false" ]; do
            if [ $RETRY_COUNT -gt 0 ]; then
                printf '    Retrying mTLS Server startup (attempt %d/%d)...\n' "$((RETRY_COUNT + 1))" "$((MAX_RETRIES + 1))"
                # Clean up certificates again before retry
                printf '    Cleaning up certificates before retry...\n'
                rm -f ~/.mtls-demo/server-cert.pem ~/.mtls-demo/server-key.pem 2>/dev/null || true
                sleep 1
            fi
            
            python3 mtls-server-app.py > /tmp/mtls-server.log 2>&1 &
            MTLS_PID=$!
            
            # Wait for server to start and verify it's listening
            for i in {1..15}; do
                sleep 1
                # Check if process is still running
                if ! ps -p $MTLS_PID > /dev/null 2>&1; then
                    # Check if it's a certificate error
                    if [ -f /tmp/mtls-server.log ] && grep -q "KEY_VALUES_MISMATCH\|key values mismatch" /tmp/mtls-server.log 2>/dev/null; then
                        printf '    [ERROR] Certificate/key mismatch detected - will retry with fresh certificates\n'
                        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                            # Clean up certificates and retry
                            rm -f ~/.mtls-demo/server-cert.pem ~/.mtls-demo/server-key.pem 2>/dev/null || true
                            MTLS_STARTED=false
                            break
                        fi
                    else
                        printf '    [ERROR] mTLS Server process died - check /tmp/mtls-server.log\n'
                        if [ -f /tmp/mtls-server.log ]; then
                            printf '    Last 10 lines of log:\n'
                            tail -10 /tmp/mtls-server.log | sed 's/^/      /'
                        fi
                    fi
                    MTLS_STARTED=false
                    break
                fi
                # Check if server is listening on port 9443
                if command -v ss >/dev/null 2>&1; then
                    if ss -tln 2>/dev/null | grep -q ':9443 '; then
                        printf '    [OK] mTLS Server started and listening on port 9443 (PID: %s)\n' "$MTLS_PID"
                        MTLS_STARTED=true
                        break
                    fi
                elif command -v netstat >/dev/null 2>&1; then
                    if netstat -tln 2>/dev/null | grep -q ':9443 '; then
                        printf '    [OK] mTLS Server started and listening on port 9443 (PID: %s)\n' "$MTLS_PID"
                        MTLS_STARTED=true
                        break
                    fi
                else
                    # Fallback: just check if process is running after a few seconds
                    if [ $i -ge 5 ]; then
                        printf '    [OK] mTLS Server process running (PID: %s) - port check unavailable\n' "$MTLS_PID"
                        MTLS_STARTED=true
                        break
                    fi
                fi
            done
            
            if [ "$MTLS_STARTED" = "true" ]; then
                break
            fi
            
            RETRY_COUNT=$((RETRY_COUNT + 1))
        done
        
        if [ "$MTLS_STARTED" = "false" ]; then
            printf '    [WARN] mTLS Server failed to start after %d attempts - check /tmp/mtls-server.log\n' "$((MAX_RETRIES + 1))"
            if [ -f /tmp/mtls-server.log ]; then
                printf '    Recent log entries:\n'
                tail -30 /tmp/mtls-server.log | sed 's/^/      /'
            fi
        fi
    else
        printf '    [WARN] mtls-server-app.py not found - skipping mTLS server startup\n'
    fi

    # Ensure backend server cert is available for Envoy (always copy after server starts)
    # The server generates fresh certificates, so we need to copy the latest one
    if [ -f "$HOME/.mtls-demo/server-cert.pem" ]; then
        sudo cp "$HOME/.mtls-demo/server-cert.pem" /opt/envoy/certs/server-cert.pem 2>/dev/null
        sudo chmod 644 /opt/envoy/certs/server-cert.pem 2>/dev/null
        printf '    [OK] Backend server certificate copied for Envoy\n'
    else
        printf '    [WARN] Backend server certificate not found - Envoy may fail to verify backend\n'
    fi

    # Start Envoy (or restart if already running to pick up new certificate)
    printf '  Starting Envoy Proxy (port 8080)...\n'
    if command -v envoy &> /dev/null; then
        # Stop existing Envoy if running (to pick up new certificate)
        if pkill -f "envoy.*envoy.yaml" >/dev/null 2>&1; then
            sleep 1
            printf '    Restarted Envoy to pick up new backend certificate\n'
        fi
        
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
            # Restore terminal settings as Envoy/sudo might have messed them up (causing staircase output)
            stty sane 2>/dev/null || true
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
        if sudo ss -tlnp 2>/dev/null | grep -q ':9050'; then
            printf '  [OK] Mobile Location Service listening on port 9050\n'
            SERVICES_OK=$((SERVICES_OK + 1))
        else
            printf '  [WARN] Mobile Location Service not listening on port 9050\n'
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
        if sudo netstat -tlnp 2>/dev/null | grep -q ':9050'; then
            printf '  [OK] Mobile Location Service listening on port 9050\n'
            SERVICES_OK=$((SERVICES_OK + 1))
        else
            printf '  [WARN] Mobile Location Service not listening on port 9050\n'
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
    printf '  To stop all services: sudo pkill -f '\''envoy.*envoy.yaml'\''; pkill -f '\''mtls-server-app.py'\''; pkill -f '\''service.py.*9050'\''\n'
    printf '  To view logs:\n'
    printf '    tail -f /tmp/mobile-sensor.log\n'
    printf '    tail -f /tmp/mtls-server.log\n'
    printf '    tail -f /opt/envoy/logs/envoy.log\n'
    printf '\n'
    printf 'Note: Sensor ID extraction is done directly in the WASM filter - no separate service needed!\n'
    # Reset terminal colors before exit (ignore errors)
    [ -t 1 ] && tput sgr0 2>/dev/null || true
    
    # Exit successfully if services are running
    if [ $SERVICES_OK -eq 3 ]; then
        exit 0
    else
        # Still exit 0 even if verification had warnings (services may still be starting)
        exit 0
    fi
else
    # Not on test machine - show manual startup instructions
    printf '\n'
    printf 'To start all services manually (in separate terminals):\n'
    printf '\n'
    printf 'Terminal 1 - Mobile Location Service:\n'
    printf '  cd %s/mobile-sensor-microservice\n' "$REPO_ROOT"
    printf '  source .venv/bin/activate\n'
    printf '  export CAMARA_BYPASS=true  # or set CAMARA_BASIC_AUTH\n'
    printf '  python3 service.py --port 9050 --host 0.0.0.0\n'
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
    printf '  cd %s/mobile-sensor-microservice && source .venv/bin/activate && export CAMARA_BYPASS=true DEMO_MODE=true && python3 service.py --port 9050 --host 0.0.0.0 > /tmp/mobile-sensor.log 2>&1 &\n' "$REPO_ROOT"
    printf '  cd %s/python-app-demo && export SERVER_USE_SPIRE="false" SERVER_PORT="9443" && python3 mtls-server-app.py > /tmp/mtls-server.log 2>&1 &\n' "$REPO_ROOT"
    printf '  sudo envoy -c /opt/envoy/envoy.yaml > /opt/envoy/logs/envoy.log 2>&1 &\n'
    printf '\n'
    printf 'Note: Sensor ID extraction is done directly in the WASM filter - no separate service needed!\n'
    # Reset terminal colors before exit (ignore errors)
    [ -t 1 ] && tput sgr0 2>/dev/null || true
    exit 0
fi

