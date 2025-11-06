#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Setup script for SPIRE Server, Agent, and Keylime Stub for Python app demo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${SCRIPT_DIR}/../spire"
KEYLIME_STUB_DIR="${SCRIPT_DIR}/../keylime-stub"

echo "Unified-Identity - Phase 1: Setting up SPIRE for Python App Demo"
echo ""

# Clean up any existing processes
echo "Cleaning up any existing SPIRE processes..."
pkill -f "spire-server" >/dev/null 2>&1 || true
pkill -f "spire-agent" >/dev/null 2>&1 || true
pkill -f "keylime-stub" >/dev/null 2>&1 || true
pkill -f "go run main.go" >/dev/null 2>&1 || true
sleep 2

# Clean up old sockets and data
echo "Cleaning up old sockets and data..."
rm -rf /tmp/spire-server /tmp/spire-agent
rm -f /tmp/spire-server.pid /tmp/spire-agent.pid /tmp/keylime-stub.pid
sudo rm -rf /opt/spire/data 2>/dev/null || true
sudo mkdir -p /opt/spire/data/server /opt/spire/data/agent
sudo chown -R $(whoami):$(whoami) /opt/spire/data 2>/dev/null || true

# Start Keylime Stub
echo "Starting Keylime Stub..."
cd "${KEYLIME_STUB_DIR}"
go run main.go > /tmp/keylime-stub.log 2>&1 &
echo $! > /tmp/keylime-stub.pid
sleep 2
echo "✓ Keylime Stub started (PID: $(cat /tmp/keylime-stub.pid))"

# Initialize SPIRE Server
echo "Initializing SPIRE Server..."
mkdir -p /tmp/spire-server/private
"${SPIRE_DIR}/bin/spire-server" validate -config "${SCRIPT_DIR}/spire-server.conf"
"${SPIRE_DIR}/bin/spire-server" run -config "${SCRIPT_DIR}/spire-server.conf" > /tmp/spire-server.log 2>&1 &
SPIRE_SERVER_PID=$!
echo $SPIRE_SERVER_PID > /tmp/spire-server.pid
sleep 3
echo "✓ SPIRE Server started (PID: $SPIRE_SERVER_PID)"

# Wait for server to be ready
echo "Waiting for SPIRE Server to be ready..."
for i in {1..30}; do
    if [ -S /tmp/spire-server/private/api.sock ]; then
        # Test if socket is responsive
        "${SPIRE_DIR}/bin/spire-server" healthcheck -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1 && break
    fi
    sleep 1
done

if [ ! -S /tmp/spire-server/private/api.sock ]; then
    echo "Error: SPIRE Server socket not ready"
    exit 1
fi
echo "✓ SPIRE Server is ready"

# Create join token
echo "Creating join token..."
JOIN_TOKEN=$("${SPIRE_DIR}/bin/spire-server" token generate \
    -spiffeID spiffe://example.org/host/python-demo-agent \
    -socketPath /tmp/spire-server/private/api.sock \
    | grep "Token:" | awk '{print $2}')

if [ -z "$JOIN_TOKEN" ]; then
    echo "Error: Failed to generate join token"
    exit 1
fi
echo "✓ Join token generated: $JOIN_TOKEN"

# Fetch trust bundle
echo "Fetching trust bundle for agent..."
"${SPIRE_DIR}/bin/spire-server" bundle show -format pem -socketPath /tmp/spire-server/private/api.sock > /tmp/bundle.pem
echo "✓ Trust bundle saved to /tmp/bundle.pem"

# Start SPIRE Agent
echo "Starting SPIRE Agent..."
mkdir -p /tmp/spire-agent/public
"${SPIRE_DIR}/bin/spire-agent" validate -config "${SCRIPT_DIR}/spire-agent.conf"
"${SPIRE_DIR}/bin/spire-agent" run \
    -config "${SCRIPT_DIR}/spire-agent.conf" \
    -joinToken "$JOIN_TOKEN" > /tmp/spire-agent.log 2>&1 &
SPIRE_AGENT_PID=$!
echo $SPIRE_AGENT_PID > /tmp/spire-agent.pid
sleep 3
echo "✓ SPIRE Agent started (PID: $SPIRE_AGENT_PID)"

# Wait for agent socket
echo "Waiting for SPIRE Agent socket..."
SOCKET_READY=false
for i in {1..60}; do
    if [ -S /tmp/spire-agent/public/api.sock ]; then
        # Socket exists - verify it's actually a socket and accessible
        # Note: We don't test with 'spire-agent api fetch' because that requires
        # a registration entry, which we haven't created yet. Just check socket exists.
        SOCKET_READY=true
        break
    fi
    if [ $((i % 5)) -eq 0 ]; then
        echo "  Still waiting... ($i/60)"
        # Check if agent process is still running
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
    echo "Agent logs:"
    tail -30 /tmp/spire-agent.log 2>&1 | head -30
    exit 1
fi
echo "✓ SPIRE Agent socket ready: /tmp/spire-agent/public/api.sock"

echo ""
echo "=" * 70
echo "SPIRE Setup Complete!"
echo "=" * 70
echo ""
echo "Server PID: $SPIRE_SERVER_PID"
echo "Agent PID: $SPIRE_AGENT_PID"
echo "Keylime Stub PID: $(cat /tmp/keylime-stub.pid)"
echo ""
echo "To stop SPIRE:"
echo "  kill \$(cat /tmp/spire-server.pid) \$(cat /tmp/spire-agent.pid) \$(cat /tmp/keylime-stub.pid)"
echo ""

