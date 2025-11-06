#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Quick teardown script (no prompts, minimal cleanup)

set -e

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-aegis-spire}"
KUBECONFIG_FILE="/tmp/kubeconfig-kind.yaml"

echo "Unified-Identity - Phase 1: Quick Teardown"
echo ""

# Stop processes
echo "Stopping processes..."

# Stop SPIRE Agent
if [ -f /tmp/spire-agent.pid ]; then
    pid=$(cat /tmp/spire-agent.pid)
    kill "$pid" 2>/dev/null || true
    rm -f /tmp/spire-agent.pid
fi
pkill -f "spire-agent" >/dev/null 2>&1 || true

# Stop SPIRE Server
if [ -f /tmp/spire-server.pid ]; then
    pid=$(cat /tmp/spire-server.pid)
    kill "$pid" 2>/dev/null || true
    rm -f /tmp/spire-server.pid
fi
pkill -f "spire-server" >/dev/null 2>&1 || true

# Stop Keylime Stub
if [ -f /tmp/keylime-stub.pid ]; then
    pid=$(cat /tmp/keylime-stub.pid)
    kill "$pid" 2>/dev/null || true
    rm -f /tmp/keylime-stub.pid
fi
pkill -f "keylime-stub" >/dev/null 2>&1 || true

# Wait a moment for processes to stop
sleep 2

# Delete kind cluster
echo "Deleting kind cluster..."
# Try without sudo first, then with sudo
kind delete cluster --name "$KIND_CLUSTER_NAME" 2>/dev/null || \
sudo kind delete cluster --name "$KIND_CLUSTER_NAME" 2>/dev/null || true

# Remove kubeconfig (always remove, even if cluster was already deleted)
echo "Removing kubeconfig..."
if [ -f "$KUBECONFIG_FILE" ]; then
    rm -f "$KUBECONFIG_FILE"
    echo "  ✓ Kubeconfig file removed"
else
    echo "  ⚠ Kubeconfig file not found"
fi

# Remove kind cluster context from ~/.kube/config if it exists
CONTEXT_NAME="kind-${KIND_CLUSTER_NAME}"
if [ -f "$HOME/.kube/config" ]; then
    echo "Removing context from ~/.kube/config..."
    kubectl config delete-context "$CONTEXT_NAME" >/dev/null 2>&1 || true
    kubectl config unset "clusters.${CONTEXT_NAME}" >/dev/null 2>&1 || true
    kubectl config unset "users.${CONTEXT_NAME}" >/dev/null 2>&1 || true
    echo "  ✓ Context removed from ~/.kube/config"
fi

# Remove admin.conf from ~/.kube/ if it exists
if [ -f "$HOME/.kube/admin.conf" ]; then
    rm -f "$HOME/.kube/admin.conf"
    echo "  ✓ admin.conf removed from ~/.kube/"
fi

# Remove sockets
echo "Removing sockets..."
rm -f /tmp/spire-server/private/api.sock
rm -f /tmp/spire-agent/public/api.sock
rm -rf /tmp/spire-server /tmp/spire-agent 2>/dev/null || true

# Remove log files (optional, but good for clean state)
echo "Removing log files..."
rm -f /tmp/spire-server.log /tmp/spire-agent.log /tmp/keylime-stub.log 2>/dev/null || true

# Verify processes are stopped
echo "Verifying processes are stopped..."
if pgrep -f "spire-server|spire-agent|keylime-stub" > /dev/null 2>&1; then
    echo "  ⚠ Some processes may still be running, consider running teardown.sh for full cleanup"
else
    echo "  ✓ All SPIRE and Keylime processes stopped"
fi

# Note: SPIRE data directories in /opt/spire/data are NOT removed by default
# to preserve registration entries and keys. To fully clean, manually remove:
# sudo rm -rf /opt/spire/data

echo ""
echo "✓ Quick teardown complete"

