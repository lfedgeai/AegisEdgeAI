#!/bin/bash
# Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
# Script to dump SVID from a Kubernetes workload pod

set -e

POD_NAME="${1:-test-sovereign-workload}"
NAMESPACE="${2:-default}"
OUTPUT_DIR="${3:-/tmp/k8s-svid-dump}"
KUBECONFIG="${KUBECONFIG:-/tmp/kubeconfig-kind.yaml}"

export KUBECONFIG

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Check if SPIRE socket exists in pod (try both CSI driver and hostPath patterns)
echo "Checking SPIRE Workload API socket..."
SOCKET_FOUND=false
SOCKET_PATH=""

# Try CSI driver pattern first (production)
if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -S /run/spire/sockets/workload_api.sock 2>/dev/null; then
    SOCKET_PATH="/run/spire/sockets/workload_api.sock"
    SOCKET_FOUND=true
    echo "✓ SPIRE Workload API socket found (CSI driver pattern)"
# Try hostPath pattern (legacy/testing)
elif kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -S /run/spire/sockets/api.sock 2>/dev/null; then
    SOCKET_PATH="/run/spire/sockets/api.sock"
    SOCKET_FOUND=true
    echo "✓ SPIRE Workload API socket found (hostPath pattern)"
fi

if [ "$SOCKET_FOUND" = "false" ]; then
    echo "Error: SPIRE Workload API socket not found in pod"
    echo "Checked locations:"
    echo "  - /run/spire/sockets/workload_api.sock (CSI driver pattern)"
    echo "  - /run/spire/sockets/api.sock (hostPath pattern)"
    echo ""
    echo "Checking available sockets:"
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- ls -la /run/spire/sockets/ 2>/dev/null || echo "Socket directory not found"
    exit 1
fi

echo ""

# Method 1: Use spire-agent CLI if available in pod
echo "Method 1: Attempting to use spire-agent CLI..."
SPIRE_AGENT_AVAILABLE=false

# Check if spire-agent is available in pod
if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- which spire-agent >/dev/null 2>&1; then
    SPIRE_AGENT_AVAILABLE=true
    echo "  spire-agent found in pod"
elif [ -f "${SCRIPT_DIR}/../spire/bin/spire-agent" ]; then
    # Copy spire-agent binary from host to pod
    echo "  Copying spire-agent binary from host to pod..."
    kubectl cp "${SCRIPT_DIR}/../spire/bin/spire-agent" "$NAMESPACE/$POD_NAME:/tmp/spire-agent" >/dev/null 2>&1 && \
        kubectl exec "$POD_NAME" -n "$NAMESPACE" -- chmod +x /tmp/spire-agent >/dev/null 2>&1 && \
        SPIRE_AGENT_AVAILABLE=true && \
        echo "  ✓ spire-agent binary copied to pod" || echo "  ⚠ Could not copy spire-agent binary"
fi

if [ "$SPIRE_AGENT_AVAILABLE" = "true" ]; then
    echo "  Fetching SVID using spire-agent..."
    # Use spire-agent from pod or copied binary
    if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- which spire-agent >/dev/null 2>&1; then
        SPIRE_AGENT_CMD="spire-agent"
    else
        SPIRE_AGENT_CMD="/tmp/spire-agent"
    fi
    
    # Try to fetch SVID - check if binary exists and is executable first
    if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -x "$SPIRE_AGENT_CMD" 2>/dev/null; then
        echo "  Attempting to fetch SVID (timeout: 10 seconds)..."
        # Use timeout to prevent hanging, and capture both stdout and stderr
        # If timeout command is not available, use a background process with kill
        if command -v timeout >/dev/null 2>&1; then
            FETCH_OUTPUT=$(timeout 10 kubectl exec "$POD_NAME" -n "$NAMESPACE" -- "$SPIRE_AGENT_CMD" api fetch \
                -socketPath "$SOCKET_PATH" \
                -write /tmp 2>&1) || FETCH_EXIT=$?
        else
            # Fallback: run in background and kill after timeout
            kubectl exec "$POD_NAME" -n "$NAMESPACE" -- "$SPIRE_AGENT_CMD" api fetch \
                -socketPath "$SOCKET_PATH" \
                -write /tmp > "$OUTPUT_DIR/fetch_output.tmp" 2>&1 &
            FETCH_PID=$!
            sleep 10
            if kill -0 $FETCH_PID 2>/dev/null; then
                kill $FETCH_PID 2>/dev/null || true
                FETCH_EXIT=124  # Timeout
                FETCH_OUTPUT="Command timed out after 10 seconds"
            else
                wait $FETCH_PID
                FETCH_EXIT=$?
                FETCH_OUTPUT=$(cat "$OUTPUT_DIR/fetch_output.tmp" 2>/dev/null || echo "")
                rm -f "$OUTPUT_DIR/fetch_output.tmp"
            fi
        fi
        
        # Check if command succeeded
        if [ ${FETCH_EXIT:-1} -eq 0 ]; then
            echo "  ✓ SVID fetched successfully"
        elif [ ${FETCH_EXIT:-1} -eq 124 ]; then
            echo "  ⚠ Command timed out (binary may be hanging due to missing libraries)"
            echo "  The pod image (curlimages/curl) lacks required glibc libraries."
        else
            echo "  ⚠ spire-agent fetch failed (exit code: ${FETCH_EXIT:-1})"
            echo "  Error output:"
            echo "$FETCH_OUTPUT" | head -5 | sed 's/^/    /'
            echo "  Note: Binary may be missing required libraries (glibc)."
            echo "        The curlimages/curl image is minimal and doesn't include these."
        fi
    else
        echo "  ⚠ Binary not found or not executable: $SPIRE_AGENT_CMD"
    fi
    
    # Copy SVID files from pod
    if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -f /tmp/svid.0.pem 2>/dev/null; then
        kubectl cp "$NAMESPACE/$POD_NAME:/tmp/svid.0.pem" "$OUTPUT_DIR/svid.crt" >/dev/null 2>&1 && \
            echo "  ✓ SVID certificate copied to $OUTPUT_DIR/svid.crt" || echo "  ⚠ Could not copy certificate"
    fi
    
    if kubectl exec "$POD_NAME" -n "$NAMESPACE" -- test -f /tmp/svid.0.key 2>/dev/null; then
        kubectl cp "$NAMESPACE/$POD_NAME:/tmp/svid.0.key" "$OUTPUT_DIR/svid.key" >/dev/null 2>&1 && \
            echo "  ✓ SVID key copied to $OUTPUT_DIR/svid.key" || true
    fi
else
    echo "  ⚠ spire-agent not available in pod and could not be copied"
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
	socketPath := "/run/spire/sockets/workload_api.sock"
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
        ./fetch-svid "$SOCKET_PATH" 2>&1
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
echo "  spire-agent api fetch -socketPath $SOCKET_PATH > /tmp/svid.pem"
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
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "To display/view the SVID:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Option 1: Use the dump-svid script (recommended - shows Phase 1 highlights):"
    echo "  cd $(dirname "$0")/../scripts"
    echo "  ./dump-svid -cert $OUTPUT_DIR/svid.crt"
    echo ""
    echo "Option 2: Use openssl to view certificate details:"
    echo "  openssl x509 -in $OUTPUT_DIR/svid.crt -text -noout"
    echo ""
    echo "Option 3: View certificate in JSON format:"
    echo "  openssl x509 -in $OUTPUT_DIR/svid.crt -noout -json"
    echo ""
    echo "Option 4: View just the SPIFFE URI:"
    echo "  openssl x509 -in $OUTPUT_DIR/svid.crt -noout -text | grep -A 1 'Subject Alternative Name'"
    echo ""
    echo "Note: AttestedClaims JSON is not automatically extracted from the workload API."
    echo "      For full Phase 1 features with AttestedClaims, use the generate-sovereign-svid"
    echo "      script with the entry ID from the host (not from the pod)."
else
    echo ""
    echo "⚠ Could not automatically extract SVID certificate"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Manual extraction method:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Since the pod image lacks required libraries, manually extract the SVID:"
    echo ""
    echo "1. Exec into the pod:"
    echo "   kubectl exec -it $POD_NAME -n $NAMESPACE -- /bin/sh"
    echo ""
echo "2. Inside the pod, try to use the copied spire-agent (may fail due to libraries):"
echo "   /tmp/spire-agent api fetch -socketPath $SOCKET_PATH -write /tmp"
    echo ""
    echo "3. If that fails, the workload should still be able to use the socket programmatically."
    echo "   For testing, use the generate-sovereign-svid script from the host instead."
    echo ""
    echo "4. To view any extracted certificate:"
    echo "   openssl x509 -in $OUTPUT_DIR/svid.crt -text -noout"
fi

echo ""
echo "Files saved to: $OUTPUT_DIR"

