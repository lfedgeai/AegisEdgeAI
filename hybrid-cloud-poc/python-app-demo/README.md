*** End Patch
# Unified-Identity: Python App Demo

This demo shows how a Python workload can fetch and use a Sovereign SVID with AttestedClaims from SPIRE Agent.

## Overview

This demo demonstrates the **workload SVID flow**, where a Python application:
1. Connects to SPIRE Agent Workload API
2. Receives a workload SVID with AttestedClaims
3. The workload SVID inherits TPM attestation claims from the agent SVID

**Components:**
1. **SPIRE Server** - Issues SVIDs with AttestedClaims (from Keylime Verifier)
2. **SPIRE Agent** - Provides Workload API to applications
3. **Keylime Verifier** - Validates TPM attestation and returns AttestedClaims
4. **Python App** - Fetches SVID and displays AttestedClaims

## Prerequisites

- Go installed (for SPIRE)
- Python 3 installed
- SPIRE binaries built
- All services running (SPIRE Server, SPIRE Agent, Keylime Verifier, rust-keylime Agent)

**Note:** This demo is typically run as part of the main integration test (`../test_complete.sh`), which sets up all required services.

### Install Python Dependencies

```bash
pip install -r requirements.txt
```

This installs:
- `grpcio` - gRPC library for Workload API
- `protobuf` - Protocol buffer support

## Quick Start

### As Part of Main Integration Test

The recommended way to run this demo is as part of the complete integration test:

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc
./test_complete.sh
```

This will:
- Set up all services (SPIRE Server, SPIRE Agent, Keylime Verifier, rust-keylime Agent)
- Create registration entry for the Python app
- Fetch workload SVID with AttestedClaims
- Verify the complete end-to-end flow

### Standalone Demo

If you want to run just the Python app demo (assuming services are already running):

#### Step 1: Create Registration Entry

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo
./create-registration-entry.sh
```

This creates a registration entry for your Python app based on your Unix UID.

#### Step 2: Fetch Sovereign SVID

**Recommended: Use the all-in-one demo script:**
```bash
./run-demo.sh
```

This script orchestrates all steps and uses the gRPC version (`fetch-sovereign-svid-grpc.py`) to get AttestedClaims.

**Or manually:**
```bash
python3 fetch-sovereign-svid-grpc.py
```

This will:
- Connect to SPIRE Agent Workload API via gRPC (direct access to AttestedClaims)
- Agent automatically attests the process and matches to registration entry
- Agent requests workload SVID from server (workloads inherit claims from agent SVID)
- Server returns `AttestedClaims` in response (from agent SVID)
- Agent passes `AttestedClaims` to the Python app
- Save the certificate to `/tmp/svid-dump/svid.pem`
- Save AttestedClaims to `/tmp/svid-dump/attested_claims.json`

#### Step 3: Dump SVID with AttestedClaims

```bash
../scripts/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem
```

### Manual mTLS Demo (Server and Client)

The `mtls-server-app.py` and `mtls-client-app.py` demonstrate automatic SVID renewal with mTLS connections. These apps automatically detect SVID renewals and update their TLS contexts.

**Modes:**
- **SPIRE Mode** (default): Uses SPIRE SVIDs with automatic renewal
- **Standard Cert Mode**: Uses standard X.509 certificates (no SPIRE required)

#### Prerequisites

**For SPIRE Mode:**
- SPIRE Agent running and accessible
- Registration entries created for both server and client workloads

**For Standard Cert Mode:**
- No SPIRE required

**Common:**
- Python dependencies installed: `pip install -r requirements.txt`
  - For SPIRE mode: `spiffe` library
  - For standard cert mode: `cryptography` library

#### Manual Launch (Linux)

**Option A: SPIRE Mode (Default)**

**Terminal 1: Start the Server**

```bash
cd python-app-demo

# Set environment variables
export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
export SERVER_PORT="9443"
export SERVER_LOG="/tmp/mtls-server-app.log"
# Optional: explicitly enable SPIRE mode
export SERVER_USE_SPIRE="true"

# Run the server (output goes to console)
python3 mtls-server-app.py
```

**Terminal 2: Start the Client**

```bash
cd python-app-demo

# Set environment variables
export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
export SERVER_HOST="localhost"    # Or remote server IP/hostname (default: 10.1.0.10 for mixed mode)
export SERVER_PORT="9443"
export CLIENT_LOG="/tmp/mtls-client-app.log"
# Optional: explicitly enable SPIRE mode
export CLIENT_USE_SPIRE="true"

# Run the client (output goes to console)
python3 mtls-client-app.py
```

**Running Across Different Machines:**
- Start the server on the remote host (it binds to `0.0.0.0` by default and listens on `SERVER_PORT`).
- On the client machine, set `SERVER_HOST` to the server's IP/hostname (default: `10.1.0.10` for mixed mode).
- Default IP addresses for mixed mode:
  - **Server**: `10.1.0.10`
  - **Client**: `10.1.0.11`
- Ensure firewall rules allow inbound connections to `SERVER_PORT` (default `9443`) on the server host.
- In mixed mode, also ensure `CA_CERT_PATH` on the client points to the correct server certificate file when verifying a remote server.
- Copy the server's certificate from the server machine to the client machine: `scp user@10.1.0.10:~/.mtls-demo/server-cert.pem ~/.mtls-demo/server-cert.pem`

**Option B: Standard Certificate Mode (No SPIRE Required)**

**Terminal 1: Start the Server**

```bash
cd python-app-demo

# Set environment variables
export SERVER_PORT="9443"
export SERVER_LOG="/tmp/mtls-server-app.log"
export SERVER_USE_SPIRE="false"  # Disable SPIRE, use standard certs

# Optional: Provide custom certificate paths
# export SERVER_CERT_PATH="/path/to/server-cert.pem"
# export SERVER_KEY_PATH="/path/to/server-key.pem"
# export CA_CERT_PATH="/path/to/ca-cert.pem"

# Run the server (output goes to console)
python3 mtls-server-app.py
```

**Terminal 2: Start the Client**

```bash
cd python-app-demo

# Set environment variables
export SERVER_HOST="localhost"
export SERVER_PORT="9443"
export CLIENT_LOG="/tmp/mtls-client-app.log"
export CLIENT_USE_SPIRE="false"  # Disable SPIRE, use standard certs

# Optional: Provide custom certificate paths
# export CLIENT_CERT_PATH="/path/to/client-cert.pem"
# export CLIENT_KEY_PATH="/path/to/client-key.pem"
# export CA_CERT_PATH="/path/to/ca-cert.pem"  # For server verification

# Run the client (output goes to console)
python3 mtls-client-app.py
```

**Note:** In standard cert mode, if certificate paths are not provided, the apps will automatically generate self-signed certificates in `~/.mtls-demo/`. The server and client will use these certificates for mTLS.

**Option C: Mixed Mode (SPIRE Client + Standard Cert Server)**

This mode allows a SPIRE-enabled client to connect to a server using standard certificates. This is useful for gradual migration or when the server doesn't have SPIRE access.

**Prerequisites:**
- SPIRE Agent running (for the client)
- Server can run without SPIRE

**Step-by-Step Instructions:**

**Step 1: Extract SPIRE CA Bundle (Optional - for strict client verification)**

If you want the server to strictly verify SPIRE-issued client certificates, first extract the SPIRE CA bundle:

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo

# Extract SPIRE trust bundle
# Default: connect to SPIRE Agent via Unix socket on the same machine
python3 fetch-spire-bundle.py

# This will create /tmp/spire-bundle.pem by default
# Or specify custom path:
# BUNDLE_OUTPUT_PATH="/path/to/spire-bundle.pem" python3 fetch-spire-bundle.py

# Advanced: If SPIRE Agent is reachable over TCP on another machine:
#   export SPIRE_AGENT_SOCKET="tcp://<AGENT_IP>:<PORT>"
#   python3 fetch-spire-bundle.py
# (Only recommended if your SPIRE deployment exposes the Workload API over TCP securely)
```

**Step 2: Start the Server (Standard Cert Mode)**

Open Terminal 1:

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo

# Set environment variables
export SERVER_USE_SPIRE="false"
export SERVER_PORT="9443"
export SERVER_LOG="/tmp/mtls-server-app.log"

# Optional: Provide SPIRE CA bundle for strict client verification
# First, extract the SPIRE bundle (if you haven't already):
# python3 fetch-spire-bundle.py
#
# Then provide it to the server:
export CA_CERT_PATH="/tmp/spire-bundle.pem"

# Run the server
python3 mtls-server-app.py
```

**Note:** 
- **Without `CA_CERT_PATH`**: Server accepts any client certificate (permissive mode)
- **With `CA_CERT_PATH` pointing to SPIRE bundle**: Server strictly verifies SPIRE-issued client certificates
- To extract the SPIRE bundle, run: `python3 fetch-spire-bundle.py` (creates `/tmp/spire-bundle.pem` by default)

**Expected Server Output (without CA_CERT_PATH):**
```
╔════════════════════════════════════════════════════════════════╗
║  mTLS Server Starting with Standard Certificates               ║
╚════════════════════════════════════════════════════════════════╝
Listening on port: 9443

  Mode: Standard Certificates (no SPIRE)
  Accepts: SPIRE and standard client certificates (mixed mode supported)
  ⚠ Client verification: Permissive (accepts any client cert)
  ℹ For strict verification, provide CA_CERT_PATH with SPIRE CA

Setting up TLS context with standard certificates...
  Using existing certificates: /home/mw/.mtls-demo/server-cert.pem, /home/mw/.mtls-demo/server-key.pem
  ⚠ No CA certificate provided
  ℹ Mixed mode: Accepting client certificates (including SPIRE-issued)
  ℹ Note: For strict verification, provide CA_CERT_PATH with SPIRE CA
  ✓ Standard TLS context configured

╔════════════════════════════════════════════════════════════════╗
║  Server Ready - Waiting for mTLS Connections                   ║
╚════════════════════════════════════════════════════════════════╝
  Standard certificate mode (no SPIRE)
  No automatic renewal (certificates are static)
```

**Expected Server Output (with CA_CERT_PATH for strict verification):**
```
╔════════════════════════════════════════════════════════════════╗
║  mTLS Server Starting with Standard Certificates               ║
╚════════════════════════════════════════════════════════════════╝
Listening on port: 9443

  Mode: Standard Certificates (no SPIRE)
  Accepts: SPIRE and standard client certificates (mixed mode supported)
  ✓ Client verification: Strict (using SPIRE CA bundle)

Setting up TLS context with standard certificates...
  Using existing certificates: /home/mw/.mtls-demo/server-cert.pem, /home/mw/.mtls-demo/server-key.pem
  ✓ CA certificate loaded for client verification: /tmp/spire-bundle.pem
  ✓ Standard TLS context configured

╔════════════════════════════════════════════════════════════════╗
║  Server Ready - Waiting for mTLS Connections                   ║
╚════════════════════════════════════════════════════════════════╝
  Standard certificate mode (no SPIRE)
  No automatic renewal (certificates are static)
```

**Step 3: Start the Client (SPIRE Mode)**

Open Terminal 2:

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo

# Set environment variables
export CLIENT_USE_SPIRE="true"
export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
export SERVER_HOST="localhost"
export SERVER_PORT="9443"
export CLIENT_LOG="/tmp/mtls-client-app.log"

# IMPORTANT: Provide server's CA certificate for verification
# The server uses a self-signed certificate, so provide the server cert itself
export CA_CERT_PATH="~/.mtls-demo/server-cert.pem"

# Alternative: Use absolute path
# export CA_CERT_PATH="/home/mw/.mtls-demo/server-cert.pem"

# Run the client
python3 mtls-client-app.py
```

**Client and Server on Different Machines:**

For the mixed mode scenario where the client and server run on different machines, use the following configuration:

**On Server Machine (IP: 10.1.0.10):**

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo

# Set environment variables
export SERVER_USE_SPIRE="false"
export SERVER_PORT="9443"
export SERVER_LOG="/tmp/mtls-server-app.log"

# Optional: For strict SPIRE client verification, provide SPIRE CA bundle
# First, copy the SPIRE bundle to this machine (from a machine with SPIRE Agent):
#   scp user@CLIENT_IP:/tmp/spire-bundle.pem /tmp/spire-bundle.pem
# Then:
export CA_CERT_PATH="/tmp/spire-bundle.pem"

# Run the server
python3 mtls-server-app.py
```

**On Client Machine (IP: 10.1.0.11):**

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo

# First, copy the server's certificate from the server machine:
mkdir -p ~/.mtls-demo
scp user@10.1.0.10:~/.mtls-demo/server-cert.pem ~/.mtls-demo/server-cert.pem

# Set environment variables
export CLIENT_USE_SPIRE="true"
export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
export SERVER_HOST="10.1.0.10"  # Server machine IP
export SERVER_PORT="9443"
export CLIENT_LOG="/tmp/mtls-client-app.log"

# IMPORTANT: Provide server's CA certificate for verification
export CA_CERT_PATH="~/.mtls-demo/server-cert.pem"

# Run the client
python3 mtls-client-app.py
```

**Key Points for Different Machines:**
- **Server IP**: Default `10.1.0.10` (set `SERVER_HOST` on client to this IP)
- **Client IP**: Default `10.1.0.11` (where SPIRE Agent runs)
- **Server certificate**: Must be copied from server machine (`~/.mtls-demo/server-cert.pem`) to client machine
- **SPIRE bundle**: Must be extracted on a machine with SPIRE Agent, then copied to server machine for strict client verification
- **Firewall**: Ensure port `9443` (or your `SERVER_PORT`) is open on the server machine
- **Both sides need to trust each other**: Client needs server cert, server needs SPIRE bundle (for strict verification)

**Expected Client Output:**
```
╔════════════════════════════════════════════════════════════════╗
║  mTLS Client Starting with SPIRE SVID (Automatic Renewal)      ║
╚════════════════════════════════════════════════════════════════╝
SPIRE Agent socket: /tmp/spire-agent/public/api.sock
Server: localhost:9443

  Mode: SPIRE (automatic SVID renewal enabled)
  Can connect to: SPIRE and standard certificate servers
  ✓ Server CA provided: /home/mw/.mtls-demo/server-cert.pem (for standard cert servers)

Got initial SVID: spiffe://example.org/mtls-client
  Initial Certificate Serial: 1234567890
  Certificate Expires: 2025-11-29 03:55:32
  Monitoring for automatic SVID renewal...
  ✓ Loaded trust bundle with 4 CA certificate(s)
  ✓ SPIRE trust bundle loaded into SSL context
  ✓ Additional CA certificate loaded: /home/mw/.mtls-demo/server-cert.pem
  ℹ Mixed mode: SPIRE client can verify standard cert servers

Connecting to localhost:9443...
  ℹ Mixed mode: Server using standard certificate, Client using SPIRE certificate
  ✓ Server CA provided - verification should succeed
✓ Connected to server
📤 Sending: HELLO #1
📥 Received: SERVER ACK: HELLO #1
```

**Step 4: Verify Connection (Optional)**

You should see:
- **Server logs**: `✓ New TLS client connected from 127.0.0.1:xxxxx` followed by `ℹ Mixed mode: Client using SPIRE certificate, Server using standard certificate`
- **Client logs**: Successful connection and message exchange

**Troubleshooting:**

1. **If client fails with `CERTIFICATE_VERIFY_FAILED`:**
   - Ensure `CA_CERT_PATH` points to the server's certificate file
   - Check that the path is correct: `ls -la ~/.mtls-demo/server-cert.pem`
   - Use absolute path if `~` expansion doesn't work: `/home/mw/.mtls-demo/server-cert.pem`

2. **If server shows `TLSV1_ALERT_UNKNOWN_CA`:**
   - This is normal initially - the server accepts SPIRE client certs without strict verification
   - For strict verification:
     1. Extract SPIRE bundle: `python3 fetch-spire-bundle.py`
     2. Set `CA_CERT_PATH="/tmp/spire-bundle.pem"` on the server
     3. Restart the server with the CA_CERT_PATH set

3. **To find the server certificate location:**
   ```bash
   ls -la ~/.mtls-demo/
   # Should show: server-cert.pem, server-key.pem
   ```

4. **To extract SPIRE CA bundle for server verification:**
   ```bash
   cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo
   python3 fetch-spire-bundle.py
   # Creates /tmp/spire-bundle.pem by default
   # Then use it: export CA_CERT_PATH="/tmp/spire-bundle.pem"
   ```

**Note:** In mixed mode:
- The client uses SPIRE SVIDs for its certificate (with automatic renewal)
- The client verifies the server's standard certificate using the CA provided via `CA_CERT_PATH` (server's cert)
- The server accepts client certificates (including SPIRE-issued ones) without strict verification unless `CA_CERT_PATH` is provided with the SPIRE CA bundle
- To enable strict server verification of SPIRE clients:
  1. Extract SPIRE bundle: `python3 fetch-spire-bundle.py`
  2. Set `CA_CERT_PATH="/tmp/spire-bundle.pem"` on the server
- Both sides automatically detect and log the mixed mode configuration

**Terminal 3: Monitor Logs (Optional)**

```bash
# Monitor both logs
tail -f /tmp/mtls-server-app.log /tmp/mtls-client-app.log

# Or monitor individually
tail -f /tmp/mtls-server-app.log
tail -f /tmp/mtls-client-app.log
```

#### Manual Launch (Windows)

**Option A: SPIRE Mode**

**PowerShell Terminal 1: Start the Server**

```powershell
cd python-app-demo

# Set environment variables for Windows
$env:SPIRE_AGENT_SOCKET = "\\.\pipe\spire-agent\public\api"
$env:SERVER_PORT = "9443"
$env:SERVER_LOG = "C:\temp\mtls-server-app.log"
# Optional: explicitly enable SPIRE mode
$env:SERVER_USE_SPIRE = "true"

# Run the server
python mtls-server-app.py
```

**PowerShell Terminal 2: Start the Client**

```powershell
cd python-app-demo

# Set environment variables
$env:SPIRE_AGENT_SOCKET = "\\.\pipe\spire-agent\public\api"
$env:SERVER_HOST = "localhost"
$env:SERVER_PORT = "9443"
$env:CLIENT_LOG = "C:\temp\mtls-client-app.log"
# Optional: explicitly enable SPIRE mode
$env:CLIENT_USE_SPIRE = "true"

# Run the client
python mtls-client-app.py
```

**Note:** The named pipe path format may vary. Check your SPIRE Agent configuration for the exact path.

**Option B: Standard Certificate Mode (No SPIRE Required)**

**PowerShell Terminal 1: Start the Server**

```powershell
cd python-app-demo

# Set environment variables
$env:SERVER_PORT = "9443"
$env:SERVER_LOG = "C:\temp\mtls-server-app.log"
$env:SERVER_USE_SPIRE = "false"  # Disable SPIRE, use standard certs

# Optional: Provide custom certificate paths
# $env:SERVER_CERT_PATH = "C:\path\to\server-cert.pem"
# $env:SERVER_KEY_PATH = "C:\path\to\server-key.pem"
# $env:CA_CERT_PATH = "C:\path\to\ca-cert.pem"

# Run the server
python mtls-server-app.py
```

**PowerShell Terminal 2: Start the Client**

```powershell
cd python-app-demo

# Set environment variables
$env:SERVER_HOST = "localhost"
$env:SERVER_PORT = "9443"
$env:CLIENT_LOG = "C:\temp\mtls-client-app.log"
$env:CLIENT_USE_SPIRE = "false"  # Disable SPIRE, use standard certs

# Optional: Provide custom certificate paths
# $env:CLIENT_CERT_PATH = "C:\path\to\client-cert.pem"
# $env:CLIENT_KEY_PATH = "C:\path\to\client-key.pem"
# $env:CA_CERT_PATH = "C:\path\to\ca-cert.pem"  # For server verification

# Run the client
python mtls-client-app.py
```

**Note:** In standard cert mode, if certificate paths are not provided, the apps will automatically generate self-signed certificates in `%USERPROFILE%\.mtls-demo\` (Windows) or `~/.mtls-demo/` (Linux).

#### Default Environment Variables

If environment variables are not set, the apps use these defaults:

**Server:**
- `SPIRE_AGENT_SOCKET`: `/tmp/spire-agent/public/api.sock` (Linux) or `\\.\pipe\spire-agent\public\api` (Windows)
- `SERVER_PORT`: `9443`
- `SERVER_LOG`: `/tmp/mtls-server-app.log` (Linux) or `C:\temp\mtls-server-app.log` (Windows)
- `SERVER_USE_SPIRE`: Auto-detect (uses SPIRE if socket exists and spiffe library available, otherwise standard cert mode)
- `SERVER_CERT_PATH`: Auto-generate in `~/.mtls-demo/server-cert.pem` (standard mode only)
- `SERVER_KEY_PATH`: Auto-generate in `~/.mtls-demo/server-key.pem` (standard mode only)
- `CA_CERT_PATH`: Optional (for client verification in standard mode)

**Client:**
- `SPIRE_AGENT_SOCKET`: `/tmp/spire-agent/public/api.sock` (Linux) or `\\.\pipe\spire-agent\public\api` (Windows)
- `SERVER_HOST`: `localhost`
- `SERVER_PORT`: `9443`
- `CLIENT_LOG`: `/tmp/mtls-client-app.log` (Linux) or `C:\temp\mtls-client-app.log` (Windows)
- `CLIENT_USE_SPIRE`: Auto-detect (uses SPIRE if socket exists and spiffe library available, otherwise standard cert mode)
- `CLIENT_CERT_PATH`: Auto-generate in `~/.mtls-demo/client-cert.pem` (standard mode only)
- `CLIENT_KEY_PATH`: Auto-generate in `~/.mtls-demo/client-key.pem` (standard mode only)
- `CA_CERT_PATH`: Optional (for server verification in standard mode)

#### Cleanup

To stop and clean up all mTLS processes:

```bash
cd python-app-demo
./cleanup-mtls-app.sh
```

This script will:
- Kill all `mtls-server-app.py` and `mtls-client-app.py` processes (including background processes)
- Clean up PID files
- Free up the server port
- Remove log files (by default)
- Verify cleanup completion

**To keep log files during cleanup:**

```bash
CLEAN_LOGS=0 ./cleanup-mtls-app.sh
```

**Custom configuration:**

```bash
SERVER_PORT=8443 \
SERVER_PID_FILE=/tmp/my-server.pid \
CLIENT_PID_FILE=/tmp/my-client.pid \
./cleanup-mtls-app.sh
```

#### SVID Renewal Behavior

Both the server and client apps automatically detect SVID renewals and update their TLS contexts. When a renewal occurs:

1. **Server**: Detects renewal, updates TLS context, and closes existing connections to force clients to reconnect with new certificates
2. **Client**: Detects renewal, recreates TLS context, and reconnects to the server

You'll see renewal events logged with clear markers:
```
╔════════════════════════════════════════════════════════════════╗
║  🔄 SVID RENEWAL DETECTED - RENEWAL BLIP EVENT                  ║
╚════════════════════════════════════════════════════════════════╝
```

#### Default SVID Renewal Times

##### SPIRE Agent SVID Renewal

**Default Configuration:**
- **Agent SVID lifetime**: 1 hour (from SPIRE Server `agent_ttl`, which defaults to `default_x509_svid_ttl`)
- **Default renewal strategy** (when `availability_target` is not set):
  - Renews at **1/2 of SVID lifetime** (30 minutes for a 1-hour SVID)
  - Includes **±10% jitter** to spread out renewal requests and avoid spikes
  - Example: For a 1-hour SVID, renewal occurs between 27-33 minutes (30 minutes ± 3 minutes jitter)

**With `availability_target` Configured:**
- **Renewal trigger**: Agent rotates the SVID when remaining lifetime reaches the `availability_target` value
- **Grace period requirement**: For `availability_target` to be guaranteed, the grace period (`SVID lifetime - availability_target`) must be **at least 12 hours**
- **Fallback behavior**: If grace period < 12 hours, agent falls back to default rotation strategy (1/2 lifetime)
- **Jitter**: When using `availability_target`, jitter is 0 to +10 minutes added to the target time
- **Minimum `availability_target`**:
  - **30 seconds** when Unified-Identity feature is enabled
  - **24 hours** when Unified-Identity feature is disabled (legacy compatibility)

**Examples:**
- **1-hour SVID, no `availability_target`**: Renews at ~30 minutes (with jitter: 27-33 minutes)
- **1-hour SVID, `availability_target = "30s"`**: Falls back to default (grace period < 12h), renews at ~30 minutes
- **24-hour SVID, `availability_target = "30s"`**: Renews when 30 seconds remain (grace period = 23h 59m 30s > 12h ✓)
- **24-hour SVID, `availability_target = "1h"`**: Renews when 1 hour remains (grace period = 23h > 12h ✓)

##### Workload SVID Renewal (Client/Server Apps)

**Default Configuration:**
- **Workload SVID lifetime**: 1 hour (from SPIRE Server `default_x509_svid_ttl`)
- **Renewal strategy**: Uses the same strategy as agent SVIDs
  - If `availability_target` is set in agent config, workload SVIDs use it
  - If not set, workload SVIDs use default rotation (1/2 lifetime with jitter)
- **Applies to**: X509-SVIDs only (JWT-SVIDs are not affected by `availability_target`)

**Renewal Behavior:**
- Workload SVIDs follow the agent's `availability_target` setting
- Same jitter and fallback rules apply as agent SVIDs
- Apps using SPIRE Workload API automatically receive renewed SVIDs

##### Demo Configuration

The demo configuration (`spire-agent.conf`) sets `availability_target = "30s"` for fast renewal demonstrations. However, with default 1-hour SVID lifetimes, this falls back to the default rotation strategy (30 minutes) because the grace period requirement (12 hours) is not met.

To see true `availability_target` behavior in demos:
- Use longer SVID lifetimes (e.g., 24 hours) with `agent_ttl` or `default_x509_svid_ttl` in server config
- Or accept that with 1-hour SVIDs, renewals occur at ~30 minutes regardless of `availability_target` setting

##### Summary Table

| Configuration | SVID Lifetime | `availability_target` | Grace Period | Actual Renewal Time |
|--------------|---------------|----------------------|--------------|---------------------|
| Default | 1h | Not set | N/A | ~30 min (1/2 lifetime ± jitter) |
| Demo | 1h | 30s | 59m 30s | ~30 min (falls back, grace < 12h) |
| Production | 24h | 1h | 23h | When 1h remains (grace > 12h ✓) |
| Production | 24h | 30s | 23h 59m 30s | When 30s remains (grace > 12h ✓) |

**Key Points:**
- `availability_target` only takes effect if grace period ≥ 12 hours
- Default rotation (1/2 lifetime) applies when `availability_target` is not set or grace period is insufficient
- Jitter is always applied to prevent renewal spikes
- Both agent SVIDs and workload X509-SVIDs use the same renewal strategy

## Files

- `run-demo.sh` - **All-in-one demo script** (recommended - orchestrates all steps)
- `create-registration-entry.sh` - Creates registration entry for the Python app
- `fetch-sovereign-svid-grpc.py` - **Fetches sovereign SVID with AttestedClaims via gRPC** (recommended)
- `fetch-sovereign-svid.py` - Alternative using `spiffe` library (fallback)
- `fetch-svid.py` - Basic SVID fetch without AttestedClaims
- `mtls-server-app.py` - **mTLS server with automatic SVID renewal** (see Manual mTLS Demo)
- `mtls-client-app.py` - **mTLS client with automatic SVID renewal** (see Manual mTLS Demo)
- `cleanup-mtls-app.sh` - **Cleanup script for mTLS processes** (kills background processes, cleans logs)
- `spire-server.conf` - SPIRE Server configuration
- `spire-agent.conf` - SPIRE Agent configuration
- `generate-proto-stubs.sh` - Generates Python protobuf stubs from workload.proto

## How It Works

1. **SPIRE Server** runs with the `Unified-Identity` feature flag enabled
2. **SPIRE Agent** connects to the server and provides the Workload API
3. **Python App** communicates **only with SPIRE Agent** via Workload API (gRPC):
   - Connects to Agent's Workload API socket (`/tmp/spire-agent/public/api.sock`)
   - Agent automatically attests the Python process (extracts UID, etc.)
   - Agent matches selectors to registration entry
   - Agent requests workload SVID from server (workloads inherit claims from agent SVID)
   - Server returns `AttestedClaims` from agent SVID (no Keylime verification for workloads)
   - Agent passes `AttestedClaims` to the Python app via Workload API
4. **dump-svid** script displays the SVID and highlights AttestedClaims

**Important Notes:**
- The Python app does NOT communicate directly with SPIRE Server. All communication goes through the SPIRE Agent Workload API.
- **Workload SVID requests skip Keylime verification** - workloads inherit attested claims from the agent SVID
- The agent SVID contains TPM attestation claims (geolocation, TPM attestation) from Keylime Verifier
- The workload SVID certificate chain includes the agent SVID, allowing policy enforcement based on both workload and agent identity

**✅ Verified**: The complete flow is working end-to-end. AttestedClaims are successfully passed from Keylime Verifier → SPIRE Server (agent SVID) → SPIRE Agent → Python App (workload SVID).

## AttestedClaims

The AttestedClaims in the workload SVID are inherited from the agent SVID, which includes:

- **Geolocation** (`grc.geolocation`):
  - Type: `mobile` or `gnss`
  - Sensor ID: e.g., `12d1:1433` (mobile device)
  - TPM-attested location (bound to PCR 17)
  - Latitude/Longitude (from mobile sensor verification)

- **TPM Attestation** (`grc.tpm-attestation`):
  - App Key certificate (signed by TPM AK)
  - App Key public key
  - Challenge nonce
  - TPM quote data

- **Workload** (`grc.workload`):
  - Workload ID (SPIFFE ID)
  - Key source: `tpm-app-key`

These claims are embedded in the agent SVID and inherited by workload SVIDs through the certificate chain.

## Integration with Main Test

This demo is integrated into the main integration test (`../test_complete.sh`):

- **Step 8**: Creates registration entry for the workload
- **Step 10**: Fetches workload SVID with AttestedClaims
- **Step 12**: Verifies integration and checks logs

The test validates:
- Agent SVID contains TPM attestation claims
- Workload SVID inherits claims from agent SVID
- Complete end-to-end flow (TPM → Keylime → SPIRE → Workload)

## Troubleshooting

- **Socket not found**: Make sure SPIRE Agent is running (check `/tmp/spire-agent/public/api.sock`)
- **Permission denied**: Check socket permissions (`ls -la /tmp/spire-agent/public/api.sock`)
- **No AttestedClaims**: 
  - Ensure `Unified-Identity` feature flag is enabled
  - Verify agent SVID was issued with AttestedClaims (check agent logs)
  - Ensure Keylime Verifier is running and agent attestation succeeded
- **Registration entry not found**: Run `./create-registration-entry.sh` to create the entry
- **Protobuf import errors**: Run `./generate-proto-stubs.sh` to generate Python protobuf stubs

## Quick Reference: Mixed Mode Setup

**Complete Command Sequence for Mixed Mode (SPIRE Client + Standard Cert Server):**

**Step 0: Extract SPIRE CA Bundle (Optional - for strict server verification of SPIRE clients)**
```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo
python3 fetch-spire-bundle.py
# Creates /tmp/spire-bundle.pem by default
```

**Terminal 1 - Server:**
```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo
export SERVER_USE_SPIRE="false"
export SERVER_PORT="9443"
export SERVER_LOG="/tmp/mtls-server-app.log"

# Optional: For strict SPIRE client verification, provide SPIRE CA bundle:
export CA_CERT_PATH="/tmp/spire-bundle.pem"

python3 mtls-server-app.py
```

**Terminal 2 - Client:**
```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo
export CLIENT_USE_SPIRE="true"
export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
export SERVER_HOST="localhost"  # Use "10.1.0.10" if server is on different machine
export SERVER_PORT="9443"
export CLIENT_LOG="/tmp/mtls-client-app.log"
export CA_CERT_PATH="~/.mtls-demo/server-cert.pem"  # Required for server verification
python3 mtls-client-app.py
```

**For Client and Server on Different Machines:**

**Server Machine (IP: 10.1.0.10):**
```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo
# First copy spire bundle cert: scp mw@10.1.0.11:~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo/tmp/spire-bundle.pem ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo/tmp/spire-bundle.pem
export SERVER_USE_SPIRE="false"
export SERVER_PORT="9443"
export SERVER_LOG="/tmp/mtls-server-app.log"
export CA_CERT_PATH="/tmp/spire-bundle.pem"  # Copy from client machine
python3 mtls-server-app.py
```

**Client Machine (IP: 10.1.0.11):**
```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo
# First copy server cert: scp mw@10.1.0.10:~/.mtls-demo/server-cert.pem ~/.mtls-demo/server-cert.pem
export CLIENT_USE_SPIRE="true"
export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
export SERVER_HOST="10.1.0.10"  # Server machine IP
export SERVER_PORT="9443"
export CLIENT_LOG="/tmp/mtls-client-app.log"
export CA_CERT_PATH="~/.mtls-demo/server-cert.pem"  # Required for server verification
python3 mtls-client-app.py
```

**Key Points:**
- Server uses standard certificates (no SPIRE required)
- Client uses SPIRE SVIDs (requires SPIRE Agent running)
- **Client `CA_CERT_PATH`**: Points to server's certificate file (for client to verify server)
- **Server `CA_CERT_PATH`**: Points to SPIRE bundle file (for server to verify SPIRE clients)
- Extract SPIRE bundle with: `python3 fetch-spire-bundle.py`
- Server automatically accepts SPIRE-issued client certificates (permissive mode) unless `CA_CERT_PATH` is provided
- Both sides detect and log mixed mode automatically

## See Also

- **Main Integration Test**: `../test_complete.sh` - Complete end-to-end test including this demo
- **Architecture Documentation**: `../README-arch-sovereign-unified-identity.md` - Detailed architecture flow
- **Main README**: `../README.md` - Project overview and quick start
