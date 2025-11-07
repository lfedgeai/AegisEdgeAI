# Unified-Identity - Phase 1: Kubernetes Integration with SPIRE CSI Driver

**⚠️ STATUS: PENDING**

This directory contains the setup for testing sovereign SVID generation with Kubernetes workloads using the SPIRE CSI driver, while SPIRE Server and Agent run **outside** the Kubernetes cluster for security.

**Note**: Kubernetes integration is currently pending resolution of CSI driver image pull issues. For a working Phase 1 demo, see the Python app demo in `../python-app-demo/` which demonstrates the complete end-to-end flow.

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

**Note:** SPIRE runs as a non-root user. With proper Docker permissions (user in `docker` group), you don't need `sudo` for kind operations. The `setup-spire.sh` script sets appropriate socket permissions (666) so containers can access the agent socket.

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
ps aux | grep -E "spire-server|spire-agent|keylime|go run main.go" | grep -v grep

# Check SPIRE sockets
ls -la /tmp/spire-server/private/api.sock
ls -la /tmp/spire-agent/public/api.sock

# Check Keylime stub is running and listening
if pgrep -f "go run main.go" > /dev/null 2>&1 || pgrep -f "keylime-stub" > /dev/null 2>&1; then
    echo "✓ Keylime stub process is running"
else
    echo "⚠ Keylime stub process not found"
fi

# Check Keylime stub port (8888) is listening
if netstat -tlnp 2>/dev/null | grep -q ":8888" || ss -tlnp 2>/dev/null | grep -q ":8888"; then
    echo "✓ Keylime stub is listening on port 8888"
else
    echo "⚠ Keylime stub port 8888 not listening"
fi

# Test Keylime stub endpoint (optional)
curl -s -X POST http://localhost:8888/v2.4/verify/evidence \
  -H "Content-Type: application/json" \
  -d '{"data": {"nonce": "test"}}' > /dev/null 2>&1 && \
  echo "✓ Keylime stub endpoint responding" || \
  echo "⚠ Keylime stub endpoint not responding"

# Check agent joined successfully
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1
./spire/bin/spire-server agent list -socketPath /tmp/spire-server/private/api.sock

# Check logs
tail -f /tmp/spire-server.log | grep "Unified-Identity"
tail -f /tmp/spire-agent.log | grep "Unified-Identity"
tail -f /tmp/keylime-stub.log | grep "Unified-Identity"
```

**Note:** The agent may take 30-60 seconds to fully join and create the workload API socket. If the socket doesn't appear immediately, wait and check the logs.

**Important:** 
- The agent is configured with `use_anonymous_authentication = true`, which allows it to start without a Kubernetes cluster. Once the cluster is created (Step 3), the agent will **dynamically discover and use it** - **no restart needed** if the agent is already running.
- The Keylime stub should be running and listening on port 8888. If it's not running, check `/tmp/keylime-stub.log` for errors and restart it if needed.

**Troubleshooting:**
- If the agent failed to start, check `/tmp/spire-agent.log` for errors
- If you need to rejoin the agent, use: `./rejoin-agent.sh`

### Step 3: Create Kubernetes Cluster with Socket Mount

**Note:** The agent will automatically discover and use the cluster once it's created - **no restart needed** if the agent is already running (from Step 1).

Create the kind cluster with the SPIRE Agent socket mounted:

```bash
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
```

**Note:** If you're in the `docker` group (which you should be), you don't need `sudo` for kind commands.

**Set up kubeconfig:**

After creating the cluster, configure kubectl:

```bash
# Using the helper script (recommended):
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/k8s-integration
./setup-kubeconfig.sh aegis-spire
export KUBECONFIG=/tmp/kubeconfig-kind.yaml

# Verify cluster access
kubectl cluster-info --context kind-aegis-spire
```

**Verify Agent is Running:**

```bash
# Check if agent is running
ps aux | grep spire-agent | grep -v grep

# If not running, use the rejoin script:
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/k8s-integration
./rejoin-agent.sh
```

### Step 4: Create Registration Entry

First, get the agent SPIFFE ID:

```bash
export KUBECONFIG=/tmp/kubeconfig-kind.yaml

# Get the agent SPIFFE ID
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/spire
AGENT_SPIFFE_ID=$(./bin/spire-server agent list -socketPath /tmp/spire-server/private/api.sock 2>&1 | \
    grep "SPIFFE ID" | awk -F': ' '/SPIFFE ID/ {print $2}' | awk '{print $1}' | head -1)

echo "Agent SPIFFE ID: $AGENT_SPIFFE_ID"
```

Then create the registration entry:

```bash
# Create registration entry for test workload
./bin/spire-server entry create \
    -spiffeID spiffe://example.org/workload/test-k8s \
    -parentID "$AGENT_SPIFFE_ID" \
    -selector k8s:ns:default \
    -selector k8s:sa:test-workload
```

**Note:** The `parentID` must match the actual agent SPIFFE ID from `spire-server agent list`. The agent ID format is typically `spiffe://example.org/spire/agent/join_token/<token>`.

### Step 5: Deploy Test Workload

**Option A: Simple hostPath Mount (Recommended for Phase 1 Testing)**

This option mounts the SPIRE Agent socket directly via hostPath:

This is the simplest approach and works immediately without CSI driver:

```bash
export KUBECONFIG=/tmp/kubeconfig-kind.yaml
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/k8s-integration

# Deploy workload using simple hostPath mount
kubectl apply -f workloads/test-workload-simple.yaml

# Verify the pod is running
kubectl get pods -l app=test-sovereign-workload

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=test-sovereign-workload --timeout=60s
```

**Option B: SPIRE CSI Driver (Production Pattern - Pending Image Resolution)**

**Note:** The CSI driver image `ghcr.io/spiffe/spire-csi-driver:0.4.0` currently has image pull issues. This option is documented for future use once the image issue is resolved.

```bash
export KUBECONFIG=/tmp/kubeconfig-kind.yaml
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/k8s-integration

# Deploy CSI driver (when image is available)
kubectl apply -f csi-driver/spire-csi-driver.yaml

# Wait for CSI driver to be ready
kubectl wait --for=condition=ready pod -l app=spire-csi-driver -n spire-system --timeout=60s

# Deploy workload using CSI driver
kubectl apply -f workloads/test-workload.yaml
```

**CSI Driver Status:** The image `ghcr.io/spiffe/spire-csi-driver:0.4.0` may require authentication or a different tag. Check the [SPIRE CSI Driver repository](https://github.com/spiffe/spire-csi-driver) for the latest available images and build instructions.

**Option C: Workload with SVID Files Mounted (Production Pattern for File-Based Apps)**

For applications that need SVID certificate, private key, and CA bundle as regular files (not just the socket), use `test-workload-with-svid-files.yaml`:

```bash
export KUBECONFIG=/tmp/kubeconfig-kind.yaml
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/k8s-integration

# Deploy workload with SVID files mounted
kubectl apply -f workloads/test-workload-with-svid-files.yaml

# Verify the pod is running
kubectl get pods -l app=test-sovereign-workload-with-files

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=test-sovereign-workload-with-files --timeout=60s
```

**How it works:**
- Uses an init container to fetch SVID from the workload API socket
- Writes SVID files to a shared `emptyDir` volume (in-memory for security)
- Main container mounts the volume read-only with files at:
  - `/svid-files/svid.pem` - SVID certificate
  - `/svid-files/svid.key` - SVID private key
  - `/svid-files/bundle.pem` - SPIRE CA bundle

**Note:** The example uses placeholder files. In production, use `spire-agent` or a Go client in the init container to fetch real SVID files from the workload API.

**Copying SVID files from pod:**
```bash
# Get pod name
POD_NAME=$(kubectl get pods -l app=test-sovereign-workload-with-files -o jsonpath='{.items[0].metadata.name}')

# Copy SVID files
kubectl cp default/$POD_NAME:/svid-files/svid.pem /tmp/svid.pem
kubectl cp default/$POD_NAME:/svid-files/svid.key /tmp/svid.key
kubectl cp default/$POD_NAME:/svid-files/bundle.pem /tmp/bundle.pem
```

### Step 6: Dump SVID from Workload Pod

After the workload is running, dump the SVID using the simple kubectl exec approach:

```bash
export KUBECONFIG=/tmp/kubeconfig-kind.yaml
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/k8s-integration

# Use the simple kubectl exec script (recommended - easiest method)
./scripts/dump-svid-kubectl-exec.sh test-sovereign-workload default /tmp/k8s-svid-dump

# View the SVID with Phase 1 highlights
cd ../scripts
./dump-svid -cert /tmp/k8s-svid-dump/svid.crt
```

**Manual kubectl exec (if script doesn't work):**

```bash
# Get pod name
POD_NAME=$(kubectl get pods -l app=test-sovereign-workload -o jsonpath='{.items[0].metadata.name}')

# Copy spire-agent binary to pod
kubectl cp ../spire/bin/spire-agent default/$POD_NAME:/tmp/spire-agent
kubectl exec $POD_NAME -- chmod +x /tmp/spire-agent

# Fetch SVID
kubectl exec $POD_NAME -- /tmp/spire-agent api fetch -socketPath /run/spire/sockets/api.sock -write /tmp

# Copy SVID back to host
kubectl cp default/$POD_NAME:/tmp/svid.0.pem /tmp/k8s-svid.crt

# View SVID
cd ../scripts
./dump-svid -cert /tmp/k8s-svid.crt
```

### Step 7: Test Workload Attestors (Optional - Verification Only)

**Note:** This step is optional and is for verification/testing purposes only. Step 4 already creates the necessary Kubernetes workload registration entry. This step verifies that both workload attestors are properly configured and working.

Test both `unix` and `k8s` workload attestors:

```bash
cd k8s-integration
./test-workload-attestors.sh
```

This script:
- Verifies SPIRE Server and Agent are running
- Tests `unix` workload attestor by creating a test registration entry with `unix:uid` selector (for non-Kubernetes workloads)
- Tests `k8s` workload attestor by creating a test registration entry with `k8s:ns` and `k8s:sa` selectors (verifies the k8s attestor works, separate from Step 4's entry)
- Verifies both attestors are loaded in agent logs
- Provides cleanup commands for test entries

**Why this step?**
- Step 4 creates the registration entry for your actual workload
- Step 6 verifies that the workload attestors themselves are working correctly
- Useful for troubleshooting if workloads aren't getting SVIDs
- Tests the `unix` attestor (which Step 4 doesn't test)

**Expected Output:**
- ✓ Unix workload attestor: Tested
- ✓ K8s workload attestor: Tested (if cluster exists)

**You can skip this step** if you're confident the attestors are working and proceed directly to Step 8 to test SVID generation with your actual workload.

### Step 8: Test Sovereign SVID Generation (Optional)

**Note:** The `BatchNewX509SVID` API requires agent credentials for authorization. For Phase 1 testing, use Step 6 to verify SVID generation from workloads. See `TESTING_STATUS.md` for details.

**Option A: Generate SVID from Host (Requires Agent Credentials)**

**Status:** ⚠️ **API Authorization Limitation**

The `BatchNewX509SVID` API requires agent credentials (`allow_agent: true` in SPIRE authorization policy). Direct client calls will receive `PermissionDenied`. This is a security feature, not a bug.

**For Phase 1 Testing:**
- Use Step 6 (Dump SVID from Pod) - This demonstrates the complete workflow and works correctly
- The sovereign attestation code path is implemented and tested via unit tests
- For testing `AttestedClaims`, see `TESTING_STATUS.md` for workarounds

**If you want to test the API directly (advanced):**
```bash
# Get the entry ID created in Step 4
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/spire
ENTRY_ID=$(./bin/spire-server entry show -spiffeID spiffe://example.org/workload/test-k8s \
    -socketPath /tmp/spire-server/private/api.sock 2>&1 | \
    grep "Entry ID" | awk '{print $3}')

echo "Entry ID: $ENTRY_ID"

# Note: This will fail with PermissionDenied unless using agent credentials
cd ../scripts
./generate-sovereign-svid \
    -entryID "$ENTRY_ID" \
    -spiffeID spiffe://example.org/workload/test-k8s \
    -outputCert /tmp/svid.crt \
    -verbose
```

**Option B: Dump SVID from Kubernetes Pod**

**Note:** The pod image (`curlimages/curl`) is minimal and may not have required libraries. Automatic extraction may fail.

```bash
export KUBECONFIG=/tmp/kubeconfig-kind.yaml
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/k8s-integration

# Attempt to dump SVID from pod
./dump-svid-from-k8s.sh test-sovereign-workload default /tmp/k8s-svid-dump

# If successful, display it:
cd ../scripts
./dump-svid -cert /tmp/k8s-svid-dump/svid.crt
```

## SPIRE CSI Driver Details (Pending Image Resolution)

**Current Status:** The CSI driver image `ghcr.io/spiffe/spire-csi-driver:0.4.0` currently has image pull issues (403 Forbidden). For Phase 1 testing, use the simple hostPath mount option (Step 5, Option A).

**Production Pattern (When Image is Available):**

The SPIRE CSI driver provides the production pattern for injecting SPIFFE identities into Kubernetes workloads:

1. The CSI driver runs as a DaemonSet on each node
2. It connects to the external SPIRE Agent socket (mounted via kind's `extraMounts`)
3. Workloads request volumes using `csi.spiffe.io` driver
4. The CSI driver mounts the Workload API socket into the pod
5. Workloads can then fetch SVIDs via the Workload API

**Configuration:**
- CSI driver image: `ghcr.io/spiffe/spire-csi-driver:0.4.0` (pending resolution)
- Agent socket path: `/tmp/spire-agent/public/api.sock` (external, on host)
- Workload API socket: `/run/spire/sockets/workload_api.sock` (in pod)

**To Resolve CSI Driver Image Issue:**
- Check the [SPIRE CSI Driver repository](https://github.com/spiffe/spire-csi-driver) for:
  - Latest available image tags
  - Build instructions if you need to build from source
  - Authentication requirements for ghcr.io images

**For Phase 1 Testing:** Use the simple hostPath mount option (Step 5, Option A) which works immediately without CSI driver.

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

## Automated Testing

### Test All Critical Steps (1-6)

Run the automated Python test script to test all critical steps:

```bash
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/k8s-integration
python3 test-all-steps.py
```

This script:
1. **Cleans up** any existing setup (teardown, stop processes, delete cluster)
2. **Step 1**: Starts SPIRE (Server, Agent, Keylime Stub)
3. **Step 2**: Verifies SPIRE Setup (processes, sockets, Keylime stub)
4. **Step 3**: Creates Kubernetes Cluster with socket mount
5. **Step 4**: Creates Registration Entry
6. **Step 5**: Deploys Test Workload
7. **Step 6**: Dumps SVID from Workload Pod

**Output:**
- Color-coded success/warning/error messages
- Detailed verification at each step
- Summary at the end showing which steps passed/failed
- Exit code 0 if all steps pass, 1 if any step fails

**Example:**
```bash
$ python3 test-all-steps.py

╔════════════════════════════════════════════════════════════════╗
║  Unified-Identity - Phase 1: Automated Test Script             ║
║  Testing Steps 1-6 from Kubernetes Integration README          ║
╚════════════════════════════════════════════════════════════════╝

Step 0: Cleaning Up Existing Setup
  ✓ Cleanup complete

Step 1: Start SPIRE (Outside Kubernetes)
  ✓ SPIRE setup script completed

Step 2: Verify SPIRE Setup
  ✓ SPIRE Server is running
  ✓ SPIRE Agent is running
  ✓ SPIRE Server socket exists
  ✓ SPIRE Agent socket exists
  ✓ Keylime stub is listening on port 8888
  ✓ Agent joined successfully

... (continues through all steps)

Test Summary
  ✓ cleanup: PASSED
  ✓ step1: PASSED
  ✓ step2: PASSED
  ✓ step3: PASSED
  ✓ step4: PASSED
  ✓ step5: PASSED
  ✓ step6: PASSED

✅ All steps completed successfully!
```

## Cleanup

**Note:** Both teardown scripts (`teardown.sh` and `teardown-quick.sh`) now automatically clean up SPIRE registration entries as part of the cleanup process. This ensures a clean state for subsequent test runs.

### Full Teardown (Interactive)

The `teardown.sh` script provides a comprehensive cleanup with options:

```bash
cd k8s-integration
./teardown.sh
```

This script will:
1. **Delete Kubernetes workloads** - Removes test pods and service accounts
2. **Delete kind cluster** - Removes the Kubernetes cluster
3. **Clean up SPIRE registration entries** - Automatically deletes all registration entries
4. **Remove kubeconfig file** - Always removes `/tmp/kubeconfig-kind.yaml` (even if cluster was already deleted)
5. **Remove kubeconfig context** - Removes `kind-aegis-spire` context from `~/.kube/config`
6. **Remove admin.conf** - Removes `~/.kube/admin.conf` if it exists
7. **Stop SPIRE Agent** - Gracefully stops the agent process
8. **Stop SPIRE Server** - Gracefully stops the server process
9. **Stop Keylime Stub** - Stops the stub service
10. **Clean up sockets** - Removes Unix domain sockets
11. **Optional cleanup** - Prompts to remove log files and data directories

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

Step 3: Cleaning up SPIRE registration entries...
  Found 1 registration entries
    Deleted entry: <entry-id>
  ✓ Registration entries cleaned up

Step 4: Stopping SPIRE Agent...
  ✓ SPIRE Agent stopped

Step 5: Stopping SPIRE Server...
  ✓ SPIRE Server stopped

Step 6: Stopping Keylime Stub...
  ✓ Keylime Stub stopped

Step 7: Cleaning up sockets...
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
kind delete cluster --name aegis-spire

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

