#!/bin/bash
# Unified-Identity - Phase 1: Shared startup script for SPIRE Server, Agent, and Keylime Stub

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SPIRE_DIR="${PROJECT_ROOT}/spire"
KEYLIME_STUB_DIR="${PROJECT_ROOT}/keylime-stub"

SERVER_CONFIG_DEFAULT="${PROJECT_ROOT}/python-app-demo/spire-server.conf"
AGENT_CONFIG_DEFAULT="${PROJECT_ROOT}/python-app-demo/spire-agent.conf"

SERVER_CONFIG="${SERVER_CONFIG:-$SERVER_CONFIG_DEFAULT}"
AGENT_CONFIG="${AGENT_CONFIG:-$AGENT_CONFIG_DEFAULT}"
AGENT_SPIFFE_ID="${AGENT_SPIFFE_ID:-spiffe://example.org/host/python-demo-agent}"

QUIET=${QUIET:-0}

log() {
    if [ "$QUIET" -eq 0 ]; then
        echo "$1"
    fi
}

log "Unified-Identity - Phase 1: Starting SPIRE stack"
log ""

# Clean up any existing processes
log "Cleaning up any existing SPIRE processes..."
pkill -f "spire-server" >/dev/null 2>&1 || true
pkill -f "spire-agent" >/dev/null 2>&1 || true
pkill -f "keylime-stub" >/dev/null 2>&1 || true
pkill -f "go run main.go" >/dev/null 2>&1 || true

# Kill any process using port 8888 (Keylime stub)
if command -v lsof >/dev/null 2>&1; then
    lsof -ti:8888 | xargs kill -9 >/dev/null 2>&1 || true
fi
if command -v fuser >/dev/null 2>&1; then
    fuser -k 8888/tcp >/dev/null 2>&1 || true
fi

sleep 2

# Clean up old sockets and data
log "Cleaning up old sockets and data..."
rm -rf /tmp/spire-server /tmp/spire-agent
rm -f /tmp/spire-server.pid /tmp/spire-agent.pid /tmp/keylime-stub.pid
sudo rm -rf /opt/spire/data 2>/dev/null || true
sudo mkdir -p /opt/spire/data/server /opt/spire/data/agent
sudo chown -R "$(whoami)":"$(whoami)" /opt/spire/data 2>/dev/null || true

# Start Keylime Stub
log "Starting Keylime Stub..."
cd "${KEYLIME_STUB_DIR}"
go run main.go > /tmp/keylime-stub.log 2>&1 &
echo $! > /tmp/keylime-stub.pid
sleep 2
log "✓ Keylime Stub started (PID: $(cat /tmp/keylime-stub.pid))"
if [ "$QUIET" -eq 0 ] && [ -f /tmp/keylime-stub.log ]; then
    log "  Initial log:"
    tail -2 /tmp/keylime-stub.log | sed 's/^/    /' || true
fi

# Initialize SPIRE Server
log "Initializing SPIRE Server..."
mkdir -p /tmp/spire-server/private
"${SPIRE_DIR}/bin/spire-server" validate -config "$SERVER_CONFIG"
"${SPIRE_DIR}/bin/spire-server" run -config "$SERVER_CONFIG" > /tmp/spire-server.log 2>&1 &
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
    echo "SPIRE Stack Ready"
    printf '=%.0s' {1..70}
    echo ""
    echo "Server PID: $SPIRE_SERVER_PID"
    echo "Agent PID: $SPIRE_AGENT_PID"
    echo "Keylime Stub PID: $(cat /tmp/keylime-stub.pid)"
    echo ""
    echo "To stop the stack: ${PROJECT_ROOT}/scripts/stop-unified-identity.sh"
fi


