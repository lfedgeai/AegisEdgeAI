#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Teardown script to clean up Kubernetes cluster and SPIRE components

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-aegis-spire}"
KUBECONFIG_FILE="/tmp/kubeconfig-kind.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Unified-Identity - Phase 1: Teardown${NC}"
echo ""

# Function to check if a process is running
check_process() {
    local pid_file=$1
    local name=$2
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    fi
    return 1
}

# Step 1: Delete Kubernetes workloads
echo -e "${YELLOW}Step 1: Cleaning up Kubernetes workloads...${NC}"
export KUBECONFIG="$KUBECONFIG_FILE"

if kubectl cluster-info > /dev/null 2>&1; then
    echo "  Deleting test workloads..."
    kubectl delete -f "${SCRIPT_DIR}/workloads/test-workload.yaml" 2>/dev/null || true
    kubectl delete -f "${SCRIPT_DIR}/csi-driver/spire-csi-driver.yaml" 2>/dev/null || true
    
    # Delete any remaining pods with test labels
    kubectl delete pods -l app=test-sovereign-workload --ignore-not-found=true 2>/dev/null || true
    kubectl delete pods -l app=test-sovereign-pod --ignore-not-found=true 2>/dev/null || true
    
    # Delete service accounts
    kubectl delete serviceaccount test-workload --ignore-not-found=true 2>/dev/null || true
    
    echo -e "  ${GREEN}✓ Kubernetes workloads cleaned${NC}"
else
    echo -e "  ${YELLOW}⚠ Kubernetes cluster not accessible, skipping workload cleanup${NC}"
fi

echo ""

# Step 2: Delete kind cluster
echo -e "${YELLOW}Step 2: Deleting kind cluster '${KIND_CLUSTER_NAME}'...${NC}"
# Try without sudo first, then with sudo
if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
    kind delete cluster --name "$KIND_CLUSTER_NAME" 2>&1
elif sudo kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
    sudo kind delete cluster --name "$KIND_CLUSTER_NAME" 2>&1
    echo -e "  ${GREEN}✓ Kind cluster deleted${NC}"
else
    echo -e "  ${YELLOW}⚠ Kind cluster '${KIND_CLUSTER_NAME}' not found${NC}"
fi

# Always remove kubeconfig file (even if cluster was already deleted)
if [ -f "$KUBECONFIG_FILE" ]; then
    rm -f "$KUBECONFIG_FILE"
    echo -e "  ${GREEN}✓ Kubeconfig file removed${NC}"
else
    echo -e "  ${YELLOW}⚠ Kubeconfig file not found${NC}"
fi

# Remove kind cluster context from ~/.kube/config if it exists
KUBECONFIG_USER="$HOME/.kube/config"
CONTEXT_NAME="kind-${KIND_CLUSTER_NAME}"
if [ -f "$KUBECONFIG_USER" ]; then
    if kubectl config get-contexts "$CONTEXT_NAME" >/dev/null 2>&1; then
        echo "  Removing context '$CONTEXT_NAME' from ~/.kube/config..."
        kubectl config delete-context "$CONTEXT_NAME" >/dev/null 2>&1 || true
        kubectl config unset "clusters.${CONTEXT_NAME}" >/dev/null 2>&1 || true
        kubectl config unset "users.${CONTEXT_NAME}" >/dev/null 2>&1 || true
        echo -e "  ${GREEN}✓ Context removed from ~/.kube/config${NC}"
    else
        echo -e "  ${YELLOW}⚠ Context '$CONTEXT_NAME' not found in ~/.kube/config${NC}"
    fi
fi

# Remove admin.conf from ~/.kube/ if it exists
ADMIN_CONF="$HOME/.kube/admin.conf"
if [ -f "$ADMIN_CONF" ]; then
    rm -f "$ADMIN_CONF"
    echo -e "  ${GREEN}✓ admin.conf removed from ~/.kube/${NC}"
else
    echo -e "  ${YELLOW}⚠ admin.conf not found in ~/.kube/${NC}"
fi

echo ""

# Step 3: Stop SPIRE Agent
echo -e "${YELLOW}Step 3: Stopping SPIRE Agent...${NC}"
if check_process "/tmp/spire-agent.pid" "spire-agent"; then
    SPIRE_AGENT_PID=$(cat /tmp/spire-agent.pid)
    echo "  Stopping SPIRE Agent (PID: $SPIRE_AGENT_PID)..."
    kill "$SPIRE_AGENT_PID" 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    if ps -p "$SPIRE_AGENT_PID" > /dev/null 2>&1; then
        echo "  Force killing SPIRE Agent..."
        kill -9 "$SPIRE_AGENT_PID" 2>/dev/null || true
    fi
    
    rm -f /tmp/spire-agent.pid
    echo -e "  ${GREEN}✓ SPIRE Agent stopped${NC}"
else
    echo -e "  ${YELLOW}⚠ SPIRE Agent not running${NC}"
    rm -f /tmp/spire-agent.pid
fi

echo ""

# Step 4: Stop SPIRE Server
echo -e "${YELLOW}Step 4: Stopping SPIRE Server...${NC}"
if check_process "/tmp/spire-server.pid" "spire-server"; then
    SPIRE_SERVER_PID=$(cat /tmp/spire-server.pid)
    echo "  Stopping SPIRE Server (PID: $SPIRE_SERVER_PID)..."
    kill "$SPIRE_SERVER_PID" 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    if ps -p "$SPIRE_SERVER_PID" > /dev/null 2>&1; then
        echo "  Force killing SPIRE Server..."
        kill -9 "$SPIRE_SERVER_PID" 2>/dev/null || true
    fi
    
    rm -f /tmp/spire-server.pid
    echo -e "  ${GREEN}✓ SPIRE Server stopped${NC}"
else
    echo -e "  ${YELLOW}⚠ SPIRE Server not running${NC}"
    rm -f /tmp/spire-server.pid
fi

echo ""

# Step 5: Stop Keylime Stub
echo -e "${YELLOW}Step 5: Stopping Keylime Stub...${NC}"
if check_process "/tmp/keylime-stub.pid" "keylime-stub"; then
    KEYLIME_STUB_PID=$(cat /tmp/keylime-stub.pid)
    echo "  Stopping Keylime Stub (PID: $KEYLIME_STUB_PID)..."
    kill "$KEYLIME_STUB_PID" 2>/dev/null || true
    sleep 2
    
    # Force kill if still running
    if ps -p "$KEYLIME_STUB_PID" > /dev/null 2>&1; then
        echo "  Force killing Keylime Stub..."
        kill -9 "$KEYLIME_STUB_PID" 2>/dev/null || true
    fi
    
    rm -f /tmp/keylime-stub.pid
    echo -e "  ${GREEN}✓ Keylime Stub stopped${NC}"
else
    echo -e "  ${YELLOW}⚠ Keylime Stub not running${NC}"
    rm -f /tmp/keylime-stub.pid
fi

echo ""

# Step 6: Clean up sockets (optional)
echo -e "${YELLOW}Step 6: Cleaning up sockets...${NC}"
if [ -S "/tmp/spire-server/private/api.sock" ]; then
    rm -f /tmp/spire-server/private/api.sock
    echo -e "  ${GREEN}✓ SPIRE Server socket removed${NC}"
fi

if [ -S "/tmp/spire-agent/public/api.sock" ]; then
    rm -f /tmp/spire-agent/public/api.sock
    echo -e "  ${GREEN}✓ SPIRE Agent socket removed${NC}"
fi

echo ""

# Step 7: Optional cleanup of logs and data
read -p "Do you want to remove log files and data directories? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Step 7: Cleaning up logs and data...${NC}"
    
    # Remove log files
    rm -f /tmp/spire-server.log
    rm -f /tmp/spire-agent.log
    rm -f /tmp/keylime-stub.log
    echo -e "  ${GREEN}✓ Log files removed${NC}"
    
    # Optionally remove data directories
    read -p "Do you want to remove SPIRE data directories? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf /tmp/spire-server/data
        rm -rf /tmp/spire-agent/data
        rm -rf /opt/spire/data
        echo -e "  ${GREEN}✓ Data directories removed${NC}"
    else
        echo -e "  ${YELLOW}⚠ Data directories preserved${NC}"
    fi
else
    echo -e "${YELLOW}Step 7: Skipping log and data cleanup${NC}"
fi

echo ""
echo -e "${GREEN}✅ Teardown complete!${NC}"
echo ""
echo "Summary:"
echo "  - Kubernetes cluster: Deleted"
echo "  - SPIRE Server: Stopped"
echo "  - SPIRE Agent: Stopped"
echo "  - Keylime Stub: Stopped"
echo "  - Sockets: Removed"
echo ""

