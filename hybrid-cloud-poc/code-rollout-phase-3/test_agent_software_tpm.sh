#!/usr/bin/env bash
# Test rust-keylime agent with software TPM (swtpm) to isolate hardware vs software issues
# If swtpm works, the issue is with the hardware TPM
# If swtpm also hangs, the issue is in the agent code

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE2_DIR="${SCRIPT_DIR}/../code-rollout-phase-2"
RUST_KEYLIME_DIR="${PHASE2_DIR}/rust-keylime"
KEYLIME_AGENT_DIR="/tmp/keylime-agent-swtpm"
SWTPM_DIR="/tmp/swtpm"
SWTPM_SOCKET="${SWTPM_DIR}/swtpm-sock"
SWTPM_STATE="${SWTPM_DIR}/tpm-state"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Testing Agent with Software TPM (swtpm)                       ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Initial cleanup: Stop any existing swtpm and agent processes
echo -e "${CYAN}Initial cleanup: Stopping existing swtpm and agent processes...${NC}"

# Check and stop swtpm processes
SWTPM_RUNNING=$(pgrep -f "swtpm" 2>/dev/null | wc -l) || SWTPM_RUNNING=0
if [ "$SWTPM_RUNNING" -gt 0 ]; then
    echo "  Stopping existing swtpm processes..."
    pkill -f "swtpm" 2>/dev/null || true
    sleep 2
    SWTPM_STILL_RUNNING=$(pgrep -f "swtpm" 2>/dev/null | wc -l) || SWTPM_STILL_RUNNING=0
    if [ "$SWTPM_STILL_RUNNING" -gt 0 ]; then
        echo "  Force killing remaining swtpm processes..."
        pkill -9 -f "swtpm" 2>/dev/null || true
        sleep 1
    fi
    echo -e "${GREEN}  ✓ Existing swtpm processes stopped${NC}"
else
    echo -e "${GREEN}  ✓ No existing swtpm processes${NC}"
fi

# Check and stop agent processes
AGENT_RUNNING=$(pgrep -f "keylime_agent" 2>/dev/null | wc -l) || AGENT_RUNNING=0
if [ "$AGENT_RUNNING" -gt 0 ]; then
    echo "  Stopping existing agent processes..."
    pkill -f "keylime_agent" 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}  ✓ Existing agent processes stopped${NC}"
else
    echo -e "${GREEN}  ✓ No existing agent processes${NC}"
fi

# Remove old swtpm socket if it exists
if [ -S "$SWTPM_SOCKET" ] || [ -f "$SWTPM_SOCKET" ]; then
    echo "  Removing old swtpm socket..."
    rm -f "$SWTPM_SOCKET" 2>/dev/null || true
    echo -e "${GREEN}  ✓ Old socket removed${NC}"
fi
echo ""

# Cleanup function
cleanup() {
    # Only run cleanup if we've actually started something
    if [ -z "${CLEANUP_NEEDED:-}" ]; then
        return 0
    fi
    echo ""
    echo -e "${CYAN}Cleaning up...${NC}"
    pkill -f "keylime_agent" >/dev/null 2>&1 || true
    pkill -f "^swtpm " >/dev/null 2>&1 || true
    sleep 1
    if mountpoint -q "${KEYLIME_AGENT_DIR}/secure" 2>/dev/null; then
        sudo umount "${KEYLIME_AGENT_DIR}/secure" 2>/dev/null || true
    fi
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}
# Set trap only after we've started processes
trap cleanup EXIT INT TERM

# Step 1: Check prerequisites
echo -e "${CYAN}Step 1: Checking prerequisites...${NC}"
if ! command -v swtpm >/dev/null 2>&1; then
    echo -e "${RED}✗ swtpm not found. Install with: sudo apt-get install swtpm swtpm-tools${NC}"
    exit 1
fi
echo -e "${GREEN}✓ swtpm is installed${NC}"

if [ ! -f "${RUST_KEYLIME_DIR}/target/release/keylime_agent" ]; then
    echo -e "${RED}✗ Agent binary not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Agent binary found${NC}"

# Step 2: Setup swtpm
echo ""
echo -e "${CYAN}Step 2: Setting up software TPM (swtpm)...${NC}"
mkdir -p "$SWTPM_DIR" "$SWTPM_STATE" 2>/dev/null || true

# Start swtpm (cleanup already done at beginning)
# Use TCP interface - swtpm needs two ports:
#   - Port 2321 for TPM commands
#   - Port 2322 for control commands
echo "  Starting swtpm on TCP ports 2321 (TPM) and 2322 (control)..."
if swtpm socket \
    --tpmstate dir="$SWTPM_STATE" \
    --ctrl type=tcp,port=2322 \
    --server type=tcp,port=2321 \
    --tpm2 \
    --flags startup-clear \
    --log level=20 \
    --daemon 2>&1 | tee /tmp/swtpm-startup.log; then
    SWTPM_START_EXIT=$?
else
    SWTPM_START_EXIT=$?
fi

sleep 3
if pgrep -f "swtpm" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ swtpm started${NC}"
    echo "  Listening on TCP port 2321"
    echo "  TPM auto-initialized with startup-clear flag"
    
    # Give swtpm a moment to fully initialize
    sleep 2
    
    # Verify TPM is responsive
    echo "  Verifying TPM is responsive..."
    if env TCTI="swtpm:host=127.0.0.1,port=2321" tpm2_getcap properties-fixed 2>/dev/null | head -3 >/dev/null; then
        echo -e "${GREEN}  ✓ TPM is responsive and ready${NC}"
    else
        echo -e "${YELLOW}  ⚠ TPM verification failed (agent may still work)${NC}"
    fi
    
    # Mark that cleanup is needed
    export CLEANUP_NEEDED=1
else
    echo -e "${RED}✗ Failed to start swtpm${NC}"
    if [ -f /tmp/swtpm-startup.log ]; then
        echo "  Error log:"
        cat /tmp/swtpm-startup.log
    fi
    exit 1
fi

# Step 3: Setup agent directories
echo ""
echo -e "${CYAN}Step 3: Setting up agent directories...${NC}"
rm -rf "$KEYLIME_AGENT_DIR" 2>/dev/null || true
mkdir -p "$KEYLIME_AGENT_DIR" 2>/dev/null || true

# Copy or generate certificates
TLS_DIR="${PHASE2_DIR}/keylime/cv_ca"
if [ -d "$TLS_DIR" ] && [ -f "$TLS_DIR/cacert.crt" ] && [ -f "$TLS_DIR/server-cert.crt" ] && [ -f "$TLS_DIR/server-private.pem" ]; then
    echo "  Copying existing certificates..."
    mkdir -p "${KEYLIME_AGENT_DIR}/cv_ca" 2>/dev/null || true
    cp -a "${TLS_DIR}/." "${KEYLIME_AGENT_DIR}/cv_ca/" 2>/dev/null || true
    echo -e "${GREEN}✓ Certificates copied${NC}"
else
    echo "  Certificates not found, generating them..."
    # Use the same certificate generation logic as start_agent_debug.sh
    PYTHON_KEYLIME_DIR="${PHASE2_DIR}/keylime"
    KEYLIME_DIR="${PYTHON_KEYLIME_DIR}"
    VERIFIER_CONFIG="${PHASE2_DIR}/verifier.conf.minimal"
    
    if [ ! -d "${PYTHON_KEYLIME_DIR}" ]; then
        echo -e "${RED}  ✗ Python Keylime directory not found${NC}"
        exit 1
    fi
    
    WORK_DIR="${KEYLIME_DIR}"
    mkdir -p "$TLS_DIR" 2>/dev/null || true
    chmod 700 "$TLS_DIR" 2>/dev/null || true
    
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

os.environ['KEYLIME_DIR'] = '${KEYLIME_DIR_VAR}'
sys.path.insert(0, '${PYTHON_KEYLIME_DIR}')

if '${VERIFIER_CONFIG_ABS_VAR}':
    os.environ['KEYLIME_VERIFIER_CONFIG'] = '${VERIFIER_CONFIG_ABS_VAR}'
    os.environ['KEYLIME_CA_CONFIG'] = '${VERIFIER_CONFIG_ABS_VAR}'
    os.environ['KEYLIME_CONFIG'] = '${VERIFIER_CONFIG_ABS_VAR}'
os.environ['KEYLIME_TEST'] = 'on'

from keylime import config, ca_util, keylime_logging

logger = keylime_logging.init_logging("verifier")
tls_dir = os.path.join('${KEYLIME_DIR_VAR}', 'cv_ca')
original_cwd = os.getcwd()
os.chdir(tls_dir)

try:
    ca_util.read_password("")
    print("  Generating CA...")
    ca_util.cmd_init(tls_dir)
    print("  ✓ CA certificate generated")
    print("  Generating server certificate...")
    ca_util.cmd_mkcert(tls_dir, 'server', password=None)
    print("  ✓ Server certificate generated")
    print("  Generating client certificate...")
    ca_util.cmd_mkcert(tls_dir, 'client', password=None)
    print("  ✓ Client certificate generated")
except Exception as e:
    print(f"  ✗ Failed to generate certificates: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
finally:
    os.chdir(original_cwd)
PYTHON_EOF
    
    if [ $? -eq 0 ] && [ -f "$TLS_DIR/cacert.crt" ]; then
        mkdir -p "${KEYLIME_AGENT_DIR}/cv_ca" 2>/dev/null || true
        cp -a "${TLS_DIR}/." "${KEYLIME_AGENT_DIR}/cv_ca/" 2>/dev/null || true
        echo -e "${GREEN}✓ Certificates generated and copied${NC}"
    else
        echo -e "${RED}  ✗ Failed to generate certificates${NC}"
        exit 1
    fi
fi

# Setup secure directory
SECURE_DIR="${KEYLIME_AGENT_DIR}/secure"
sudo mkdir -p "$SECURE_DIR" 2>/dev/null || true
sudo chmod 700 "$SECURE_DIR" 2>/dev/null || true
if sudo mount -t tmpfs -o "size=10m,mode=0700" tmpfs "$SECURE_DIR" 2>/dev/null; then
    sudo chown -R "$(whoami):$(id -gn)" "$SECURE_DIR" 2>/dev/null || true
    echo -e "${GREEN}✓ Secure directory mounted${NC}"
else
    echo -e "${YELLOW}⚠ Failed to mount secure directory${NC}"
fi

# Step 4: Start agent with swtpm
echo ""
echo -e "${CYAN}Step 4: Starting agent with swtpm...${NC}"

# Set TCTI to use swtpm TCP interface (port 2321)
export TCTI="swtpm:host=127.0.0.1,port=2321"
export KEYLIME_DIR="${KEYLIME_AGENT_DIR}"
export KEYLIME_AGENT_KEYLIME_DIR="${KEYLIME_AGENT_DIR}"
export KEYLIME_AGENT_API_VERSIONS="2.1,2.2"
export KEYLIME_AGENT_ENABLE_NETWORK_LISTENER="true"
export KEYLIME_AGENT_ENABLE_AGENT_MTLS="true"
export KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD="true"
export KEYLIME_AGENT_TRUSTED_CLIENT_CA="cv_ca/cacert.crt"
export KEYLIME_AGENT_SERVER_CERT="cv_ca/server-cert.crt"
export KEYLIME_AGENT_SERVER_KEY="cv_ca/server-private.pem"
export RUST_LOG="keylime=info,keylime_agent=info"

AGENT_LOG="/tmp/rust-keylime-agent-swtpm.log"
echo "  Starting agent with TCTI: $TCTI"
cd "${RUST_KEYLIME_DIR}"

nohup env TCTI="$TCTI" \
    KEYLIME_DIR="$KEYLIME_DIR" \
    KEYLIME_AGENT_KEYLIME_DIR="$KEYLIME_AGENT_KEYLIME_DIR" \
    KEYLIME_AGENT_API_VERSIONS="$KEYLIME_AGENT_API_VERSIONS" \
    KEYLIME_AGENT_ENABLE_NETWORK_LISTENER="$KEYLIME_AGENT_ENABLE_NETWORK_LISTENER" \
    KEYLIME_AGENT_ENABLE_AGENT_MTLS="$KEYLIME_AGENT_ENABLE_AGENT_MTLS" \
    KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD="$KEYLIME_AGENT_ENABLE_INSECURE_PAYLOAD" \
    KEYLIME_AGENT_TRUSTED_CLIENT_CA="$KEYLIME_AGENT_TRUSTED_CLIENT_CA" \
    KEYLIME_AGENT_SERVER_CERT="$KEYLIME_AGENT_SERVER_CERT" \
    KEYLIME_AGENT_SERVER_KEY="$KEYLIME_AGENT_SERVER_KEY" \
    USE_TPM2_QUOTE_DIRECT=1 \
    RUST_LOG="$RUST_LOG" \
    ./target/release/keylime_agent > "$AGENT_LOG" 2>&1 &

AGENT_PID=$!
echo "  Agent PID: $AGENT_PID"

# Step 5: Wait for agent to start
echo ""
echo -e "${CYAN}Step 5: Waiting for agent to start...${NC}"
AGENT_STARTED=false
for i in {1..30}; do
    if lsof -i :9002 >/dev/null 2>&1; then
        AGENT_STARTED=true
        echo -e "${GREEN}✓ Agent is listening on port 9002${NC}"
        break
    fi
    if ! ps -p $AGENT_PID >/dev/null 2>&1; then
        echo -e "${RED}✗ Agent process died${NC}"
        echo "  Last 20 lines of log:"
        tail -20 "$AGENT_LOG"
        exit 1
    fi
    sleep 1
done

if [ "$AGENT_STARTED" = false ]; then
    echo -e "${RED}✗ Agent failed to start${NC}"
    tail -30 "$AGENT_LOG"
    exit 1
fi

# Step 6: Test quote endpoint
echo ""
echo -e "${CYAN}Step 6: Testing quote endpoint with swtpm...${NC}"
CLIENT_CERT="${KEYLIME_AGENT_DIR}/cv_ca/client-cert.crt"
CLIENT_KEY="${KEYLIME_AGENT_DIR}/cv_ca/client-private.pem"
CA_CERT="${KEYLIME_AGENT_DIR}/cv_ca/cacert.crt"
NONCE=$(uuidgen | tr -d '-')
echo "  Nonce: $NONCE"
echo "  Making quote request (timeout: 15 seconds)..."

QUOTE_RESPONSE="/tmp/quote-response-swtpm.json"
timeout 15 curl --max-time 12 -s \
    --cert "$CLIENT_CERT" \
    --key "$CLIENT_KEY" \
    --cacert "$CA_CERT" \
    --insecure \
    "https://127.0.0.1:9002/v2.2/quotes/identity?nonce=$NONCE" \
    > "$QUOTE_RESPONSE" 2>&1

QUOTE_EXIT=$?

echo ""
if [ -f "$QUOTE_RESPONSE" ] && [ -s "$QUOTE_RESPONSE" ]; then
    if grep -q '"code": 200' "$QUOTE_RESPONSE" 2>/dev/null; then
        echo -e "${GREEN}✓✓✓ SUCCESS: Quote worked with swtpm!${NC}"
        echo ""
        echo "This indicates the issue is with the HARDWARE TPM, not the agent code."
        echo ""
        echo "Quote response:"
        cat "$QUOTE_RESPONSE" | python3 -m json.tool 2>/dev/null | head -40 || cat "$QUOTE_RESPONSE" | head -30
    elif grep -q '"code": 500' "$QUOTE_RESPONSE" 2>/dev/null; then
        echo -e "${YELLOW}⚠ Quote returned error (HTTP 500)${NC}"
        cat "$QUOTE_RESPONSE" | head -20
    else
        echo -e "${YELLOW}? Unexpected response:${NC}"
        cat "$QUOTE_RESPONSE" | head -20
    fi
elif [ $QUOTE_EXIT -eq 124 ] || [ $QUOTE_EXIT -eq 28 ]; then
    echo -e "${RED}✗ Quote request timed out (also hangs with swtpm)${NC}"
    echo ""
    echo "This indicates the issue is in the AGENT CODE, not the hardware TPM."
    echo ""
    echo "Checking agent log..."
    tail -30 "$AGENT_LOG" | grep -E "(quote|Quote|Error|ERROR)" | tail -10
else
    echo -e "${RED}✗ Quote request failed${NC}"
    cat "$QUOTE_RESPONSE" 2>/dev/null || echo "No response received"
fi

echo ""
echo -e "${CYAN}Test complete. Agent and swtpm will be cleaned up on exit.${NC}"

