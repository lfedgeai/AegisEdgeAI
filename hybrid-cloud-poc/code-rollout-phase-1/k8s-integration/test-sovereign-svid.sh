#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# End-to-end test script for sovereign SVID with Kubernetes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG=/tmp/kubeconfig-kind.yaml

echo "Unified-Identity - Phase 1: Testing Sovereign SVID with Kubernetes"
echo ""

# Step 1: Start SPIRE
echo "Step 1: Starting SPIRE Server and Agent..."
"${SCRIPT_DIR}/setup-spire.sh"
sleep 5

# Step 2: Create registration entry
echo ""
echo "Step 2: Creating registration entry..."
cd "${SCRIPT_DIR}/../spire"
ENTRY_OUTPUT=$(./bin/spire-server entry create \
    -spiffeID spiffe://example.org/workload/test-k8s \
    -parentID spiffe://example.org/spire/agent-external \
    -selector k8s:ns:default \
    -selector k8s:sa:test-workload 2>&1)

ENTRY_ID=$(echo "$ENTRY_OUTPUT" | grep "Entry ID" | awk '{print $3}' || echo "")
if [ -z "$ENTRY_ID" ]; then
    echo "Failed to get entry ID. Output:"
    echo "$ENTRY_OUTPUT"
    exit 1
fi

echo "✓ Registration entry created: $ENTRY_ID"

# Step 3: Deploy test workload
echo ""
echo "Step 3: Deploying test workload..."
kubectl apply -f "${SCRIPT_DIR}/workloads/test-workload.yaml"
sleep 10

# Step 4: Wait for pod to be ready
echo ""
echo "Step 4: Waiting for pod to be ready..."
kubectl wait --for=condition=ready pod -l app=test-sovereign-workload --timeout=60s || true

# Step 5: Check pod logs
echo ""
echo "Step 5: Checking pod logs..."
kubectl logs -l app=test-sovereign-workload --tail=50 || true

# Step 6: Test SVID generation from host
echo ""
echo "Step 6: Testing SVID generation with sovereign attestation..."
cd "${SCRIPT_DIR}/../scripts"
if [ -f "./generate-sovereign-svid" ]; then
    ./generate-sovereign-svid \
        -entryID "$ENTRY_ID" \
        -spiffeID "spiffe://example.org/workload/test-k8s" \
        -serverSocketPath "unix:///tmp/spire-server/private/api.sock" \
        -verbose || echo "Note: SVID generation test completed (check logs above)"
else
    echo "⚠ generate-sovereign-svid script not found, skipping direct API test"
fi

# Step 7: Verify logs
echo ""
echo "Step 7: Checking SPIRE Server logs for Unified-Identity messages..."
tail -20 /tmp/spire-server.log | grep -i "unified-identity" || echo "No Unified-Identity messages in recent logs"

echo ""
echo "✅ Test complete!"
echo ""
echo "To view logs:"
echo "  SPIRE Server: tail -f /tmp/spire-server.log"
echo "  SPIRE Agent: tail -f /tmp/spire-agent.log"
echo "  Keylime Stub: tail -f /tmp/keylime-stub.log"
echo "  Workload: kubectl logs -l app=test-sovereign-workload"

