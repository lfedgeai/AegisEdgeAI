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

## Files

- `run-demo.sh` - **All-in-one demo script** (recommended - orchestrates all steps)
- `create-registration-entry.sh` - Creates registration entry for the Python app
- `fetch-sovereign-svid-grpc.py` - **Fetches sovereign SVID with AttestedClaims via gRPC** (recommended)
- `fetch-sovereign-svid.py` - Alternative using `spiffe` library (fallback)
- `fetch-svid.py` - Basic SVID fetch without AttestedClaims
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

## See Also

- **Main Integration Test**: `../test_complete.sh` - Complete end-to-end test including this demo
- **Architecture Documentation**: `../README-arch-sovereign-unified-identity.md` - Detailed architecture flow
- **Main README**: `../README.md` - Project overview and quick start
