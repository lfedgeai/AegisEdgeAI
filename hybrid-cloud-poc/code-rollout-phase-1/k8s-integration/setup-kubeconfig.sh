#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Helper script to set up kubeconfig for kind cluster

set -e

CLUSTER_NAME="${1:-aegis-spire}"
KUBECONFIG_PATH="/tmp/kubeconfig-kind.yaml"

echo "Unified-Identity - Phase 1: Setting up kubeconfig for kind cluster"
echo "Cluster name: $CLUSTER_NAME"
echo ""

# Check if cluster exists (try without sudo first, then with sudo)
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    USE_SUDO=false
elif sudo kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    USE_SUDO=true
else
    echo "Error: Cluster '$CLUSTER_NAME' not found"
    echo "Available clusters:"
    kind get clusters 2>/dev/null || sudo kind get clusters 2>/dev/null || echo "  (none)"
    exit 1
fi

# Get kubeconfig
echo "Retrieving kubeconfig..."
if [ "$USE_SUDO" = "true" ]; then
    sudo kind get kubeconfig --name "$CLUSTER_NAME" > "$KUBECONFIG_PATH" 2>&1
    sudo chown "$USER:$USER" "$KUBECONFIG_PATH" 2>/dev/null || true
else
    kind get kubeconfig --name "$CLUSTER_NAME" > "$KUBECONFIG_PATH" 2>&1
fi

# Fix permissions (only if we used sudo)
if [ "$USE_SUDO" = "true" ]; then
    sudo chown "$USER:$USER" "$KUBECONFIG_PATH" 2>/dev/null || true
fi
chmod 600 "$KUBECONFIG_PATH" 2>/dev/null || true

# Verify kubeconfig
if [ ! -f "$KUBECONFIG_PATH" ] || [ ! -s "$KUBECONFIG_PATH" ]; then
    echo "Error: Failed to retrieve kubeconfig"
    exit 1
fi

echo "✓ Kubeconfig saved to: $KUBECONFIG_PATH"

# Export KUBECONFIG
export KUBECONFIG="$KUBECONFIG_PATH"

# Verify cluster access
echo ""
echo "Verifying cluster access..."
if kubectl cluster-info --context "kind-${CLUSTER_NAME}" &>/dev/null; then
    echo "✓ Cluster access verified"
    kubectl cluster-info --context "kind-${CLUSTER_NAME}" | head -2
else
    echo "⚠ Warning: Could not verify cluster access"
    echo "Try running: export KUBECONFIG=$KUBECONFIG_PATH"
fi

echo ""
echo "To use this kubeconfig, run:"
echo "  export KUBECONFIG=$KUBECONFIG_PATH"
echo ""
echo "Or add to your shell profile:"
echo "  echo 'export KUBECONFIG=$KUBECONFIG_PATH' >> ~/.bashrc"

