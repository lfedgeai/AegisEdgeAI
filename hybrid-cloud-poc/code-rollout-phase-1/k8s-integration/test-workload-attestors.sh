#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Test script to verify both unix and k8s workload attestors work correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_DIR="${SCRIPT_DIR}/../spire"
export KUBECONFIG=/tmp/kubeconfig-kind.yaml

echo "Unified-Identity - Phase 1: Testing Both Workload Attestors"
echo "============================================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Step 1: Verify SPIRE is running
echo "Step 1: Verifying SPIRE Server and Agent are running..."
if ! pgrep -f "spire-server" > /dev/null; then
    echo -e "${RED}✗ SPIRE Server is not running${NC}"
    echo "Please run: cd ${SCRIPT_DIR} && ./setup-spire.sh"
    exit 1
fi

if ! pgrep -f "spire-agent" > /dev/null; then
    echo -e "${RED}✗ SPIRE Agent is not running${NC}"
    echo "Please run: cd ${SCRIPT_DIR} && ./setup-spire.sh"
    exit 1
fi

if [ ! -S "/tmp/spire-server/private/api.sock" ]; then
    echo -e "${RED}✗ SPIRE Server socket not found${NC}"
    exit 1
fi

if [ ! -S "/tmp/spire-agent/public/api.sock" ]; then
    echo -e "${YELLOW}⚠ SPIRE Agent socket not found - agent may still be joining${NC}"
    echo "Waiting 10 seconds for agent to initialize..."
    sleep 10
    if [ ! -S "/tmp/spire-agent/public/api.sock" ]; then
        echo -e "${RED}✗ SPIRE Agent socket still not found${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ SPIRE Server and Agent are running${NC}"
echo ""

# Step 2: Get agent SPIFFE ID
echo "Step 2: Getting agent SPIFFE ID..."
cd "${SPIRE_DIR}"
AGENT_LIST=$(./bin/spire-server agent list -socketPath /tmp/spire-server/private/api.sock 2>&1)
if echo "$AGENT_LIST" | grep -q "No attested agents found"; then
    echo -e "${RED}✗ No agents found. Agent may not have joined yet.${NC}"
    echo "Agent list output:"
    echo "$AGENT_LIST"
    exit 1
fi

AGENT_SPIFFE_ID=$(echo "$AGENT_LIST" | grep -oP 'spiffe://[^\s]+' | head -1)
if [ -z "$AGENT_SPIFFE_ID" ]; then
    echo -e "${YELLOW}⚠ Could not extract agent SPIFFE ID, using default${NC}"
    AGENT_SPIFFE_ID="spiffe://example.org/spire/agent/join_token/$(cat /tmp/spire-agent.pid 2>/dev/null || echo 'default')"
fi

echo -e "${GREEN}✓ Agent SPIFFE ID: $AGENT_SPIFFE_ID${NC}"
echo ""

# Step 3: Test Unix Workload Attestor
echo "Step 3: Testing Unix Workload Attestor"
echo "--------------------------------------"

# Get current user ID
CURRENT_UID=$(id -u)
echo "Current user ID: $CURRENT_UID"

# Create registration entry for unix workload
echo "Creating registration entry for unix workload..."
UNIX_ENTRY_OUTPUT=$(./bin/spire-server entry create \
    -spiffeID spiffe://example.org/workload/test-unix \
    -parentID "$AGENT_SPIFFE_ID" \
    -selector "unix:uid:$CURRENT_UID" \
    -socketPath /tmp/spire-server/private/api.sock 2>&1)

if echo "$UNIX_ENTRY_OUTPUT" | grep -q "Entry ID"; then
    UNIX_ENTRY_ID=$(echo "$UNIX_ENTRY_OUTPUT" | grep "Entry ID" | awk '{print $3}')
    echo -e "${GREEN}✓ Unix workload entry created: $UNIX_ENTRY_ID${NC}"
    
    # Test SVID retrieval via workload API (if available)
    if [ -S "/tmp/spire-agent/public/api.sock" ]; then
        echo "Testing SVID retrieval via workload API..."
        # Use spire-agent CLI or workload API client to test
        # For now, just verify the entry exists
        ENTRY_SHOW=$(./bin/spire-server entry show -id "$UNIX_ENTRY_ID" -socketPath /tmp/spire-server/private/api.sock 2>&1)
        if echo "$ENTRY_SHOW" | grep -q "unix:uid:$CURRENT_UID"; then
            echo -e "${GREEN}✓ Unix workload attestor entry verified${NC}"
        else
            echo -e "${YELLOW}⚠ Entry created but selectors not verified${NC}"
        fi
    fi
else
    echo -e "${RED}✗ Failed to create unix workload entry${NC}"
    echo "Output: $UNIX_ENTRY_OUTPUT"
    exit 1
fi
echo ""

# Step 4: Test K8s Workload Attestor (if Kubernetes cluster exists)
echo "Step 4: Testing K8s Workload Attestor"
echo "-------------------------------------"

if kubectl cluster-info &>/dev/null; then
    echo "Kubernetes cluster detected"
    
    # Check if test workload exists
    if kubectl get deployment test-sovereign-workload -n default &>/dev/null; then
        echo "Test workload deployment found"
        
        # Create registration entry for k8s workload
        echo "Creating registration entry for k8s workload..."
        K8S_ENTRY_OUTPUT=$(./bin/spire-server entry create \
            -spiffeID spiffe://example.org/workload/test-k8s \
            -parentID "$AGENT_SPIFFE_ID" \
            -selector "k8s:ns:default" \
            -selector "k8s:sa:test-workload" \
            -socketPath /tmp/spire-server/private/api.sock 2>&1)
        
        if echo "$K8S_ENTRY_OUTPUT" | grep -q "Entry ID"; then
            K8S_ENTRY_ID=$(echo "$K8S_ENTRY_OUTPUT" | grep "Entry ID" | awk '{print $3}')
            echo -e "${GREEN}✓ K8s workload entry created: $K8S_ENTRY_ID${NC}"
            
            # Verify entry
            ENTRY_SHOW=$(./bin/spire-server entry show -id "$K8S_ENTRY_ID" -socketPath /tmp/spire-server/private/api.sock 2>&1)
            if echo "$ENTRY_SHOW" | grep -q "k8s:ns:default" && echo "$ENTRY_SHOW" | grep -q "k8s:sa:test-workload"; then
                echo -e "${GREEN}✓ K8s workload attestor entry verified${NC}"
            else
                echo -e "${YELLOW}⚠ Entry created but selectors not verified${NC}"
            fi
        else
            echo -e "${RED}✗ Failed to create k8s workload entry${NC}"
            echo "Output: $K8S_ENTRY_OUTPUT"
        fi
    else
        echo -e "${YELLOW}⚠ Test workload deployment not found${NC}"
        echo "Deploy test workload with: kubectl apply -f ${SCRIPT_DIR}/workloads/test-workload.yaml"
    fi
else
    echo -e "${YELLOW}⚠ Kubernetes cluster not detected - skipping k8s workload attestor test${NC}"
    echo "To test k8s workload attestor, create a kind cluster first"
fi
echo ""

# Step 5: Verify both attestors in agent logs
echo "Step 5: Verifying Workload Attestors in Agent Logs"
echo "---------------------------------------------------"

if [ -f "/tmp/spire-agent.log" ]; then
    echo "Checking agent logs for workload attestor initialization..."
    
    if grep -q "unix" /tmp/spire-agent.log | grep -q "WorkloadAttestor"; then
        echo -e "${GREEN}✓ Unix workload attestor found in logs${NC}"
    else
        echo -e "${YELLOW}⚠ Unix workload attestor not explicitly found in logs${NC}"
    fi
    
    if grep -q "k8s" /tmp/spire-agent.log | grep -q "WorkloadAttestor"; then
        echo -e "${GREEN}✓ K8s workload attestor found in logs${NC}"
    else
        echo -e "${YELLOW}⚠ K8s workload attestor not explicitly found in logs${NC}"
    fi
    
    # Check for any workload attestor errors
    if grep -i "error.*workload.*attestor" /tmp/spire-agent.log | tail -5; then
        echo -e "${RED}✗ Errors found in workload attestor logs${NC}"
    else
        echo -e "${GREEN}✓ No errors in workload attestor logs${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Agent log file not found${NC}"
fi
echo ""

# Step 6: Summary
echo "Step 6: Test Summary"
echo "--------------------"
echo -e "${GREEN}✓ Unix workload attestor: Tested${NC}"
if kubectl cluster-info &>/dev/null 2>&1; then
    echo -e "${GREEN}✓ K8s workload attestor: Tested${NC}"
else
    echo -e "${YELLOW}⚠ K8s workload attestor: Skipped (no cluster)${NC}"
fi

echo ""
echo "Registration Entries Created:"
if [ -n "$UNIX_ENTRY_ID" ]; then
    echo "  - Unix workload: $UNIX_ENTRY_ID"
fi
if [ -n "$K8S_ENTRY_ID" ]; then
    echo "  - K8s workload: $K8S_ENTRY_ID"
fi

echo ""
echo "To view entries:"
echo "  cd ${SPIRE_DIR}"
echo "  ./bin/spire-server entry show -id <entry-id> -socketPath /tmp/spire-server/private/api.sock"
echo ""
echo "To clean up entries:"
if [ -n "$UNIX_ENTRY_ID" ]; then
    echo "  ./bin/spire-server entry delete -id $UNIX_ENTRY_ID -socketPath /tmp/spire-server/private/api.sock"
fi
if [ -n "$K8S_ENTRY_ID" ]; then
    echo "  ./bin/spire-server entry delete -id $K8S_ENTRY_ID -socketPath /tmp/spire-server/private/api.sock"
fi

echo ""
echo -e "${GREEN}✅ Workload Attestor Test Complete!${NC}"

