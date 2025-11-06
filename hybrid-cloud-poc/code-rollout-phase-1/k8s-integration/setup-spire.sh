#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Setup script to run SPIRE Server and Agent outside Kubernetes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${SCRIPT_DIR}/../spire"

echo "Unified-Identity - Phase 1: Setting up SPIRE (outside Kubernetes)"

# Create directories
mkdir -p /tmp/spire-server/{private,data}
mkdir -p /tmp/spire-agent/{public,data}
mkdir -p /opt/spire/data/{server,agent}

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
for i in {1..30}; do
    if [ -S "/tmp/spire-server/private/api.sock" ]; then
        break
    fi
    sleep 1
done

# Create join token for agent
echo "Creating join token..."
JOIN_TOKEN_OUTPUT=$(${SPIRE_DIR}/bin/spire-server token generate -spiffeID spiffe://example.org/spire/agent-external 2>&1)
JOIN_TOKEN=$(echo "$JOIN_TOKEN_OUTPUT" | grep "Token:" | awk '{print $2}' || echo "")
if [ -z "$JOIN_TOKEN" ]; then
    # Try alternative format
    JOIN_TOKEN=$(echo "$JOIN_TOKEN_OUTPUT" | tail -1 | awk '{print $NF}')
fi
echo "Join token: $JOIN_TOKEN"

# Start SPIRE Agent
echo "Starting SPIRE Agent..."
${SPIRE_DIR}/bin/spire-agent validate -config "${SCRIPT_DIR}/spire-agent/agent.conf"
${SPIRE_DIR}/bin/spire-agent run -config "${SCRIPT_DIR}/spire-agent/agent.conf" -joinToken "$JOIN_TOKEN" > /tmp/spire-agent.log 2>&1 &
SPIRE_AGENT_PID=$!
echo $SPIRE_AGENT_PID > /tmp/spire-agent.pid
sleep 3
echo "✓ SPIRE Agent started (PID: $SPIRE_AGENT_PID)"

# Verify sockets exist
if [ -S "/tmp/spire-server/private/api.sock" ]; then
    echo "✓ SPIRE Server socket: /tmp/spire-server/private/api.sock"
else
    echo "⚠ SPIRE Server socket not found"
fi

if [ -S "/tmp/spire-agent/public/api.sock" ]; then
    echo "✓ SPIRE Agent socket: /tmp/spire-agent/public/api.sock"
    # Make socket accessible to CSI driver (adjust permissions as needed)
    chmod 755 /tmp/spire-agent/public
    chmod 666 /tmp/spire-agent/public/api.sock || true
else
    echo "⚠ SPIRE Agent socket not found"
fi

echo ""
echo "✅ SPIRE setup complete!"
echo "   Server PID: $SPIRE_SERVER_PID"
echo "   Agent PID: $SPIRE_AGENT_PID"
echo ""
echo "To stop SPIRE:"
echo "  kill \$(cat /tmp/spire-server.pid) \$(cat /tmp/spire-agent.pid)"
echo "  kill \$(cat /tmp/keylime-stub.pid)"

