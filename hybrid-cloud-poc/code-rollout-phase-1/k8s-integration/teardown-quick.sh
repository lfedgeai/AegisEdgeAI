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
for pid_file in /tmp/spire-agent.pid /tmp/spire-server.pid /tmp/keylime-stub.pid; do
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
        kill "$pid" 2>/dev/null || true
        rm -f "$pid_file"
    fi
done

# Delete kind cluster
echo "Deleting kind cluster..."
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

echo "✓ Quick teardown complete"

