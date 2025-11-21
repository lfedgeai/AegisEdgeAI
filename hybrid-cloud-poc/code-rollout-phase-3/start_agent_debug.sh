#!/usr/bin/env bash
# Standalone rust-keylime agent startup script for debugging TPM quote issues
# This script starts the agent and keeps it running for manual testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_DIR="${SCRIPT_DIR}/../code-rollout-phase-2"
RUST_KEYLIME_DIR="${PHASE2_DIR}/rust-keylime"
PYTHON_KEYLIME_DIR="${PHASE2_DIR}/keylime"
KEYLIME_DIR="${PYTHON_KEYLIME_DIR}"
KEYLIME_AGENT_DIR="/tmp/keylime-agent"
VERIFIER_CONFIG="${PHASE2_DIR}/verifier.conf.minimal"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Rust-Keylime Agent - Standalone Debug Startup                  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 0: Cleanup - Kill existing agent and remove persistent data
echo -e "${CYAN}Step 0: Cleaning up existing agent and persistent data...${NC}"

# Kill any existing rust-keylime agent processes
echo "  Stopping any existing rust-keylime agent processes..."
pkill -f "keylime_agent" >/dev/null 2>&1 || true
pkill -f "rust-keylime" >/dev/null 2>&1 || true
pkill -f "target/release/keylime_agent" >/dev/null 2>&1 || true
sleep 2
# Force kill if still running
if pgrep -f "keylime_agent" >/dev/null 2>&1; then
    echo "  Force killing remaining agent processes..."
    pkill -9 -f "keylime_agent" >/dev/null 2>&1 || true
    sleep 1
fi
echo -e "${GREEN}  ✓ Existing agent processes stopped${NC}"

# Unmount tmpfs if mounted
SECURE_DIR="${KEYLIME_AGENT_DIR}/secure"
if mountpoint -q "$SECURE_DIR" 2>/dev/null; then
    echo "  Unmounting tmpfs secure directory..."
    sudo umount "$SECURE_DIR" 2>/dev/null || \
    sudo umount -l "$SECURE_DIR" 2>/dev/null || \
    sudo umount -f "$SECURE_DIR" 2>/dev/null || true
    if mountpoint -q "$SECURE_DIR" 2>/dev/null; then
        echo -e "${YELLOW}  ⚠ tmpfs still mounted, may need manual cleanup${NC}"
    else
        echo -e "${GREEN}  ✓ tmpfs unmounted${NC}"
    fi
fi

# Remove agent persistent data (including agent_data.json with stale AK handles)
echo "  Removing agent persistent data..."
rm -rf "${KEYLIME_AGENT_DIR}" 2>/dev/null || true
# Explicitly remove agent_data.json if it exists (contains AK handles that may be invalid after TPM clear)
rm -f "${KEYLIME_AGENT_DIR}/agent_data.json" 2>/dev/null || true
rm -f /tmp/rust-keylime-agent*.pid 2>/dev/null || true
rm -f /tmp/rust-keylime-agent*.log 2>/dev/null || true
rm -f /tmp/keylime-agent-*.conf 2>/dev/null || true
echo -e "${GREEN}  ✓ Agent persistent data removed (including stale AK handles)${NC}"

# Recreate agent directory
mkdir -p "${KEYLIME_AGENT_DIR}" 2>/dev/null || true
echo ""

# Step 1: Check prerequisites
echo -e "${CYAN}Step 1: Checking prerequisites...${NC}"
if [ ! -f "${RUST_KEYLIME_DIR}/target/release/keylime_agent" ]; then
    echo -e "${RED}  ✗ Agent binary not found at ${RUST_KEYLIME_DIR}/target/release/keylime_agent${NC}"
    echo "  Building agent..."
    cd "${RUST_KEYLIME_DIR}"
    source "$HOME/.cargo/env" 2>/dev/null || true
    cargo build --release || {
        echo -e "${RED}  ✗ Build failed${NC}"
        exit 1
    }
fi
echo -e "${GREEN}  ✓ Agent binary found${NC}"

# Check for verifier/registrar
if ! pgrep -f "keylime\.cmd\.(verifier|registrar)" >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ Keylime Verifier/Registrar not running${NC}"
    echo "  Note: Agent can start without them, but registration will fail"
fi

# Step 2: Setup directories and certificates
echo ""
echo -e "${CYAN}Step 2: Setting up directories and certificates...${NC}"
mkdir -p "${KEYLIME_AGENT_DIR}" 2>/dev/null || true

# Check if certificates exist, generate if needed
TLS_DIR="${KEYLIME_DIR}/cv_ca"
AGENT_CV_CA_SRC="${TLS_DIR}"
AGENT_CV_CA_DST="${KEYLIME_AGENT_DIR}/cv_ca"

if [ ! -d "$AGENT_CV_CA_SRC" ] || [ ! -f "$AGENT_CV_CA_SRC/cacert.crt" ] || [ ! -f "$AGENT_CV_CA_SRC/server-cert.crt" ]; then
    echo "  Certificates not found, generating them..."
    
    # Ensure Python Keylime directory exists
    if [ ! -d "${PYTHON_KEYLIME_DIR}" ]; then
        echo -e "${RED}  ✗ Python Keylime directory not found: ${PYTHON_KEYLIME_DIR}${NC}"
        exit 1
    fi
    
    # Generate certificates using Python Keylime CA utilities
    WORK_DIR="${KEYLIME_DIR}"
    mkdir -p "$TLS_DIR" 2>/dev/null || true
    chmod 700 "$TLS_DIR" 2>/dev/null || true
    
    # Check for verifier config file (contains CA settings with cert_bits)
    if [ ! -f "$VERIFIER_CONFIG" ]; then
        echo -e "${YELLOW}  ⚠ Verifier config not found at ${VERIFIER_CONFIG}${NC}"
        echo "  Certificate generation may fail without proper CA configuration"
    fi
    
    # Set absolute path for verifier config
    if [ -f "$VERIFIER_CONFIG" ]; then
        VERIFIER_CONFIG_ABS="$(cd "$(dirname "${VERIFIER_CONFIG}")" && pwd)/$(basename "${VERIFIER_CONFIG}")"
    else
        VERIFIER_CONFIG_ABS=""
    fi
    
    cd "${PYTHON_KEYLIME_DIR}"
    KEYLIME_DIR_VAR="${KEYLIME_DIR}"
    VERIFIER_CONFIG_ABS_VAR="${VERIFIER_CONFIG_ABS}"
    python3 << PYTHON_EOF
import sys
import os

# Set KEYLIME_DIR before importing keylime modules
os.environ['KEYLIME_DIR'] = '${KEYLIME_DIR_VAR}'
sys.path.insert(0, '${PYTHON_KEYLIME_DIR}')

# Set up config before importing - use verifier config for CA settings
if '${VERIFIER_CONFIG_ABS_VAR}':
    os.environ['KEYLIME_VERIFIER_CONFIG'] = '${VERIFIER_CONFIG_ABS_VAR}'
    os.environ['KEYLIME_CA_CONFIG'] = '${VERIFIER_CONFIG_ABS_VAR}'
    os.environ['KEYLIME_CONFIG'] = '${VERIFIER_CONFIG_ABS_VAR}'
else:
    os.environ['KEYLIME_VERIFIER_CONFIG'] = os.environ.get('KEYLIME_VERIFIER_CONFIG', '')
os.environ['KEYLIME_TEST'] = 'on'

from keylime import config, ca_util, keylime_logging

# Initialize logging
logger = keylime_logging.init_logging("verifier")

# Get TLS directory
tls_dir = os.path.join('${KEYLIME_DIR_VAR}', 'cv_ca')

# Change to TLS directory for certificate generation
original_cwd = os.getcwd()
os.chdir(tls_dir)

try:
    # Set empty password for testing (must be done before cmd_init)
    ca_util.read_password("")
    
    # Initialize CA
    print(f"  Generating CA in {tls_dir}...")
    ca_util.cmd_init(tls_dir)
    print("  ✓ CA certificate generated")
    
    # Generate server certificate
    print("  Generating server certificate...")
    ca_util.cmd_mkcert(tls_dir, 'server', password=None)
    print("  ✓ Server certificate generated")
    
    # Generate client certificate
    print("  Generating client certificate...")
    ca_util.cmd_mkcert(tls_dir, 'client', password=None)
    print("  ✓ Client certificate generated")
    
    print("  ✓ TLS setup complete")
except Exception as e:
    print(f"  ✗ Failed to generate certificates: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
finally:
    os.chdir(original_cwd)
PYTHON_EOF
    
    if [ $? -ne 0 ] || [ ! -f "$AGENT_CV_CA_SRC/cacert.crt" ]; then
        echo -e "${RED}  ✗ Failed to generate TLS certificates${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ Certificates generated${NC}"
fi

# Copy certificates to agent directory
if [ -d "$AGENT_CV_CA_SRC" ]; then
    rm -rf "$AGENT_CV_CA_DST" 2>/dev/null || true
    mkdir -p "$AGENT_CV_CA_DST" 2>/dev/null || true
    cp -a "${AGENT_CV_CA_SRC}/." "${AGENT_CV_CA_DST}/" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Certificates copied to ${AGENT_CV_CA_DST}${NC}"
else
    echo -e "${RED}  ✗ Certificate source not found: ${AGENT_CV_CA_SRC}${NC}"
    exit 1
fi

# Step 3: Setup TPM
echo ""
echo -e "${CYAN}Step 3: Setting up TPM...${NC}"
if [ -c /dev/tpmrm0 ]; then
    TPM_DEVICE="/dev/tpmrm0"
    export TCTI="device:${TPM_DEVICE}"
    echo "  Using TPM resource manager: $TPM_DEVICE"
elif [ -c /dev/tpm0 ]; then
    TPM_DEVICE="/dev/tpm0"
    export TCTI="device:${TPM_DEVICE}"
    echo "  Using TPM device: $TPM_DEVICE"
else
    echo -e "${YELLOW}  ⚠ No hardware TPM found${NC}"
    TPM_DEVICE=""
    unset TCTI
fi

if [ -n "${TPM_DEVICE:-}" ]; then
    # Ensure tpm2-abrmd is running before TPM operations (if using tpmrm0)
    if [ -c /dev/tpmrm0 ]; then
        if ! pgrep -x tpm2-abrmd >/dev/null 2>&1; then
            echo "  Starting tpm2-abrmd resource manager..."
            if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet tpm2-abrmd 2>/dev/null; then
                sudo systemctl start tpm2-abrmd >/dev/null 2>&1 || true
                sleep 2
            elif command -v tpm2-abrmd >/dev/null 2>&1; then
                tpm2-abrmd --tcti=device 2>/dev/null &
                sleep 2
            fi
            if pgrep -x tpm2-abrmd >/dev/null 2>&1; then
                echo -e "${GREEN}  ✓ tpm2-abrmd started${NC}"
            else
                echo -e "${YELLOW}  ⚠ tpm2-abrmd may need to be started manually${NC}"
            fi
        else
            echo -e "${GREEN}  ✓ tpm2-abrmd is running${NC}"
        fi
    fi
    
    # Clear and initialize TPM state (prevents quote hangs from stale handles)
    echo "  Clearing and initializing TPM state..."
    if command -v tpm2_clear >/dev/null 2>&1 && command -v tpm2_startup >/dev/null 2>&1; then
        # Use tpmrm0 if available (resource manager), otherwise tpm0
        TPM_DEVICE_CLEAR="/dev/tpmrm0"
        if [ ! -c "$TPM_DEVICE_CLEAR" ]; then
            TPM_DEVICE_CLEAR="/dev/tpm0"
        fi
        # Clear TPM state (resets TPM to clean state, fixes quote hang issues)
        # This is safe and doesn't require platform authorization on most systems
        echo "    Clearing TPM..."
        if timeout 10 env TCTI="device:${TPM_DEVICE_CLEAR}" tpm2_clear 2>/dev/null; then
            echo -e "${GREEN}    ✓ TPM cleared${NC}"
        else
            echo -e "${YELLOW}    ⚠ TPM clear failed or timed out (continuing anyway)${NC}"
        fi
        # Initialize TPM after clear
        if env TCTI="device:${TPM_DEVICE_CLEAR}" tpm2_startup -c 2>/dev/null; then
            echo -e "${GREEN}    ✓ TPM initialized${NC}"
        else
            echo -e "${YELLOW}    ⚠ TPM initialization skipped${NC}"
        fi
    elif command -v tpm2_startup >/dev/null 2>&1; then
        # Fallback to just startup if clear is not available
        TPM_DEVICE_CLEAR="/dev/tpmrm0"
        if [ ! -c "$TPM_DEVICE_CLEAR" ]; then
            TPM_DEVICE_CLEAR="/dev/tpm0"
        fi
        echo "    Initializing TPM (tpm2_clear not found)..."
        if env TCTI="device:${TPM_DEVICE_CLEAR}" tpm2_startup -c 2>/dev/null; then
            echo -e "${GREEN}    ✓ TPM initialized${NC}"
        else
            echo -e "${YELLOW}    ⚠ TPM initialization skipped${NC}"
        fi
    else
        echo -e "${YELLOW}    ⚠ Neither tpm2_clear nor tpm2_startup found. TPM state not managed.${NC}"
    fi
    
    # Check persistent handles (should be 0 after clear)
    echo "  Checking TPM persistent handles..."
    if command -v tpm2_getcap >/dev/null 2>&1; then
        # Use timeout to prevent hanging
        HANDLES=$(timeout 5 env TCTI="device:${TPM_DEVICE}" tpm2_getcap handles-persistent 2>&1 || echo "")
        if [ -n "$HANDLES" ]; then
            HANDLE_COUNT=$(echo "$HANDLES" | grep -E "^0x[0-9a-fA-F]+" | wc -l)
            if [ "$HANDLE_COUNT" -eq 0 ]; then
                echo -e "${GREEN}    ✓ No persistent handles (clean state)${NC}"
            else
                echo "    Found $HANDLE_COUNT persistent handles:"
                echo "$HANDLES" | head -5
            fi
        else
            echo -e "${YELLOW}    ⚠ Could not check handles (command timed out or failed)${NC}"
        fi
    fi
fi

# Step 4: Setup secure directory and tmpfs
echo ""
echo -e "${CYAN}Step 4: Setting up secure directory...${NC}"
SECURE_DIR="${KEYLIME_AGENT_DIR}/secure"
SECURE_MOUNTED=false

if mountpoint -q "$SECURE_DIR" 2>/dev/null; then
    if mount | grep -q "$SECURE_DIR.*tmpfs"; then
        SECURE_MOUNTED=true
        echo -e "${GREEN}  ✓ Secure directory already mounted as tmpfs${NC}"
    fi
fi

if [ "$SECURE_MOUNTED" = false ]; then
    echo "  Setting up tmpfs mount..."
    if sudo -n true 2>/dev/null; then
        # Unmount if already mounted (but not as tmpfs)
        if mountpoint -q "$SECURE_DIR" 2>/dev/null; then
            sudo umount "$SECURE_DIR" 2>/dev/null || true
        fi
        # Create directory
        sudo mkdir -p "$SECURE_DIR" 2>/dev/null || true
        sudo chmod 700 "$SECURE_DIR" 2>/dev/null || true
        # Mount tmpfs
        if sudo mount -t tmpfs -o "size=10m,mode=0700" tmpfs "$SECURE_DIR" 2>/dev/null; then
            sudo chown -R "$(whoami):$(id -gn)" "$SECURE_DIR" 2>/dev/null || true
            echo -e "${GREEN}  ✓ tmpfs mounted successfully${NC}"
            SECURE_MOUNTED=true
        else
            echo -e "${YELLOW}  ⚠ Failed to mount tmpfs${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ sudo not available, agent will try to mount tmpfs${NC}"
    fi
fi

# Step 5: Create temporary config file
echo ""
echo -e "${CYAN}Step 5: Creating agent configuration...${NC}"
TEMP_CONFIG="/tmp/keylime-agent-debug-$$.conf"
if [ -f "${RUST_KEYLIME_DIR}/keylime-agent.conf" ]; then
    cp "${RUST_KEYLIME_DIR}/keylime-agent.conf" "$TEMP_CONFIG" 2>/dev/null || true
    # Override keylime_dir in config
    sed -i "s|^keylime_dir = .*|keylime_dir = \"$KEYLIME_AGENT_DIR\"|" "$TEMP_CONFIG" 2>/dev/null || \
    sed -i "s|keylime_dir = .*|keylime_dir = \"$KEYLIME_AGENT_DIR\"|" "$TEMP_CONFIG" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Configuration file created: $TEMP_CONFIG${NC}"
else
    echo -e "${YELLOW}  ⚠ Default config not found, using environment variables only${NC}"
fi

# Step 6: Set environment variables
echo ""
echo -e "${CYAN}Step 6: Setting environment variables...${NC}"
export KEYLIME_DIR="${KEYLIME_AGENT_DIR}"
export KEYLIME_AGENT_KEYLIME_DIR="${KEYLIME_AGENT_DIR}"
export KEYLIME_AGENT_CONFIG="${TEMP_CONFIG}"
export KEYLIME_AGENT_API_VERSIONS="2.1,2.2"
export KEYLIME_AGENT_RUN_AS="$(whoami):$(id -gn)"
export KEYLIME_AGENT_ENABLE_NETWORK_LISTENER="true"
export KEYLIME_AGENT_ENABLE_AGENT_MTLS="true"
export KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD="true"
export KEYLIME_AGENT_TRUSTED_CLIENT_CA="cv_ca/cacert.crt"
export KEYLIME_AGENT_SERVER_CERT="cv_ca/server-cert.crt"
export KEYLIME_AGENT_SERVER_KEY="cv_ca/server-private.pem"
export UNIFIED_IDENTITY_ENABLED=true
export RUST_LOG="keylime=trace,keylime_agent=trace"

if [ -n "${TCTI:-}" ]; then
    export TCTI
    echo "  TCTI: $TCTI"
fi

echo -e "${GREEN}  ✓ Environment variables set${NC}"

# Step 7: Kill any existing agent
echo ""
echo -e "${CYAN}Step 7: Stopping any existing agent...${NC}"
pkill -f "keylime_agent" 2>/dev/null || true
sleep 2
if pgrep -f "keylime_agent" >/dev/null 2>&1; then
    echo -e "${YELLOW}  ⚠ Some agent processes still running, force killing...${NC}"
    pkill -9 -f "keylime_agent" 2>/dev/null || true
    sleep 1
fi
echo -e "${GREEN}  ✓ Existing agents stopped${NC}"

# Step 8: Start agent
echo ""
echo -e "${CYAN}Step 8: Starting rust-keylime agent...${NC}"
cd "${RUST_KEYLIME_DIR}"

# Determine if we need sudo (for tmpfs mount)
NEED_SUDO=false
if [ "$SECURE_MOUNTED" = false ] && sudo -n true 2>/dev/null; then
    NEED_SUDO=true
fi

AGENT_LOG="/tmp/rust-keylime-agent-debug.log"
echo "  Log file: $AGENT_LOG"
echo "  Starting agent..."

if [ "$NEED_SUDO" = true ]; then
    echo "  Using sudo for tmpfs mount capability..."
    sudo env -i PATH="$PATH" HOME="$HOME" USER="$USER" \
        RUST_LOG="$RUST_LOG" \
        UNIFIED_IDENTITY_ENABLED=true \
        ${TCTI:+TCTI="$TCTI"} \
        KEYLIME_DIR="$KEYLIME_DIR" \
        KEYLIME_AGENT_KEYLIME_DIR="$KEYLIME_AGENT_KEYLIME_DIR" \
        KEYLIME_AGENT_CONFIG="$TEMP_CONFIG" \
        KEYLIME_AGENT_RUN_AS="$KEYLIME_AGENT_RUN_AS" \
        KEYLIME_AGENT_ENABLE_NETWORK_LISTENER="$KEYLIME_AGENT_ENABLE_NETWORK_LISTENER" \
        KEYLIME_AGENT_ENABLE_AGENT_MTLS="$KEYLIME_AGENT_ENABLE_AGENT_MTLS" \
        KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD="$KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD" \
        KEYLIME_AGENT_TRUSTED_CLIENT_CA="$KEYLIME_AGENT_TRUSTED_CLIENT_CA" \
        KEYLIME_AGENT_SERVER_CERT="$KEYLIME_AGENT_SERVER_CERT" \
        KEYLIME_AGENT_SERVER_KEY="$KEYLIME_AGENT_SERVER_KEY" \
        ./target/release/keylime_agent > "$AGENT_LOG" 2>&1 &
    AGENT_PID=$!
else
    nohup env RUST_LOG="$RUST_LOG" \
        UNIFIED_IDENTITY_ENABLED=true \
        USE_TPM2_QUOTE_DIRECT=1 \
        ${TCTI:+TCTI="$TCTI"} \
        KEYLIME_DIR="$KEYLIME_DIR" \
        KEYLIME_AGENT_KEYLIME_DIR="$KEYLIME_AGENT_KEYLIME_DIR" \
        KEYLIME_AGENT_CONFIG="$TEMP_CONFIG" \
        KEYLIME_AGENT_RUN_AS="$KEYLIME_AGENT_RUN_AS" \
        KEYLIME_AGENT_ENABLE_NETWORK_LISTENER="$KEYLIME_AGENT_ENABLE_NETWORK_LISTENER" \
        KEYLIME_AGENT_ENABLE_AGENT_MTLS="$KEYLIME_AGENT_ENABLE_AGENT_MTLS" \
        KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD="$KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD" \
        KEYLIME_AGENT_TRUSTED_CLIENT_CA="$KEYLIME_AGENT_TRUSTED_CLIENT_CA" \
        KEYLIME_AGENT_SERVER_CERT="$KEYLIME_AGENT_SERVER_CERT" \
        KEYLIME_AGENT_SERVER_KEY="$KEYLIME_AGENT_SERVER_KEY" \
        ./target/release/keylime_agent > "$AGENT_LOG" 2>&1 &
    AGENT_PID=$!
fi

echo $AGENT_PID > /tmp/rust-keylime-agent-debug.pid
echo "  Agent PID: $AGENT_PID"

# Step 9: Wait for agent to start
echo ""
echo -e "${CYAN}Step 9: Waiting for agent to start...${NC}"
AGENT_STARTED=false
for i in {1..30}; do
    if lsof -i :9002 >/dev/null 2>&1; then
        AGENT_STARTED=true
        echo -e "${GREEN}  ✓ Agent is listening on port 9002${NC}"
        break
    fi
    if ! ps -p $AGENT_PID >/dev/null 2>&1; then
        echo -e "${RED}  ✗ Agent process died${NC}"
        echo "  Last 20 lines of log:"
        tail -20 "$AGENT_LOG"
        exit 1
    fi
    sleep 1
done

if [ "$AGENT_STARTED" = false ]; then
    echo -e "${RED}  ✗ Agent failed to start on port 9002${NC}"
    echo "  Last 30 lines of log:"
    tail -30 "$AGENT_LOG"
    exit 1
fi

# Step 10: Display testing information
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Agent Started Successfully!                                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Agent Information:"
echo "  PID: $AGENT_PID"
echo "  Log: $AGENT_LOG"
echo "  Port: 9002"
echo "  UUID: $(grep -oP 'Agent UUID: \K[0-9a-f-]+' "$AGENT_LOG" | tail -1 || echo 'checking...')"
echo ""
echo "Testing Commands:"
echo ""
echo "1. Test mTLS handshake:"
echo "   openssl s_client -connect localhost:9002 \\"
echo "     -cert ${KEYLIME_DIR}/cv_ca/client-cert.crt \\"
echo "     -key ${KEYLIME_DIR}/cv_ca/client-private.pem \\"
echo "     -CAfile ${KEYLIME_AGENT_DIR}/cv_ca/cacert.crt"
echo ""
echo "2. Test quote endpoint (with timeout):"
echo "   curl --max-time 10 -v \\"
echo "     --cert ${KEYLIME_DIR}/cv_ca/client-cert.crt \\"
echo "     --key ${KEYLIME_DIR}/cv_ca/client-private.pem \\"
echo "     --cacert ${KEYLIME_AGENT_DIR}/cv_ca/cacert.crt \\"
echo "     'https://localhost:9002/v2.2/quotes/identity?nonce=\$(uuidgen | tr -d \"-\")'"
echo ""
echo "3. Trace agent with strace (requires sudo):"
echo "   sudo strace -f -e trace=read,write,poll,select,ioctl,epoll_wait \\"
echo "     -p $AGENT_PID -o /tmp/agent-strace.log"
echo ""
echo "4. Watch agent log in real-time:"
echo "   tail -f $AGENT_LOG"
echo ""
echo "5. Stop agent:"
echo "   kill $AGENT_PID"
echo "   # or: pkill -f keylime_agent"
echo ""
echo -e "${CYAN}Agent is running. Press Ctrl+C to stop monitoring (agent will continue).${NC}"
echo ""

# Monitor agent (optional - can be interrupted)
trap "echo ''; echo 'Monitoring stopped. Agent PID: $AGENT_PID'; echo 'Use: kill $AGENT_PID to stop agent'; exit 0" INT TERM

# Keep script running and monitor agent
while ps -p $AGENT_PID >/dev/null 2>&1; do
    sleep 5
done

echo -e "${RED}Agent process has stopped${NC}"
tail -20 "$AGENT_LOG"

