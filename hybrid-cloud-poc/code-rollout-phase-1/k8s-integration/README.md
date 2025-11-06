# Unified-Identity - Phase 1: Kubernetes Integration with SPIRE CSI Driver

This directory contains the setup for testing sovereign SVID generation with Kubernetes workloads using the SPIRE CSI driver, while SPIRE Server and Agent run **outside** the Kubernetes cluster for security.

## Architecture

```
┌─────────────────────────────────────┐
│  Kubernetes Cluster (kind)          │
│  ┌───────────────────────────────┐  │
│  │  Test Workload Pod            │  │
│  │  (uses SPIRE CSI driver)      │  │
│  └──────────┬────────────────────┘  │
│             │                        │
│  ┌──────────▼────────────────────┐  │
│  │  SPIRE CSI Driver              │  │
│  │  (mounts agent socket)          │  │
│  └──────────┬────────────────────┘  │
└─────────────┼────────────────────────┘
              │ (socket mount)
              │
┌─────────────▼────────────────────────┐
│  Host (Outside Kubernetes)          │
│  ┌───────────────────────────────┐  │
│  │  SPIRE Agent                  │  │
│  │  (Unified-Identity enabled)   │  │
│  │  Socket: /tmp/spire-agent/... │  │
│  └──────────┬────────────────────┘  │
│             │                        │
│  ┌──────────▼────────────────────┐  │
│  │  SPIRE Server                 │  │
│  │  (Unified-Identity enabled)   │  │
│  └──────────┬────────────────────┘  │
│             │                        │
│  ┌──────────▼────────────────────┐  │
│  │  Keylime Stub                 │  │
│  │  (Port 8888)                  │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

## Scripts Overview

- **`setup-spire.sh`** - Starts SPIRE Server, Agent, and Keylime Stub outside Kubernetes
- **`test-sovereign-svid.sh`** - End-to-end test script for sovereign SVID generation
- **`dump-svid-from-k8s.sh`** - Dumps SVID from a Kubernetes pod (automated extraction)
- **`teardown.sh`** - Full interactive teardown (removes cluster, stops processes, optional cleanup)
- **`teardown-quick.sh`** - Quick non-interactive teardown (stops processes, removes cluster)

## Prerequisites

1. **Kubernetes Cluster**: Standard Kubernetes cluster (using kind)
2. **SPIRE Binaries**: Built SPIRE Server and Agent with Phase 1 changes
3. **Keylime Stub**: Running on host at `http://localhost:8888`
4. **Docker/Kind**: For running the Kubernetes cluster

## Setup Steps

### Step 0: Teardown Previous Setup (if needed)

If you have a previous setup running, clean it up first:

```bash
cd k8s-integration
./teardown.sh  # Full teardown with prompts
# OR
./teardown-quick.sh  # Quick teardown without prompts
```

### Step 1: Start SPIRE (Outside Kubernetes)

```bash
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/k8s-integration
./setup-spire.sh
```

This script:
- Starts Keylime Stub
- Starts SPIRE Server with Unified-Identity feature flag
- Starts SPIRE Agent with Unified-Identity feature flag
- Creates necessary sockets accessible to the cluster

### Step 2: Create Kubernetes Cluster with Socket Mount

The kind cluster is created with the agent socket mounted:

```bash
sudo kind create cluster --name aegis-spire --config - << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: aegis-spire
nodes:
- role: control-plane
  extraMounts:
  - hostPath: /tmp/spire-agent/public
    containerPath: /tmp/spire-agent/public
    readOnly: true
EOF
```

### Step 3: Create Registration Entry

```bash
export KUBECONFIG=/tmp/kubeconfig-kind.yaml

# Create registration entry for test workload
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/spire
./bin/spire-server entry create \
    -spiffeID spiffe://example.org/workload/test-k8s \
    -parentID spiffe://example.org/spire/agent-external \
    -selector k8s:ns:default \
    -selector k8s:sa:test-workload
```

### Step 4: Deploy Test Workload

For Phase 1 testing, we can use a simple hostPath mount to access the agent socket:

```bash
export KUBECONFIG=/tmp/kubeconfig-kind.yaml
kubectl apply -f workloads/test-workload-simple.yaml
```

### Step 5: Test Sovereign SVID Generation

**Option A: Dump SVID from Kubernetes Pod (Automated)**

Use the provided script to dump SVID from a running pod:

```bash
export KUBECONFIG=/tmp/kubeconfig-kind.yaml
cd k8s-integration

# Dump SVID from pod
./dump-svid-from-k8s.sh test-sovereign-workload default /tmp/k8s-svid-dump

# View the dumped SVID with Phase 1 highlights
cd ../scripts
./dump-svid -cert /tmp/k8s-svid-dump/svid.crt
```

**Option B: Manual SVID Extraction from Pod**

```bash
# Check pod logs
kubectl logs -f deployment/test-sovereign-workload

# Exec into pod
kubectl exec -it deployment/test-sovereign-workload -- /bin/sh

# Inside pod, if spire-agent is available:
spire-agent api fetch -socketPath /run/spire/sockets/api.sock > /tmp/svid.pem

# Copy certificate back to host
# (from host, in another terminal)
kubectl cp default/$(kubectl get pod -l app=test-sovereign-workload -o jsonpath='{.items[0].metadata.name}'):/tmp/svid.pem /tmp/svid.pem

# Extract first certificate
sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' /tmp/svid.pem | head -n 100 > /tmp/svid.crt

# Dump with Phase 1 highlights
cd scripts
./dump-svid -cert /tmp/svid.crt
```

**Option C: Generate SVID from Host (Recommended for Phase 1 Testing)**

Since Phase 1 requires `SovereignAttestation` which is provided at SVID generation time, you can generate and dump the SVID from the host:

```bash
# Generate SVID with SovereignAttestation (from host)
cd scripts
./generate-sovereign-svid \
    -entryID <ENTRY_ID> \
    -spiffeID spiffe://example.org/workload/test-k8s \
    -verbose

# Dump and highlight Phase 1 additions
./dump-svid -cert svid.crt -attested svid_attested_claims.json
```

**Note:** For Phase 1 testing, generating the SVID from the host with `SovereignAttestation` is recommended because:
- The `SovereignAttestation` must be provided at SVID generation time
- The `AttestedClaims` are returned in the API response and saved to JSON
- The `dump-svid` script can highlight both the certificate and AttestedClaims

## SPIRE CSI Driver (Future)

For production use, deploy the official SPIRE CSI driver:

```bash
# Install SPIRE CSI driver
helm repo add spiffe https://spiffe.github.io/helm-charts/
helm install spire-csi-driver spiffe/spire-csi-driver \
  --namespace spire-system \
  --create-namespace \
  --set agentSocketPath=/tmp/spire-agent/public/api.sock
```

## Verification

1. **Check SPIRE Server logs**:
   ```bash
   tail -f /tmp/spire-server.log | grep "Unified-Identity"
   ```

2. **Check SPIRE Agent logs**:
   ```bash
   tail -f /tmp/spire-agent.log | grep "Unified-Identity"
   ```

3. **Verify Keylime Stub is running**:
   ```bash
   curl http://localhost:8888/health
   ```

4. **Check workload can access SVID**:
   ```bash
   kubectl exec test-sovereign-pod -- ls -la /run/spire/sockets/
   ```

## Troubleshooting

### SPIRE Agent socket not accessible

- Check socket exists: `ls -la /tmp/spire-agent/public/api.sock`
- Check permissions: `chmod 755 /tmp/spire-agent/public`
- Verify kind cluster has the mount: `kubectl describe node aegis-spire-control-plane`

### Feature flag not enabled

- Verify config files have `feature_flags { Unified-Identity = true }`
- Check SPIRE Server/Agent logs for feature flag messages
- Restart SPIRE after config changes

### Keylime Stub not responding

- Check if running: `pgrep -f keylime-stub`
- Check logs: `tail -f /tmp/keylime-stub.log`
- Restart: `./setup-spire.sh`

## Cleanup

### Full Teardown (Interactive)

The `teardown.sh` script provides a comprehensive cleanup with options:

```bash
cd k8s-integration
./teardown.sh
```

This script will:
1. **Delete Kubernetes workloads** - Removes test pods and service accounts
2. **Delete kind cluster** - Removes the Kubernetes cluster
3. **Remove kubeconfig file** - Always removes `/tmp/kubeconfig-kind.yaml` (even if cluster was already deleted)
4. **Remove kubeconfig context** - Removes `kind-aegis-spire` context from `~/.kube/config`
5. **Remove admin.conf** - Removes `~/.kube/admin.conf` if it exists
6. **Stop SPIRE Agent** - Gracefully stops the agent process
7. **Stop SPIRE Server** - Gracefully stops the server process
8. **Stop Keylime Stub** - Stops the stub service
9. **Clean up sockets** - Removes Unix domain sockets
10. **Optional cleanup** - Prompts to remove log files and data directories

**Example output:**
```
Unified-Identity - Phase 1: Teardown

Step 1: Cleaning up Kubernetes workloads...
  ✓ Kubernetes workloads cleaned

Step 2: Deleting kind cluster 'aegis-spire'...
  ✓ Kind cluster deleted
  ✓ Kubeconfig file removed
  ✓ Context removed from ~/.kube/config
  ✓ admin.conf removed from ~/.kube/
  (or: ⚠ Kind cluster 'aegis-spire' not found)
  ✓ Kubeconfig file removed
  ✓ Context removed from ~/.kube/config
  ✓ admin.conf removed from ~/.kube/

Step 3: Stopping SPIRE Agent...
  ✓ SPIRE Agent stopped

Step 4: Stopping SPIRE Server...
  ✓ SPIRE Server stopped

Step 5: Stopping Keylime Stub...
  ✓ Keylime Stub stopped

Step 6: Cleaning up sockets...
  ✓ SPIRE Server socket removed
  ✓ SPIRE Agent socket removed

✅ Teardown complete!
```

### Quick Teardown (Non-Interactive)

For a quick cleanup without prompts:

```bash
cd k8s-integration
./teardown-quick.sh
```

This script:
- Stops all processes (SPIRE Server, Agent, Keylime Stub)
- Deletes the kind cluster
- Removes kubeconfig file (`/tmp/kubeconfig-kind.yaml`)
- Removes kubeconfig context from `~/.kube/config`
- Removes `~/.kube/admin.conf` if it exists
- Removes sockets
- Does NOT remove log files or data (for quick restart)

### Manual Cleanup

If you prefer manual cleanup:

```bash
# Stop SPIRE processes
kill $(cat /tmp/spire-server.pid) $(cat /tmp/spire-agent.pid) $(cat /tmp/keylime-stub.pid) 2>/dev/null || true

# Delete Kubernetes cluster
sudo kind delete cluster --name aegis-spire

# Remove sockets
rm -f /tmp/spire-server/private/api.sock
rm -f /tmp/spire-agent/public/api.sock

# Remove kubeconfig
rm -f /tmp/kubeconfig-kind.yaml

# Remove kind cluster context from ~/.kube/config
kubectl config delete-context kind-aegis-spire 2>/dev/null || true

# Remove admin.conf from ~/.kube/
rm -f ~/.kube/admin.conf

# Optional: Remove logs
rm -f /tmp/spire-server.log /tmp/spire-agent.log /tmp/keylime-stub.log

# Optional: Remove data (WARNING: This deletes all SPIRE data)
rm -rf /tmp/spire-server/data /tmp/spire-agent/data /opt/spire/data
```

