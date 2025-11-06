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
- **`setup-kubeconfig.sh`** - Sets up kubeconfig for kind cluster (helper script)
- **`test-sovereign-svid.sh`** - End-to-end test script for sovereign SVID generation with Kubernetes
- **`test-workload-attestors.sh`** - Tests both `unix` and `k8s` workload attestors
- **`dump-svid-from-k8s.sh`** - Dumps SVID from a Kubernetes pod (automated extraction)
- **`teardown.sh`** - Full interactive teardown (removes cluster, stops processes, optional cleanup)
- **`teardown-quick.sh`** - Quick non-interactive teardown (stops processes, removes cluster)

## Workload Attestation

The SPIRE Agent is configured with **both** workload attestors to support hybrid environments:

1. **`unix` workload attestor**: Attests processes running directly on the host (non-Kubernetes workloads)
   - Works for any process on the host system
   - No additional configuration required

2. **`k8s` workload attestor**: Attests Kubernetes pods
   - When the agent runs **outside Kubernetes**, the k8s workload attestor requires:
     - Access to the Kubernetes API server (via kubeconfig or service account token)
     - Access to kubelet on each node (for pod information)
     - For external agents, you may need to configure `token_path` in `spire-agent/agent.conf`
   - The k8s workload attestor will attempt to use the default service account token path (`/var/run/secrets/kubernetes.io/serviceaccount/token`) if not configured
   - For Phase 1 testing, `skip_kubelet_verification = true` is set to simplify setup

**Configuration:** See `spire-agent/agent.conf` for workload attestor settings.

## Prerequisites

1. **Kubernetes Cluster**: Standard Kubernetes cluster (using kind)
2. **SPIRE Binaries**: Built SPIRE Server and Agent with Phase 1 changes
3. **Keylime Stub**: Running on host at `http://localhost:8888`
4. **Docker/Kind**: For running the Kubernetes cluster
5. **Docker Access**: Your user should be in the `docker` group (or have Docker access)
   ```bash
   # Check if you can run docker without sudo:
   docker ps
   
   # If that fails with permission denied, even though you're in docker group:
   # - Disconnect and reconnect SSH (or start a new session)
   # - Group membership changes require a new login session
   
   # If you're not in docker group, add your user (requires logout/login):
   # sudo usermod -aG docker $USER
   # Then disconnect and reconnect SSH
   ```

**Note:** If SPIRE runs as a non-root user (recommended), you typically don't need `sudo` for kind operations. The `setup-spire.sh` script sets appropriate socket permissions (666) so containers can access the agent socket.

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
- Configures agent with both `unix` and `k8s` workload attestors
- Creates necessary sockets accessible to the cluster

### Step 2: Verify SPIRE Setup

After running `setup-spire.sh`, verify everything is running:

```bash
# Check processes
ps aux | grep -E "spire-server|spire-agent|keylime" | grep -v grep

# Check sockets
ls -la /tmp/spire-server/private/api.sock
ls -la /tmp/spire-agent/public/api.sock

# Check agent joined successfully
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1
./spire/bin/spire-server agent list -socketPath /tmp/spire-server/private/api.sock

# Check logs
tail -f /tmp/spire-server.log | grep "Unified-Identity"
tail -f /tmp/spire-agent.log | grep "Unified-Identity"
```

**Note:** The agent may take 30-60 seconds to fully join and create the workload API socket. If the socket doesn't appear immediately, wait and check the logs.

### Step 3: Create Kubernetes Cluster with Socket Mount

The kind cluster is created with the agent socket mounted:

**Note:** If SPIRE is running as a non-root user (recommended) and your user is in the `docker` group, you don't need `sudo` for kind.

**Check Docker access:**
```bash
# Test if you can run docker without sudo
docker ps

# If that fails with permission denied, even though you're in docker group:
# - Disconnect and reconnect SSH (or start a new session)
# - Group membership changes require a new login session

# If you're not in docker group, add your user (requires logout/login):
# sudo usermod -aG docker $USER
# Then disconnect and reconnect SSH
```

**Create the cluster:**
```bash
# If docker works without sudo (recommended):
kind create cluster --name aegis-spire --config - << 'EOF'
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

# OR if you need sudo (only if not in docker group):
# sudo kind create cluster --name aegis-spire --config - << 'EOF'
# ... (same config as above)
# EOF
```

**Important:** After creating the cluster, set up the kubeconfig:

**Option A: Using the helper script (recommended):**
```bash
cd k8s-integration
./setup-kubeconfig.sh aegis-spire
export KUBECONFIG=/tmp/kubeconfig-kind.yaml
```

**Option B: Manual setup:**
```bash
# Save kind kubeconfig to expected location
# Try without sudo first (if cluster was created without sudo):
kind get kubeconfig --name aegis-spire > /tmp/kubeconfig-kind.yaml

# OR if cluster was created with sudo:
# sudo kind get kubeconfig --name aegis-spire > /tmp/kubeconfig-kind.yaml
# sudo chown $USER:$USER /tmp/kubeconfig-kind.yaml

# Export KUBECONFIG environment variable
export KUBECONFIG=/tmp/kubeconfig-kind.yaml

# Verify cluster access
kubectl cluster-info --context kind-aegis-spire
```

### Step 4: Create Registration Entry

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

### Step 5: Deploy Test Workload

For Phase 1 testing, we can use a simple hostPath mount to access the agent socket:

```bash
export KUBECONFIG=/tmp/kubeconfig-kind.yaml
kubectl apply -f workloads/test-workload-simple.yaml
```

### Step 6: Test Workload Attestors

Test both `unix` and `k8s` workload attestors:

```bash
cd k8s-integration
./test-workload-attestors.sh
```

This script:
- Verifies SPIRE Server and Agent are running
- Tests `unix` workload attestor by creating a registration entry with `unix:uid` selector
- Tests `k8s` workload attestor by creating a registration entry with `k8s:ns` and `k8s:sa` selectors (if Kubernetes cluster exists)
- Verifies both attestors are loaded in agent logs
- Provides cleanup commands for test entries

**Expected Output:**
- ✓ Unix workload attestor: Tested
- ✓ K8s workload attestor: Tested (if cluster exists)

### Step 7: Test Sovereign SVID Generation (Optional)

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

