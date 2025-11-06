#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Simple script to dump SVID from Kubernetes pod using kubectl exec
# This is the easiest approach for testing

set -e

POD_NAME="${1:-test-sovereign-workload}"
NAMESPACE="${2:-default}"
OUTPUT_DIR="${3:-/tmp/k8s-svid-dump}"
KUBECONFIG="${KUBECONFIG:-/tmp/kubeconfig-kind.yaml}"

export KUBECONFIG

echo "Unified-Identity - Phase 1: Dumping SVID from Kubernetes Pod (kubectl exec)"
echo ""
echo "Pod: $POD_NAME"
echo "Namespace: $NAMESPACE"
echo "Output: $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get pod name if deployment name provided
if [[ "$POD_NAME" == *"deployment"* ]] || ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    DEPLOYMENT_NAME="$POD_NAME"
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -z "$POD_NAME" ]; then
        echo "Error: Could not find pod for deployment '$DEPLOYMENT_NAME'"
        exit 1
    fi
    echo "Found pod: $POD_NAME"
fi

# Check if pod exists
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "Error: Pod '$POD_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

# Check if pod is ready
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' | grep -q "Running"; then
    echo "Warning: Pod is not in Running state"
fi

# Determine socket path (try both patterns)
SOCKET_PATH=""
if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -S /run/spire/sockets/workload_api.sock 2>/dev/null; then
    SOCKET_PATH="/run/spire/sockets/workload_api.sock"
    echo "✓ Found socket: $SOCKET_PATH (CSI driver pattern)"
elif kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -S /run/spire/sockets/api.sock 2>/dev/null; then
    SOCKET_PATH="/run/spire/sockets/api.sock"
    echo "✓ Found socket: $SOCKET_PATH (hostPath pattern)"
else
    echo "Error: SPIRE socket not found in pod"
    echo "Checking available sockets:"
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- ls -la /run/spire/sockets/ 2>/dev/null || echo "Socket directory not found"
    exit 1
fi

echo ""
echo "Step 1: Copying spire-agent binary to pod (if needed)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPIRE_AGENT_BINARY="${SCRIPT_DIR}/../spire/bin/spire-agent"

if [ -f "$SPIRE_AGENT_BINARY" ]; then
    kubectl cp "$SPIRE_AGENT_BINARY" "$NAMESPACE/$POD_NAME:/tmp/spire-agent" >/dev/null 2>&1 && \
        kubectl exec "$POD_NAME" -n "$NAMESPACE" -- chmod +x /tmp/spire-agent >/dev/null 2>&1 && \
        echo "✓ spire-agent binary copied to pod" || echo "⚠ Could not copy binary (may already exist)"
else
    echo "⚠ spire-agent binary not found at $SPIRE_AGENT_BINARY"
fi

echo ""
echo "Step 2: Fetching SVID from pod..."
echo "Using socket: $SOCKET_PATH"

# Try to fetch SVID using spire-agent
FETCH_SUCCESS=false

# Method 1: Use copied spire-agent binary
if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -x /tmp/spire-agent 2>/dev/null; then
    echo "  Attempting with /tmp/spire-agent..."
    if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- /tmp/spire-agent api fetch \
        -socketPath "$SOCKET_PATH" \
        -write /tmp 2>&1 | grep -q "SVID written"; then
        FETCH_SUCCESS=true
        echo "  ✓ SVID fetched successfully"
    else
        echo "  ⚠ Fetch may have failed (checking for output files...)"
    fi
fi

# Check if SVID files were created
if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -f /tmp/svid.0.pem 2>/dev/null; then
    FETCH_SUCCESS=true
    echo "  ✓ SVID file found in pod"
fi

if [ "$FETCH_SUCCESS" = "false" ]; then
    echo ""
    echo "⚠ Automatic fetch failed. Trying manual approach..."
    echo ""
    echo "You can manually fetch the SVID by running:"
    echo "  kubectl exec -it $POD_NAME -n $NAMESPACE -- /bin/sh"
    echo ""
    echo "Then inside the pod:"
    echo "  /tmp/spire-agent api fetch -socketPath $SOCKET_PATH -write /tmp"
    echo ""
    echo "Or if spire-agent is not available, use a Go client or workload API directly."
    exit 1
fi

echo ""
echo "Step 3: Copying SVID files from pod to host..."

# Copy certificate
if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -f /tmp/svid.0.pem 2>/dev/null; then
    kubectl cp "$NAMESPACE/$POD_NAME:/tmp/svid.0.pem" "$OUTPUT_DIR/svid.crt" >/dev/null 2>&1 && \
        echo "✓ Certificate copied to $OUTPUT_DIR/svid.crt" || echo "⚠ Could not copy certificate"
fi

# Copy key (if available)
if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -f /tmp/svid.0.key 2>/dev/null; then
    kubectl cp "$NAMESPACE/$POD_NAME:/tmp/svid.0.key" "$OUTPUT_DIR/svid.key" >/dev/null 2>&1 && \
        echo "✓ Private key copied to $OUTPUT_DIR/svid.key" || true
fi

# Verify certificate
if [ -f "$OUTPUT_DIR/svid.crt" ] && [ -s "$OUTPUT_DIR/svid.crt" ]; then
    echo ""
    echo "✓✓✓ SVID successfully dumped! ✓✓✓"
    echo ""
    echo "Certificate location: $OUTPUT_DIR/svid.crt"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "To view the SVID:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Option 1: Use dump-svid script (recommended - shows Phase 1 highlights):"
    echo "  cd ${SCRIPT_DIR}/../scripts"
    echo "  ./dump-svid -cert $OUTPUT_DIR/svid.crt"
    echo ""
    echo "Option 2: Use openssl:"
    echo "  openssl x509 -in $OUTPUT_DIR/svid.crt -text -noout | head -30"
    echo ""
    echo "Option 3: View SPIFFE URI:"
    echo "  openssl x509 -in $OUTPUT_DIR/svid.crt -noout -text | grep -A 1 'Subject Alternative Name'"
    echo ""
    echo "Note: This SVID was fetched from the workload API (no AttestedClaims)."
    echo "      For AttestedClaims, use generate-sovereign-svid script from the host."
else
    echo ""
    echo "⚠ Could not extract SVID certificate"
    echo ""
    echo "Manual steps:"
    echo "  1. kubectl exec -it $POD_NAME -n $NAMESPACE -- /bin/sh"
    echo "  2. /tmp/spire-agent api fetch -socketPath $SOCKET_PATH -write /tmp"
    echo "  3. kubectl cp $NAMESPACE/$POD_NAME:/tmp/svid.0.pem $OUTPUT_DIR/svid.crt"
fi

echo ""
echo "Files saved to: $OUTPUT_DIR"

