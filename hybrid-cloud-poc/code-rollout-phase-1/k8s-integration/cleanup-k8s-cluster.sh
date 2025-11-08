#!/bin/bash
# Unified-Identity - Phase 1: Complete Kubernetes cluster cleanup
# Removes kind cluster and ALL associated data

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-aegis-spire}"
CONTEXT_NAME="kind-${KIND_CLUSTER_NAME}"
KUBECONFIG_FILE="/tmp/kubeconfig-kind.yaml"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Complete Kubernetes Cluster Cleanup                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Cluster: $KIND_CLUSTER_NAME"
echo "Context: $CONTEXT_NAME"
echo ""

# Step 1: Delete all Kubernetes resources (if cluster is accessible)
echo "Step 1: Deleting all Kubernetes resources..."
if kubectl cluster-info --context "$CONTEXT_NAME" >/dev/null 2>&1; then
    echo "  Cluster is accessible, deleting resources..."
    
    # Delete all namespaces (except system namespaces)
    for ns in $(kubectl get namespaces --context "$CONTEXT_NAME" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true); do
        if [[ "$ns" != "default" && "$ns" != "kube-system" && "$ns" != "kube-public" && "$ns" != "kube-node-lease" && "$ns" != "local-path-storage" ]]; then
            echo "    Deleting namespace: $ns"
            kubectl delete namespace "$ns" --context "$CONTEXT_NAME" --timeout=30s >/dev/null 2>&1 || true
        fi
    done
    
    # Delete all resources in default namespace
    echo "    Cleaning default namespace..."
    kubectl delete all --all --context "$CONTEXT_NAME" -n default --timeout=30s >/dev/null 2>&1 || true
    kubectl delete secrets --all --context "$CONTEXT_NAME" -n default --timeout=30s >/dev/null 2>&1 || true
    kubectl delete configmaps --all --context "$CONTEXT_NAME" -n default --timeout=30s >/dev/null 2>&1 || true
    kubectl delete pvc --all --context "$CONTEXT_NAME" -n default --timeout=30s >/dev/null 2>&1 || true
    
    echo "  ✓ Kubernetes resources deleted"
else
    echo "  ⚠ Cluster not accessible (may already be deleted)"
fi
echo ""

# Step 2: Delete kind cluster
echo "Step 2: Deleting kind cluster..."
if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
    echo "  Found cluster: $KIND_CLUSTER_NAME"
    # Try without sudo first, then with sudo
    if kind delete cluster --name "$KIND_CLUSTER_NAME" 2>/dev/null; then
        echo "  ✓ Cluster deleted (without sudo)"
    elif sudo kind delete cluster --name "$KIND_CLUSTER_NAME" 2>/dev/null; then
        echo "  ✓ Cluster deleted (with sudo)"
    else
        echo "  ⚠ Failed to delete cluster (may already be deleted or need manual cleanup)"
    fi
else
    echo "  ⚠ Cluster '$KIND_CLUSTER_NAME' not found in kind clusters"
fi
echo ""

# Step 3: Remove kubeconfig files
echo "Step 3: Removing kubeconfig files..."

# Remove /tmp/kubeconfig-kind.yaml
if [ -f "$KUBECONFIG_FILE" ]; then
    rm -f "$KUBECONFIG_FILE"
    echo "  ✓ Removed: $KUBECONFIG_FILE"
else
    echo "  ⚠ Not found: $KUBECONFIG_FILE"
fi

# Remove context from ~/.kube/config
if [ -f "$HOME/.kube/config" ]; then
    echo "  Removing context from ~/.kube/config..."
    
    # Delete context
    kubectl config delete-context "$CONTEXT_NAME" >/dev/null 2>&1 || true
    
    # Remove cluster entry
    kubectl config unset "clusters.${CONTEXT_NAME}" >/dev/null 2>&1 || true
    
    # Remove user entry
    kubectl config unset "users.${CONTEXT_NAME}" >/dev/null 2>&1 || true
    
    # Also try removing with sed (more aggressive)
    if grep -q "$CONTEXT_NAME" "$HOME/.kube/config" 2>/dev/null; then
        # Backup config first
        cp "$HOME/.kube/config" "$HOME/.kube/config.backup.$(date +%s)" 2>/dev/null || true
        
        # Remove lines containing the context name
        sed -i "/${CONTEXT_NAME}/d" "$HOME/.kube/config" 2>/dev/null || true
        
        # Clean up empty sections
        sed -i '/^$/N;/^\n$/d' "$HOME/.kube/config" 2>/dev/null || true
    fi
    
    echo "  ✓ Context removed from ~/.kube/config"
else
    echo "  ⚠ ~/.kube/config not found"
fi

# Remove admin.conf
if [ -f "$HOME/.kube/admin.conf" ]; then
    rm -f "$HOME/.kube/admin.conf"
    echo "  ✓ Removed: ~/.kube/admin.conf"
fi

echo ""

# Step 4: Clean up Docker resources (kind uses Docker)
echo "Step 4: Cleaning up Docker resources..."
if command -v docker >/dev/null 2>&1; then
    # Remove kind-related containers
    KIND_CONTAINERS=$(docker ps -a --filter "name=${KIND_CLUSTER_NAME}" --format "{{.ID}}" 2>/dev/null || true)
    if [ -n "$KIND_CONTAINERS" ]; then
        echo "  Removing kind containers..."
        echo "$KIND_CONTAINERS" | xargs -r docker rm -f >/dev/null 2>&1 || true
        echo "  ✓ Kind containers removed"
    else
        echo "  ⚠ No kind containers found"
    fi
    
    # Remove kind-related images (optional - commented out to avoid removing shared images)
    # KIND_IMAGES=$(docker images --filter "reference=kindest/node*" --format "{{.ID}}" 2>/dev/null || true)
    # if [ -n "$KIND_IMAGES" ]; then
    #     echo "  Removing kind images..."
    #     echo "$KIND_IMAGES" | xargs -r docker rmi -f >/dev/null 2>&1 || true
    #     echo "  ✓ Kind images removed"
    # fi
    
    # Clean up unused Docker resources
    echo "  Cleaning up unused Docker resources..."
    docker system prune -f >/dev/null 2>&1 || true
    echo "  ✓ Docker cleanup complete"
else
    echo "  ⚠ Docker not found, skipping Docker cleanup"
fi
echo ""

# Step 5: Remove any remaining kind-related files
echo "Step 5: Removing kind-related files..."
# Remove kind cache (if exists)
if [ -d "$HOME/.cache/kind" ]; then
    rm -rf "$HOME/.cache/kind"
    echo "  ✓ Removed: ~/.cache/kind"
fi

# Remove any kind-related temp files
find /tmp -name "*kind*" -type f -delete 2>/dev/null || true
find /tmp -name "*kubeconfig*" -type f -delete 2>/dev/null || true
echo "  ✓ Cleaned up temporary files"
echo ""

# Step 6: Verify cleanup
echo "Step 6: Verifying cleanup..."
echo "  Checking for remaining references..."

# Check kind clusters
REMAINING_CLUSTERS=$(kind get clusters 2>/dev/null | grep -c "^${KIND_CLUSTER_NAME}$" 2>/dev/null || echo "0")
REMAINING_CLUSTERS=$(echo "$REMAINING_CLUSTERS" | tr -d '\n' | head -1)
if [ "${REMAINING_CLUSTERS:-0}" -eq 0 ] 2>/dev/null; then
    echo "  ✓ No kind clusters found"
else
    echo "  ⚠ Cluster still exists in kind (may need manual deletion)"
fi

# Check kubectl contexts
REMAINING_CONTEXTS=$(kubectl config get-contexts 2>/dev/null | grep -c "$CONTEXT_NAME" 2>/dev/null || echo "0")
REMAINING_CONTEXTS=$(echo "$REMAINING_CONTEXTS" | tr -d '\n' | head -1)
if [ "${REMAINING_CONTEXTS:-0}" -eq 0 ] 2>/dev/null; then
    echo "  ✓ No kubectl contexts found"
else
    echo "  ⚠ Context still exists in kubectl config"
fi

# Check kubeconfig files
if [ ! -f "$KUBECONFIG_FILE" ] && [ ! -f "$HOME/.kube/admin.conf" ]; then
    echo "  ✓ No kubeconfig files found"
else
    echo "  ⚠ Some kubeconfig files may still exist"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Cleanup Complete                                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "All Kubernetes cluster data has been removed."
echo ""
echo "If you want to also clean up SPIRE data, run:"
echo "  ${SCRIPT_DIR}/teardown-quick.sh"
echo ""

