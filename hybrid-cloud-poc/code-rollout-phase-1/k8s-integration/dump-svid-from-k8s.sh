#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Script to dump SVID from a Kubernetes workload pod

set -e

POD_NAME="${1:-test-sovereign-workload}"
NAMESPACE="${2:-default}"
OUTPUT_DIR="${3:-/tmp/k8s-svid-dump}"
KUBECONFIG="${KUBECONFIG:-/tmp/kubeconfig-kind.yaml}"

export KUBECONFIG

echo "Unified-Identity - Phase 1: Dumping SVID from Kubernetes Pod"
echo ""
echo "Pod: $POD_NAME"
echo "Namespace: $NAMESPACE"
echo "Output: $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get pod name if deployment name provided
if [[ "$POD_NAME" == *"deployment"* ]] || ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    # Try to get pod from deployment
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

# Check if SPIRE socket exists in pod
echo "Checking SPIRE Workload API socket..."
if ! kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -S /run/spire/sockets/api.sock 2>/dev/null; then
    echo "Error: SPIRE Workload API socket not found in pod"
    echo "Socket location: /run/spire/sockets/api.sock"
    echo ""
    echo "Checking available sockets:"
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- ls -la /run/spire/sockets/ 2>/dev/null || echo "Socket directory not found"
    exit 1
fi

echo "✓ SPIRE Workload API socket found"
echo ""

# Method 1: Use spire-agent CLI if available in pod
echo "Method 1: Attempting to use spire-agent CLI..."
if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- which spire-agent >/dev/null 2>&1; then
    echo "Using spire-agent to fetch SVID..."
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- spire-agent api fetch \
        -socketPath /run/spire/sockets/api.sock \
        > "$OUTPUT_DIR/svid-bundle.pem" 2>&1 || echo "spire-agent CLI not working, trying alternative method"
    
    if [ -f "$OUTPUT_DIR/svid-bundle.pem" ] && [ -s "$OUTPUT_DIR/svid-bundle.pem" ]; then
        echo "✓ SVID fetched using spire-agent"
        # Extract first certificate
        sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$OUTPUT_DIR/svid-bundle.pem" | head -n 100 > "$OUTPUT_DIR/svid.crt"
        echo "✓ Certificate extracted to $OUTPUT_DIR/svid.crt"
    fi
fi

# Method 2: Use workload API client (Go)
echo ""
echo "Method 2: Using workload API client..."
cat > "$OUTPUT_DIR/fetch-svid.go" << 'EOF'
package main

import (
	"context"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io/ioutil"
	"os"
	"time"

	"github.com/spiffe/go-spiffe/v2/spiffeid"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
)

func main() {
	socketPath := "/run/spire/sockets/api.sock"
	if len(os.Args) > 1 {
		socketPath = os.Args[1]
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Create X509Source
	source, err := workloadapi.NewX509Source(ctx, workloadapi.WithClientOptions(
		workloadapi.WithAddr("unix://"+socketPath),
	))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error creating X509Source: %v\n", err)
		os.Exit(1)
	}
	defer source.Close()

	// Get X509 SVID
	svid, err := source.GetX509SVID()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting X509 SVID: %v\n", err)
		os.Exit(1)
	}

	// Write certificate
	certPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "CERTIFICATE",
		Bytes: svid.Certificates[0].Raw,
	})

	if err := ioutil.WriteFile("/tmp/svid.crt", certPEM, 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing certificate: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("SPIFFE ID: %s\n", svid.ID)
	fmt.Printf("Certificate written to /tmp/svid.crt\n")
}
EOF

# Copy and run in pod if Go is available
if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- which go >/dev/null 2>&1; then
    echo "Copying Go client to pod..."
    kubectl cp "$OUTPUT_DIR/fetch-svid.go" "$NAMESPACE/$POD_NAME:/tmp/fetch-svid.go" >/dev/null 2>&1 || echo "Could not copy Go file"
    
    echo "Building and running SVID fetcher..."
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- sh -c "
        cd /tmp && \
        go mod init fetch-svid 2>/dev/null; \
        go get github.com/spiffe/go-spiffe/v2@latest 2>/dev/null; \
        go build -o fetch-svid fetch-svid.go 2>/dev/null && \
        ./fetch-svid /run/spire/sockets/api.sock 2>&1
    " || echo "Go method not available"
    
    # Copy certificate back
    kubectl cp "$NAMESPACE/$POD_NAME:/tmp/svid.crt" "$OUTPUT_DIR/svid.crt" >/dev/null 2>&1 && \
        echo "✓ Certificate copied from pod" || echo "Could not copy certificate"
fi

# Method 3: Use kubectl exec with simple script (fallback)
echo ""
echo "Method 3: Using kubectl exec (fallback)..."
echo "For this method, you need to manually extract the SVID from the pod."
echo ""
echo "To dump SVID from the pod, run:"
echo "  kubectl exec $POD_NAME -n $NAMESPACE -- /bin/sh"
echo ""
echo "Then inside the pod, use one of these methods:"
echo ""
echo "Option A: If spire-agent is available:"
echo "  spire-agent api fetch -socketPath /run/spire/sockets/api.sock > /tmp/svid.pem"
echo ""
echo "Option B: Use a Go client (if Go is installed in pod):"
echo "  # Copy the fetch-svid.go script into the pod"
echo "  # Build and run it"
echo ""
echo "Option C: Copy certificate from pod to host:"
echo "  kubectl cp $NAMESPACE/$POD_NAME:/tmp/svid.crt $OUTPUT_DIR/svid.crt"

# Check if we have a certificate
if [ -f "$OUTPUT_DIR/svid.crt" ] && [ -s "$OUTPUT_DIR/svid.crt" ]; then
    echo ""
    echo "✓ Certificate found at $OUTPUT_DIR/svid.crt"
    echo ""
    echo "To view the SVID with Phase 1 highlights, run:"
    echo "  cd $(dirname "$0")/../scripts"
    echo "  ./dump-svid -cert $OUTPUT_DIR/svid.crt"
    echo ""
    echo "Note: AttestedClaims JSON is not automatically extracted."
    echo "      For full Phase 1 features, use the generate-sovereign-svid script"
    echo "      with the entry ID from the host."
else
    echo ""
    echo "⚠ Could not automatically extract SVID certificate"
    echo "  Please use one of the manual methods above"
fi

echo ""
echo "Files saved to: $OUTPUT_DIR"

