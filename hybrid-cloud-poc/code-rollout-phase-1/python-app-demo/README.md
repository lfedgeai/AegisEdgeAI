# Unified-Identity - Phase 1: Python App Demo

This demo shows how to fetch and dump a Sovereign SVID with AttestedClaims using a simple Python application.

## Overview

This demo includes:
1. **SPIRE Server** - Issues SVIDs with AttestedClaims
2. **SPIRE Agent** - Provides Workload API to applications
3. **Keylime Stub** - Returns fixed AttestedClaims (geolocation, host integrity, GPU metrics)
4. **Python App** - Fetches SVID and displays AttestedClaims

## Prerequisites

- Go installed (for SPIRE and Keylime stub)
- Python 3 installed
- SPIRE binaries built (in `../spire/bin/`)

### Install Python Dependencies

```bash
pip install -r requirements.txt
```

This installs:
- `spiffe` - SPIRE Workload API client library

## Quick Start

### Step 1: Setup SPIRE and Keylime

```bash
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/python-app-demo
./setup-spire.sh
```

This will:
- Start Keylime Stub (port 8888)
- Start SPIRE Server
- Start SPIRE Agent
- Create necessary directories and sockets

### Step 2: Create Registration Entry

```bash
./create-registration-entry.sh
```

This creates a registration entry for your Python app based on your Unix UID.

### Step 3: Fetch Sovereign SVID

**Recommended: Use the all-in-one demo script:**
```bash
./run-demo.sh
```

This script orchestrates all steps and uses the gRPC version (`fetch-sovereign-svid-grpc.py`) to get real AttestedClaims.

**Or manually:**
```bash
python3 fetch-sovereign-svid-grpc.py
```

This will:
- Connect to SPIRE Agent Workload API via gRPC (direct access to AttestedClaims)
- Agent automatically attests the process and matches to registration entry
- Agent sends `SovereignAttestation` to server when fetching SVID
- Server processes via Keylime stub and policy engine
- Server returns `AttestedClaims` in response
- Agent passes `AttestedClaims` to the Python app
- Save the certificate to `/tmp/svid-dump/svid.pem`
- Save AttestedClaims to `/tmp/svid-dump/attested_claims.json` (real data from Keylime stub)

### Step 4: Dump SVID with AttestedClaims

```bash
../scripts/dump-svid -cert /tmp/svid-dump/svid.pem -attested /tmp/svid-dump/attested_claims.json
```

## Files

- `run-demo.sh` - **All-in-one demo script** (recommended - orchestrates all steps)
- `setup-spire.sh` - Sets up SPIRE Server, Agent, and Keylime Stub
- `create-registration-entry.sh` - Creates registration entry for the Python app
- `fetch-sovereign-svid-grpc.py` - **Fetches sovereign SVID with AttestedClaims via gRPC** (recommended)
- `fetch-sovereign-svid.py` - Alternative using `spiffe` library (fallback)
- `cleanup.sh` - Cleans up all components
- `spire-server.conf` - SPIRE Server configuration
- `spire-agent.conf` - SPIRE Agent configuration

## Cleanup

To stop all components and clean up:

```bash
./cleanup.sh
```

Or manually:

```bash
kill $(cat /tmp/spire-server.pid) $(cat /tmp/spire-agent.pid) $(cat /tmp/keylime-stub.pid)
rm -rf /tmp/spire-server /tmp/spire-agent
sudo rm -rf /opt/spire/data
```

## How It Works

1. **SPIRE Server** runs with the `Unified-Identity` feature flag enabled
2. **SPIRE Agent** connects to the server and provides the Workload API
3. **Keylime Stub** provides fixed AttestedClaims when SPIRE Server calls it
4. **Python App** communicates **only with SPIRE Agent** via Workload API (gRPC):
   - Connects to Agent's Workload API socket (`/tmp/spire-agent/public/api.sock`)
   - Agent automatically attests the Python process (extracts UID, etc.)
   - Agent matches selectors to registration entry
   - Agent sends `SovereignAttestation` to server when fetching SVID
   - Server processes via Keylime stub and policy engine
   - Server returns `AttestedClaims` in response
   - Agent passes `AttestedClaims` to the Python app via Workload API
5. **dump-svid** script displays the SVID and highlights AttestedClaims

**Important**: The Python app does NOT communicate directly with SPIRE Server. All communication goes through the SPIRE Agent Workload API, which is the standard and secure way for workloads to get their SVIDs.

**✅ Verified**: The complete flow is working end-to-end. AttestedClaims are successfully passed from Keylime stub → Server → Agent → Workload.

## AttestedClaims

The AttestedClaims returned from Keylime stub include:
- **Geolocation**: `Spain: N40.4168, W3.7038` (from Keylime stub)
- **Host Integrity Status**: `PASSED_ALL_CHECKS`
- **GPU Metrics Health**:
  - Status: `healthy`
  - Utilization: `15.0%`
  - Memory: `10240 MB`

These are successfully passed through the complete flow: Keylime Stub → SPIRE Server → SPIRE Agent → Python App.

## Troubleshooting

- **Socket not found**: Make sure SPIRE Agent is running (`./setup-spire.sh`)
- **Permission denied**: Check socket permissions (`ls -la /tmp/spire-agent/public/api.sock`)
- **No AttestedClaims**: Ensure feature flag is enabled and Keylime stub is running

