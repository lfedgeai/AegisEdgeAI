#!/bin/bash
# Unified-Identity - Phase 1 & Phase 2: Shared startup script for SPIRE Server, Agent, and Real Keylime Verifier (Phase 2)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PHASE2_DIR="${PROJECT_ROOT}/../code-rollout-phase-2"

SPIRE_DIR="${PROJECT_ROOT}/spire"
KEYLIME_DIR="${PHASE2_DIR}/keylime"

SERVER_CONFIG_DEFAULT="${PROJECT_ROOT}/python-app-demo/spire-server-phase2.conf"
AGENT_CONFIG_DEFAULT="${PROJECT_ROOT}/python-app-demo/spire-agent.conf"

SERVER_CONFIG="${SERVER_CONFIG:-$SERVER_CONFIG_DEFAULT}"
AGENT_CONFIG="${AGENT_CONFIG:-$AGENT_CONFIG_DEFAULT}"
AGENT_SPIFFE_ID="${AGENT_SPIFFE_ID:-spiffe://example.org/host/python-demo-agent}"

# Keylime Verifier configuration
KEYLIME_VERIFIER_PORT="${KEYLIME_VERIFIER_PORT:-8881}"
# Use minimal config from Phase 2 if available, otherwise use phase2 config
if [ -f "${PHASE2_DIR}/verifier.conf.minimal" ]; then
    KEYLIME_VERIFIER_CONFIG="${KEYLIME_VERIFIER_CONFIG:-${PHASE2_DIR}/verifier.conf.minimal}"
else
    KEYLIME_VERIFIER_CONFIG="${KEYLIME_VERIFIER_CONFIG:-${PHASE2_DIR}/verifier.conf.phase2}"
fi

QUIET=${QUIET:-0}

log() {
    if [ "$QUIET" -eq 0 ]; then
        echo "$1"
    fi
}

log "Unified-Identity - Phase 1 & Phase 2: Starting SPIRE stack with Real Keylime Verifier"
log ""

# Clean up any existing processes
log "Cleaning up any existing SPIRE and Keylime processes..."
pkill -f "spire-server" >/dev/null 2>&1 || true
pkill -f "spire-agent" >/dev/null 2>&1 || true
pkill -f "keylime_verifier" >/dev/null 2>&1 || true
pkill -f "keylime-stub" >/dev/null 2>&1 || true
pkill -f "python.*keylime" >/dev/null 2>&1 || true

# Kill any process using Keylime ports
if command -v lsof >/dev/null 2>&1; then
    lsof -ti:${KEYLIME_VERIFIER_PORT} | xargs kill -9 >/dev/null 2>&1 || true
    lsof -ti:8888 | xargs kill -9 >/dev/null 2>&1 || true
fi
if command -v fuser >/dev/null 2>&1; then
    fuser -k ${KEYLIME_VERIFIER_PORT}/tcp >/dev/null 2>&1 || true
    fuser -k 8888/tcp >/dev/null 2>&1 || true
fi

sleep 2

# Clean up old sockets and data
log "Cleaning up old sockets and data..."
rm -rf /tmp/spire-server /tmp/spire-agent
rm -f /tmp/spire-server.pid /tmp/spire-agent.pid /tmp/keylime-verifier.pid
sudo rm -rf /opt/spire/data 2>/dev/null || true
sudo mkdir -p /opt/spire/data/server /opt/spire/data/agent
sudo chown -R "$(whoami)":"$(whoami)" /opt/spire/data 2>/dev/null || true

# CRITICAL: Start Keylime Verifier BEFORE SPIRE Server
# SPIRE Server needs Keylime Verifier to be running and accessible
log "Starting Keylime Verifier (Phase 2) - MUST START BEFORE SPIRE..."
if [ ! -d "${KEYLIME_DIR}" ]; then
    echo "Error: Keylime directory not found at ${KEYLIME_DIR}"
    echo "Please ensure Phase 2 implementation is available"
    exit 1
fi

# Check if verifier config exists
if [ ! -f "${KEYLIME_VERIFIER_CONFIG}" ]; then
    log "⚠ Warning: Keylime Verifier config not found at ${KEYLIME_VERIFIER_CONFIG}"
    log "  Using minimal config from Phase 2..."
    # Use the minimal config from Phase 2 if available
    PHASE2_MINIMAL_CONFIG="${PHASE2_DIR}/verifier.conf.minimal"
    if [ -f "${PHASE2_MINIMAL_CONFIG}" ]; then
        log "  Copying ${PHASE2_MINIMAL_CONFIG} to ${KEYLIME_VERIFIER_CONFIG}"
        mkdir -p "$(dirname "${KEYLIME_VERIFIER_CONFIG}")"
        cp "${PHASE2_MINIMAL_CONFIG}" "${KEYLIME_VERIFIER_CONFIG}"
    else
        log "  Creating default config..."
        mkdir -p "$(dirname "${KEYLIME_VERIFIER_CONFIG}")"
        cat > "${KEYLIME_VERIFIER_CONFIG}" << EOF
[verifier]
unified_identity_enabled = true
unified_identity_default_geolocation = Spain: N40.4168, W3.7038
unified_identity_default_integrity = passed_all_checks
unified_identity_default_gpu_status = healthy
unified_identity_default_gpu_utilization = 15.0
unified_identity_default_gpu_memory = 10240
EOF
    fi
fi

# Verify unified_identity_enabled is set to true
if ! grep -q "unified_identity_enabled = true" "${KEYLIME_VERIFIER_CONFIG}"; then
    log "⚠ Warning: unified_identity_enabled is not set to true in config"
    log "  Adding unified_identity_enabled = true to config..."
    if ! grep -q "^\[verifier\]" "${KEYLIME_VERIFIER_CONFIG}"; then
        echo "[verifier]" >> "${KEYLIME_VERIFIER_CONFIG}"
    fi
    if grep -q "unified_identity_enabled" "${KEYLIME_VERIFIER_CONFIG}"; then
        sed -i 's/^unified_identity_enabled.*/unified_identity_enabled = true/' "${KEYLIME_VERIFIER_CONFIG}"
    else
        echo "unified_identity_enabled = true" >> "${KEYLIME_VERIFIER_CONFIG}"
    fi
fi
log "✓ Verified unified_identity_enabled = true in config"

# Check how to start Keylime Verifier
cd "${KEYLIME_DIR}"

# Set environment variables to use our config
export KEYLIME_VERIFIER_CONFIG="${KEYLIME_VERIFIER_CONFIG}"
export KEYLIME_TEST=on
export KEYLIME_DIR="${KEYLIME_DIR}"

# Try different methods to start Keylime Verifier
if command -v keylime_verifier >/dev/null 2>&1; then
    # Use system keylime_verifier command
    log "  Using system keylime_verifier command"
    keylime_verifier > /tmp/keylime-verifier.log 2>&1 &
elif [ -f "keylime/cmd/verifier.py" ]; then
    # Use Keylime's verifier command module
    log "  Using keylime.cmd.verifier module"
    python3 -m keylime.cmd.verifier > /tmp/keylime-verifier.log 2>&1 &
elif [ -f "keylime/cloud_verifier_tornado.py" ]; then
    # Use cloud_verifier_tornado directly (fallback)
    log "  Using cloud_verifier_tornado.py directly"
    python3 -c "from keylime.cloud_verifier_tornado import main; main()" > /tmp/keylime-verifier.log 2>&1 &
else
    echo "Error: Keylime Verifier not found"
    echo "  Tried: keylime_verifier command, keylime/cmd/verifier.py, keylime/cloud_verifier_tornado.py"
    exit 1
fi

KEYLIME_PID=$!
echo $KEYLIME_PID > /tmp/keylime-verifier.pid
sleep 3

# Check if Keylime Verifier is running
if ! ps -p $KEYLIME_PID > /dev/null 2>&1; then
    echo "Error: Keylime Verifier failed to start"
    echo "Check logs: /tmp/keylime-verifier.log"
    tail -20 /tmp/keylime-verifier.log 2>&1 | head -20
    exit 1
fi

log "✓ Keylime Verifier started (PID: $KEYLIME_PID, Port: ${KEYLIME_VERIFIER_PORT})"
if [ "$QUIET" -eq 0 ] && [ -f /tmp/keylime-verifier.log ]; then
    log "  Initial log:"
    tail -5 /tmp/keylime-verifier.log | sed 's/^/    /' || true
fi

# Wait for Keylime Verifier to be ready (CRITICAL: Must be ready before SPIRE starts)
log "Waiting for Keylime Verifier to be ready (required before SPIRE starts)..."
VERIFIER_READY=false
for i in {1..60}; do
    # Try both HTTP and HTTPS (Keylime uses HTTPS by default)
    if curl -s -k "https://localhost:${KEYLIME_VERIFIER_PORT}/version" >/dev/null 2>&1 || \
       curl -s -k "https://localhost:${KEYLIME_VERIFIER_PORT}/v2.4/version" >/dev/null 2>&1 || \
       curl -s "http://localhost:${KEYLIME_VERIFIER_PORT}/version" >/dev/null 2>&1 || \
       curl -s "http://localhost:${KEYLIME_VERIFIER_PORT}/health" >/dev/null 2>&1; then
        log "✓ Keylime Verifier is ready on port ${KEYLIME_VERIFIER_PORT}"
        VERIFIER_READY=true
        break
    fi
    if [ $((i % 10)) -eq 0 ]; then
        log "  Still waiting for Keylime Verifier... ($i/60 seconds)"
    fi
    sleep 1
done

if [ "$VERIFIER_READY" = false ]; then
    log "⚠ Warning: Keylime Verifier may not be fully ready, but continuing..."
    log "  Verifier process is running, endpoint may take longer to become available"
fi

# CRITICAL: Set KEYLIME_VERIFIER_URL before starting SPIRE Server
# This ensures SPIRE Server uses the correct port (8881, not 8888)
# Use HTTPS since Keylime Verifier uses TLS by default
export KEYLIME_VERIFIER_URL="https://localhost:${KEYLIME_VERIFIER_PORT}"
log "✓ Set KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL} for SPIRE Server (HTTPS)"

# Initialize SPIRE Server (Keylime Verifier must already be running)
log "Initializing SPIRE Server (Keylime Verifier should already be running)..."
mkdir -p /tmp/spire-server/private

# CRITICAL: Ensure KEYLIME_VERIFIER_URL is set to correct port (8881) and HTTPS
# This must be set before SPIRE Server starts, as it reads it at initialization
# Keylime Verifier uses HTTPS by default, so URL must use https://
if [ -z "${KEYLIME_VERIFIER_URL:-}" ]; then
    export KEYLIME_VERIFIER_URL="https://localhost:${KEYLIME_VERIFIER_PORT}"
    log "✓ Set KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL} (Real Keylime Verifier - Phase 2, HTTPS)"
else
    # Verify it's pointing to the correct port and using HTTPS
    if [[ "${KEYLIME_VERIFIER_URL}" != *":${KEYLIME_VERIFIER_PORT}"* ]]; then
        log "⚠ Warning: KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL} doesn't match expected port ${KEYLIME_VERIFIER_PORT}"
        export KEYLIME_VERIFIER_URL="https://localhost:${KEYLIME_VERIFIER_PORT}"
        log "✓ Corrected KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL}"
    elif [[ "${KEYLIME_VERIFIER_URL}" != "https://"* ]]; then
        log "⚠ Warning: KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL} should use HTTPS (Keylime Verifier uses TLS)"
        # Convert http:// to https://
        export KEYLIME_VERIFIER_URL="${KEYLIME_VERIFIER_URL/http:\/\//https:\/\/}"
        log "✓ Corrected KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL}"
    else
        log "✓ Using KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL}"
    fi
fi

# Check if server config exists, if not create one
if [ ! -f "$SERVER_CONFIG" ]; then
    log "⚠ Server config not found, creating default..."
    mkdir -p "$(dirname "$SERVER_CONFIG")"
    # Create server config that points to real Keylime
    cat > "$SERVER_CONFIG" << 'EOF'
# Unified-Identity - Phase 1 & Phase 2: SPIRE Server configuration with Real Keylime Verifier
server {
    bind_address = "0.0.0.0"
    bind_port = 8081
    trust_domain = "example.org"
    data_dir = "/opt/spire/data/server"
    log_level = "DEBUG"
    default_x509_svid_ttl = "1h"
    ca_ttl = "24h"
    
    ca_subject {
        country = ["US"]
        organization = ["SPIFFE"]
        common_name = ""
    }
    
    socket_path = "/tmp/spire-server/private/api.sock"
    
    experimental {
        feature_flags = ["Unified-Identity"]
    }
}

plugins {
    DataStore "sql" {
        plugin_data {
            database_type = "sqlite3"
            connection_string = "/opt/spire/data/server/datastore.sqlite3"
        }
    }

    NodeAttestor "join_token" {
        plugin_data {
        }
    }

    KeyManager "disk" {
        plugin_data {
            keys_path = "/opt/spire/data/server/keys.json"
        }
    }
}
EOF
fi

"${SPIRE_DIR}/bin/spire-server" validate -config "$SERVER_CONFIG"

# CRITICAL: Start SPIRE Server with KEYLIME_VERIFIER_URL explicitly set
# This ensures the environment variable is inherited by the background process
# The variable must be set to https://localhost:8881 (not 8888, and must use HTTPS)
# Force set it to the correct value to override any existing value
KEYLIME_VERIFIER_URL="https://localhost:${KEYLIME_VERIFIER_PORT}"
export KEYLIME_VERIFIER_URL
log "Starting SPIRE Server with KEYLIME_VERIFIER_URL=${KEYLIME_VERIFIER_URL}..."
log "  (This MUST be port ${KEYLIME_VERIFIER_PORT}, not 8888, and MUST use HTTPS)"
KEYLIME_VERIFIER_URL="${KEYLIME_VERIFIER_URL}" "${SPIRE_DIR}/bin/spire-server" run -config "$SERVER_CONFIG" > /tmp/spire-server.log 2>&1 &
SPIRE_SERVER_PID=$!
echo $SPIRE_SERVER_PID > /tmp/spire-server.pid
sleep 3
log "✓ SPIRE Server started (PID: $SPIRE_SERVER_PID)"
if [ "$QUIET" -eq 0 ] && [ -f /tmp/spire-server.log ]; then
    log "  Initial log:"
    tail -2 /tmp/spire-server.log | sed 's/^/    /' || true
fi

# Wait for server to be ready
log "Waiting for SPIRE Server to be ready..."
for _ in {1..30}; do
    if [ -S /tmp/spire-server/private/api.sock ]; then
        if "${SPIRE_DIR}/bin/spire-server" healthcheck -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1; then
            break
        fi
    fi
    sleep 1
done

if [ ! -S /tmp/spire-server/private/api.sock ]; then
    echo "Error: SPIRE Server socket not ready"
    exit 1
fi
log "✓ SPIRE Server is ready"

# Create join token
log "Creating join token..."
JOIN_TOKEN=$("${SPIRE_DIR}/bin/spire-server" token generate \
    -spiffeID "$AGENT_SPIFFE_ID" \
    -socketPath /tmp/spire-server/private/api.sock \
    | grep "Token:" | awk '{print $2}')

if [ -z "$JOIN_TOKEN" ]; then
    echo "Error: Failed to generate join token"
    exit 1
fi
log "✓ Join token generated: $JOIN_TOKEN"

# Fetch trust bundle
log "Fetching trust bundle for agent..."
"${SPIRE_DIR}/bin/spire-server" bundle show -format pem -socketPath /tmp/spire-server/private/api.sock > /tmp/bundle.pem
log "✓ Trust bundle saved to /tmp/bundle.pem"

# Start SPIRE Agent
log "Starting SPIRE Agent..."
mkdir -p /tmp/spire-agent/public
"${SPIRE_DIR}/bin/spire-agent" validate -config "$AGENT_CONFIG"
"${SPIRE_DIR}/bin/spire-agent" run \
    -config "$AGENT_CONFIG" \
    -joinToken "$JOIN_TOKEN" > /tmp/spire-agent.log 2>&1 &
SPIRE_AGENT_PID=$!
echo $SPIRE_AGENT_PID > /tmp/spire-agent.pid
sleep 3
log "✓ SPIRE Agent started (PID: $SPIRE_AGENT_PID)"
if [ "$QUIET" -eq 0 ] && [ -f /tmp/spire-agent.log ]; then
    log "  Initial log:"
    tail -2 /tmp/spire-agent.log | sed 's/^/    /' || true
fi

# Wait for agent socket
log "Waiting for SPIRE Agent socket..."
SOCKET_READY=false
for i in {1..60}; do
    if [ -S /tmp/spire-agent/public/api.sock ]; then
        SOCKET_READY=true
        break
    fi
    if [ $((i % 5)) -eq 0 ]; then
        log "  Still waiting... ($i/60)"
        if ! ps -p $SPIRE_AGENT_PID > /dev/null 2>&1; then
            echo "  ⚠ Agent process died, checking logs..."
            tail -20 /tmp/spire-agent.log 2>&1 | head -20
            exit 1
        fi
    fi
    sleep 1
done

if [ "$SOCKET_READY" != "true" ]; then
    echo "Error: SPIRE Agent socket not ready after 60 seconds"
    tail -30 /tmp/spire-agent.log 2>&1 | head -30
    exit 1
fi
log "✓ SPIRE Agent socket ready: /tmp/spire-agent/public/api.sock"

if [ "$QUIET" -eq 0 ]; then
    echo ""
    printf '=%.0s' {1..70}
    echo ""
    echo "SPIRE Stack with Real Keylime Verifier (Phase 2) Ready"
    printf '=%.0s' {1..70}
    echo ""
    echo "Server PID: $SPIRE_SERVER_PID"
    echo "Agent PID: $SPIRE_AGENT_PID"
    echo "Keylime Verifier PID: $KEYLIME_PID (Port: ${KEYLIME_VERIFIER_PORT})"
    echo ""
    echo "⚠ NOTE: SPIRE Server is configured to use Keylime at http://localhost:${KEYLIME_VERIFIER_PORT}"
    echo "  If Keylime Verifier uses a different port, update SPIRE server.go or use environment variable"
    echo ""
    echo "To stop the stack: ${PROJECT_ROOT}/scripts/stop-unified-identity-phase2.sh"
fi

