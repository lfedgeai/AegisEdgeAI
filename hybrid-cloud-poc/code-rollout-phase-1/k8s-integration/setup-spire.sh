#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Setup script to run SPIRE Server and Agent outside Kubernetes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${SCRIPT_DIR}/../spire"

echo "Unified-Identity - Phase 1: Setting up SPIRE (outside Kubernetes)"

# Clean up any existing processes
echo "Cleaning up any existing SPIRE processes..."
pkill -f "spire-server" >/dev/null 2>&1 || true
pkill -f "spire-agent" >/dev/null 2>&1 || true
pkill -f "keylime-stub" >/dev/null 2>&1 || true
sleep 2

# Create directories with proper permissions
# Check if directories exist and are owned by root - if so, remove and recreate
if [ -d "/tmp/spire-agent" ] && [ "$(stat -c '%U' /tmp/spire-agent 2>/dev/null || echo '')" = "root" ]; then
    echo "Removing root-owned /tmp/spire-agent directory..."
    sudo rm -rf /tmp/spire-agent
fi

if [ -d "/tmp/spire-server" ] && [ "$(stat -c '%U' /tmp/spire-server 2>/dev/null || echo '')" = "root" ]; then
    echo "Removing root-owned /tmp/spire-server directory..."
    sudo rm -rf /tmp/spire-server
fi

# Create directories (now owned by current user)
mkdir -p /tmp/spire-server/{private,data}
mkdir -p /tmp/spire-agent/{public,data}

# Create /opt/spire directories (may need sudo)
if [ ! -d "/opt/spire/data" ]; then
    echo "Creating /opt/spire/data directories..."
    sudo mkdir -p /opt/spire/data/{server,agent}
    sudo chown -R "$(id -u):$(id -g)" /opt/spire/data 2>/dev/null || true
else
    sudo chown -R "$(id -u):$(id -g)" /opt/spire/data 2>/dev/null || true
    mkdir -p /opt/spire/data/{server,agent}
fi

# Check if SPIRE binaries exist
if [ ! -f "${SPIRE_DIR}/bin/spire-server" ]; then
    echo "Building SPIRE Server..."
    cd "${SPIRE_DIR}"
    make build
fi

if [ ! -f "${SPIRE_DIR}/bin/spire-agent" ]; then
    echo "Building SPIRE Agent..."
    cd "${SPIRE_DIR}"
    make build
fi

# Start Keylime Stub (if not running)
if ! pgrep -f "keylime-stub" > /dev/null; then
    echo "Starting Keylime Stub..."
    cd "${SCRIPT_DIR}/../keylime-stub"
    go run main.go > /tmp/keylime-stub.log 2>&1 &
    echo $! > /tmp/keylime-stub.pid
    sleep 2
    echo "✓ Keylime Stub started (PID: $(cat /tmp/keylime-stub.pid))"
fi

# Initialize SPIRE Server
echo "Initializing SPIRE Server..."
${SPIRE_DIR}/bin/spire-server validate -config "${SCRIPT_DIR}/spire-server/server.conf"
${SPIRE_DIR}/bin/spire-server run -config "${SCRIPT_DIR}/spire-server/server.conf" > /tmp/spire-server.log 2>&1 &
SPIRE_SERVER_PID=$!
echo $SPIRE_SERVER_PID > /tmp/spire-server.pid
sleep 3
echo "✓ SPIRE Server started (PID: $SPIRE_SERVER_PID)"

# Wait for server to be ready
echo "Waiting for SPIRE Server to be ready..."
SOCKET_READY=false
for i in {1..30}; do
    if [ -S "/tmp/spire-server/private/api.sock" ]; then
        # Test if socket is actually accessible
        if ${SPIRE_DIR}/bin/spire-server healthcheck -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1; then
            SOCKET_READY=true
            break
        fi
    fi
    sleep 1
done

if [ "$SOCKET_READY" != "true" ]; then
    echo "⚠ SPIRE Server socket not ready after 30 seconds"
    echo "Checking server logs..."
    tail -10 /tmp/spire-server.log
    exit 1
fi

# Create join token for agent
echo "Creating join token..."
JOIN_TOKEN_OUTPUT=$(${SPIRE_DIR}/bin/spire-server token generate -spiffeID spiffe://example.org/host/external-agent -socketPath /tmp/spire-server/private/api.sock 2>&1)
JOIN_TOKEN=$(echo "$JOIN_TOKEN_OUTPUT" | grep "Token:" | awk '{print $2}' || echo "")
if [ -z "$JOIN_TOKEN" ]; then
    # Try alternative format
    JOIN_TOKEN=$(echo "$JOIN_TOKEN_OUTPUT" | tail -1 | awk '{print $NF}')
fi
echo "Join token: $JOIN_TOKEN"

# Fetch trust bundle for agent
echo "Fetching trust bundle for agent..."
mkdir -p /opt/spire/data/agent 2>/dev/null || true
${SPIRE_DIR}/bin/spire-server bundle show -socketPath /tmp/spire-server/private/api.sock -format pem > /opt/spire/data/agent/bundle.crt 2>&1 || {
    echo "⚠ Failed to fetch bundle, agent will retry"
}

# Start SPIRE Agent
echo "Starting SPIRE Agent..."
${SPIRE_DIR}/bin/spire-agent validate -config "${SCRIPT_DIR}/spire-agent/agent.conf"
${SPIRE_DIR}/bin/spire-agent run -config "${SCRIPT_DIR}/spire-agent/agent.conf" -joinToken "$JOIN_TOKEN" > /tmp/spire-agent.log 2>&1 &
SPIRE_AGENT_PID=$!
echo $SPIRE_AGENT_PID > /tmp/spire-agent.pid
sleep 5
echo "✓ SPIRE Agent started (PID: $SPIRE_AGENT_PID)"

# Verify sockets exist
if [ -S "/tmp/spire-server/private/api.sock" ]; then
    echo "✓ SPIRE Server socket: /tmp/spire-server/private/api.sock"
else
    echo "⚠ SPIRE Server socket not found"
fi

# Wait a bit more for agent to fully initialize
echo "Waiting for SPIRE Agent to initialize..."
for i in {1..15}; do
    if [ -S "/tmp/spire-agent/public/api.sock" ]; then
        echo "✓ SPIRE Agent socket: /tmp/spire-agent/public/api.sock"
        # Make socket accessible to CSI driver (adjust permissions as needed)
        chmod 755 /tmp/spire-agent/public
        chmod 666 /tmp/spire-agent/public/api.sock || true
        break
    fi
    sleep 1
done

if [ ! -S "/tmp/spire-agent/public/api.sock" ]; then
    echo "⚠ SPIRE Agent socket not found after 15 seconds"
    echo "Agent may still be joining. Check logs: tail -f /tmp/spire-agent.log"
fi

echo ""
echo "✅ SPIRE setup complete!"
echo "   Server PID: $SPIRE_SERVER_PID"
echo "   Agent PID: $SPIRE_AGENT_PID"
echo ""
echo "To stop SPIRE:"
echo "  kill \$(cat /tmp/spire-server.pid) \$(cat /tmp/spire-agent.pid)"
echo "  kill \$(cat /tmp/keylime-stub.pid)"

