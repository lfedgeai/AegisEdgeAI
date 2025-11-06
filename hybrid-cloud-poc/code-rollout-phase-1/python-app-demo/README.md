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

```bash
python3 fetch-sovereign-svid.py
```

This will:
- Call SPIRE Server API to generate a sovereign SVID with AttestedClaims
- Save the certificate to `/tmp/svid-dump/svid.pem`
- Save AttestedClaims to `/tmp/svid-dump/attested_claims.json`

### Step 4: Dump SVID with AttestedClaims

```bash
../scripts/dump-svid -cert /tmp/svid-dump/svid.pem -attested /tmp/svid-dump/attested_claims.json
```

## Files

- `setup-spire.sh` - Sets up SPIRE Server, Agent, and Keylime Stub
- `create-registration-entry.sh` - Creates registration entry for the Python app
- `fetch-sovereign-svid.py` - Fetches sovereign SVID with AttestedClaims
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
4. **Python App** calls `generate-sovereign-svid.go` which:
   - Creates a CSR
   - Builds a `SovereignAttestation` request
   - Calls `BatchNewX509SVID` API on SPIRE Server
   - SPIRE Server calls Keylime Stub to get AttestedClaims
   - Returns SVID with AttestedClaims in the response
5. **dump-svid** script displays the SVID and highlights AttestedClaims

## AttestedClaims

The AttestedClaims include:
- **Geolocation**: `US-CA-SanFrancisco` (from Keylime stub)
- **Host Integrity Status**: `HOST_INTEGRITY_VERIFIED`
- **GPU Metrics Health**:
  - Status: `healthy`
  - Utilization: `45.5%`
  - Memory: `8192 MB`

## Troubleshooting

- **Socket not found**: Make sure SPIRE Agent is running (`./setup-spire.sh`)
- **Permission denied**: Check socket permissions (`ls -la /tmp/spire-agent/public/api.sock`)
- **No AttestedClaims**: Ensure feature flag is enabled and Keylime stub is running

