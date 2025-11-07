# Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)

## Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)

**✅ STATUS: COMPLETE AND TESTED**

This directory contains the implementation of **Phase 1** of the Unified Identity for Sovereign AI architecture. This phase implements all necessary SPIRE API changes and policy logic without relying on a functional Keylime or TPM plugin.

**Phase 1 has been successfully implemented and tested end-to-end.** The complete flow from workload → agent → server → Keylime stub → policy engine → AttestedClaims is working and verified.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Feature Flag](#feature-flag)
  - [Enabling the Feature Flag](#enabling-the-feature-flag)
  - [Disabling the Feature Flag](#disabling-the-feature-flag)
- [Sovereign SVID Format](#sovereign-svid-format)
- [API Changes](#api-changes)
  - [Protobuf Definitions](#protobuf-definitions)
  - [Keylime Verifier API](#keylime-verifier-api)
- [Code Changes Summary](#code-changes-summary)
- [Components](#components)
  - [Keylime Verifier Stub](#keylime-verifier-stub)
  - [SPIRE Server Integration](#spire-server-integration)
  - [Policy Engine](#policy-engine)
- [Regenerating Protobuf Files](#regenerating-protobuf-files)
- [Logging](#logging)
- [Limitations (Phase 1)](#limitations-phase-1)
- [Generating an SVID with SovereignAttestation](#generating-an-svid-with-sovereignattestation)
  - [Prerequisites](#prerequisites)
  - [Step 1: Create Registration Entry](#step-1-create-registration-entry)
  - [Step 2: Generate Certificate Signing Request (CSR)](#step-2-generate-certificate-signing-request-csr)
  - [Step 3: Prepare SovereignAttestation](#step-3-prepare-sovereignattestation)
  - [Step 4: Call BatchNewX509SVID API](#step-4-call-batchnewx509svid-api)
  - [Step 5: Verify Response](#step-5-verify-response)
  - [Step 6: Verify Logs](#step-6-verify-logs)
  - [Complete Working Script](#complete-working-script)
  - [Dumping and Highlighting SVID with Phase 1 Additions](#dumping-and-highlighting-svid-with-phase-1-additions)
  - [Notes](#notes)
- [Kubernetes Integration](#kubernetes-integration)
  - [Quick Start](#quick-start)
  - [Dumping SVID from Kubernetes Workloads](#dumping-svid-from-kubernetes-workloads)
  - [Cleanup and Teardown](#cleanup-and-teardown)
- [Next Steps](#next-steps)
- [References](#references)

## Overview

Phase 1 focuses on:
- **SPIRE Server**: Implementation of new `X509SVIDRequest` logic with `SovereignAttestation` support
- **SPIRE Agent**: Support for stubbed `SovereignAttestation` in `X509SVIDRequest` flow
- **Keylime Verifier Stub**: Mock Keylime Verifier API that validates mTLS and returns fixed `AttestedClaims`
- **Policy Engine**: Evaluation logic for `AttestedClaims` with geolocation, integrity, and GPU metrics checks

## Architecture

```
┌─────────────────┐
│  SPIRE Agent    │
│  (with stubbed  │
│  Sovereign      │
│  Attestation)   │
└────────┬────────┘
         │
         │ BatchNewX509SVID
         │ (with SovereignAttestation)
         ▼
┌─────────────────┐
│  SPIRE Server   │
│  - Validates     │
│  - Calls Keylime │
│  - Evaluates     │
│    Policy        │
└────────┬────────┘
         │
         │ POST /v2.4/verify/evidence
         ▼
┌─────────────────┐
│  Keylime Stub   │
│  (returns fixed  │
│  AttestedClaims) │
└─────────────────┘
```

## ✅ Implementation Status

**Phase 1 is complete and fully functional.** All components have been implemented, tested, and verified:

- ✅ **SPIRE Server**: Processes `SovereignAttestation`, calls Keylime stub, evaluates policy, returns `AttestedClaims`
- ✅ **SPIRE Agent**: Sends `SovereignAttestation` to server, receives and passes `AttestedClaims` to workloads
- ✅ **Keylime Stub**: Returns fixed `AttestedClaims` (geolocation, host integrity, GPU metrics)
- ✅ **Policy Engine**: Evaluates `AttestedClaims` with configurable rules (geolocation, integrity, GPU)
- ✅ **End-to-End Flow**: Complete path from Python app → Agent → Server → Keylime → Policy → AttestedClaims

### Verified Working Demo

The Python app demo (`python-app-demo/`) successfully demonstrates the complete flow:
- Python app fetches SVID via SPIRE Agent Workload API (gRPC)
- Agent sends `SovereignAttestation` to server
- Server processes via Keylime stub and policy engine
- `AttestedClaims` are returned and displayed:
  ```json
  {
    "geolocation": "Spain: N40.4168, W3.7038",
    "host_integrity_status": "PASSED_ALL_CHECKS",
    "gpu_metrics_health": {
      "status": "healthy",
      "utilization_pct": 15.0,
      "memory_mb": 10240
    }
  }
  ```

### Automated Test

An automated regression test is available to verify the entire flow (including agent bootstrap SVID, Python workload SVID, and Unified-Identity logs):

```bash
cd scripts
./test-python-demo.sh
```

The test starts the SPIRE stack, verifies agent bootstrap AttestedClaims, fetches the Python app SVID via gRPC, validates the generated SVID/AttestedClaims files, checks Keylime/SPIRE logs, and then tears everything down.

See `python-app-demo/README.md` for details.

## Feature Flag

All Phase 1 code changes are wrapped under the **`Unified-Identity`** feature flag, which is **disabled by default**.

### Enabling the Feature Flag

To enable the Unified-Identity feature, configure SPIRE with the feature flag enabled:

1. **SPIRE Server Configuration** (`spire-server.conf`):
```hcl
server {
    experimental {
        feature_flags = ["Unified-Identity"]
    }
    # ... other config ...
}
```

2. **SPIRE Agent Configuration** (`spire-agent.conf`):
```hcl
agent {
    experimental {
        feature_flags = ["Unified-Identity"]
    }
    # ... other config ...
}
```

3. **Optional: Rebuild SPIRE** (only if using modified SPIRE binaries with Phase 1 changes):
```bash
cd spire
make build
```

**Note**: If using existing SPIRE binaries without Phase 1 changes, the feature flag will be ignored and SovereignAttestation will not be processed (backward compatible behavior).

### Disabling the Feature Flag

Remove `"Unified-Identity"` from the `feature_flags` array in configuration files. If using rebuilt SPIRE binaries, restart the services.

## Sovereign SVID Format

**Important:** The X.509 certificate itself is **unchanged** - it remains a standard SPIFFE SVID. The new Phase 1 fields are in the API request/response, not in the certificate.

### New Fields

**Request Field:** `SovereignAttestation` (input)
- Sent when requesting an SVID with sovereign attestation
- Contains TPM quote, app key, challenge nonce, etc.

**Response Field:** `AttestedClaims` (output)
- Returned after Keylime verification and policy evaluation
- Contains geolocation, host integrity status, GPU metrics

For complete details, see **[SOVEREIGN_SVID_FORMAT.md](SOVEREIGN_SVID_FORMAT.md)**.

## API Changes

### Protobuf Definitions

#### New Messages

**`SovereignAttestation`** (in `sovereignattestation.proto` and `workload.proto`):
```protobuf
message SovereignAttestation {
    string tpm_signed_attestation = 1;  // Base64-encoded TPM Quote
    string app_key_public = 2;          // App Key public key (PEM/base64)
    bytes app_key_certificate = 3;      // Base64-encoded X.509 cert
    string challenge_nonce = 4;        // SPIRE Server nonce
    string workload_code_hash = 5;      // Optional workload code hash
}
```

**`AttestedClaims`** (in `sovereignattestation.proto`):
```protobuf
message AttestedClaims {
    string geolocation = 1;
    enum HostIntegrity {
        HOST_INTEGRITY_UNSPECIFIED = 0;
        PASSED_ALL_CHECKS = 1;
        FAILED = 2;
        PARTIAL = 3;
    }
    HostIntegrity host_integrity_status = 2;
    message GpuMetrics {
        string status = 1;
        double utilization_pct = 2;
        int64 memory_mb = 3;
    }
    GpuMetrics gpu_metrics_health = 3;
}
```

#### Modified Messages

**`X509SVIDRequest`** (in `workload.proto`):
- Added optional `sovereign_attestation` field (tag 20)

**`X509SVIDResponse`** (in `workload.proto`):
- Added optional `attested_claims` field (tag 30)

**`NewX509SVIDParams`** (in `svid.proto`):
- Added optional `sovereign_attestation` field (tag 20)

**`BatchNewX509SVIDResponse.Result`** (in `svid.proto`):
- Added optional `attested_claims` field (tag 30)

### Keylime Verifier API

**Endpoint**: `POST /v2.4/verify/evidence`

**Request**:
```json
{
  "data": {
    "nonce": "string",
    "quote": "string (Base64-encoded TPM Quote)",
    "hash_alg": "sha256",
    "app_key_public": "string",
    "app_key_certificate": "string (Base64-encoded X.509 DER/PEM)",
    "tpm_ak": "string (optional)",
    "tpm_ek": "string (optional)"
  },
  "metadata": {
    "source": "SPIRE Server",
    "submission_type": "PoR/tpm-app-key",
    "audit_id": "optional"
  }
}
```

**Response**:
```json
{
  "results": {
    "verified": true,
    "verification_details": {
      "app_key_certificate_valid": true,
      "app_key_public_matches_cert": true,
      "quote_signature_valid": true,
      "nonce_valid": true,
      "timestamp": 1690000000
    },
    "attested_claims": {
      "geolocation": "Spain: N40.4168, W3.7038",
      "host_integrity_status": "passed_all_checks",
      "gpu_metrics_health": {
        "status": "healthy",
        "utilization_pct": 15.0,
        "memory_mb": 10240
      }
    },
    "audit_id": "uuid-..."
  }
}
```

## Code Changes Summary

### Files Created

1. **`spire/pkg/server/keylime/client.go`** - HTTP client for Keylime Verifier API
2. **`spire/pkg/server/keylime/client_test.go`** - Unit tests for Keylime client
3. **`spire/pkg/server/policy/engine.go`** - Policy evaluation engine
4. **`spire/pkg/server/policy/engine_test.go`** - Unit tests for policy engine
5. **`spire-api-sdk/proto/spire/api/types/sovereignattestation.proto`** - Protobuf definitions
6. **`keylime-stub/main.go`** - Mock Keylime Verifier API server
7. **`keylime-stub/go.mod`** - Go module for Keylime stub

### Files Modified

1. **`spire/pkg/common/fflag/fflag.go`**
   - Added `FlagUnifiedIdentity` constant
   - Added to flags map (default: false)

2. **`go-spiffe/proto/spiffe/workload/workload.proto`**
   - Added `SovereignAttestation` and `AttestedClaims` messages
   - Extended `X509SVIDRequest` with `sovereign_attestation` field
   - Extended `X509SVIDResponse` with `attested_claims` field

3. **`spire-api-sdk/proto/spire/api/server/svid/v1/svid.proto`**
   - Imported `sovereignattestation.proto`
   - Extended `NewX509SVIDParams` with `sovereign_attestation` field
   - Extended `BatchNewX509SVIDResponse.Result` with `attested_claims` field

4. **`spire/pkg/server/api/svid/v1/service.go`**
   - Added Keylime client and policy engine to `Config`
   - Added `processSovereignAttestation()` method
   - Modified `newX509SVID()` to handle `SovereignAttestation` when feature flag enabled
   - Added feature flag check: `if fflag.IsSet(fflag.FlagUnifiedIdentity) && param.SovereignAttestation != nil`

5. **`spire/pkg/server/api/svid/v1/service_test.go`**
   - Added integration tests for SovereignAttestation processing
   - Added feature flag disabled/enabled tests
   - Added policy failure tests

6. **`spire-api-sdk/Makefile`**
   - Added `sovereignattestation.proto` to protos list

### Key Implementation Details

**Feature Flag Wrapping**:
```go
if fflag.IsSet(fflag.FlagUnifiedIdentity) && param.SovereignAttestation != nil {
    log.Info("Unified-Identity - Phase 1: Processing SovereignAttestation")
    claims, err := s.processSovereignAttestation(ctx, log, param.SovereignAttestation, spiffeID.String())
    // ... handle claims ...
}
```

**Code Comments**: All changes tagged with:
```go
// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
```

**Logging**: All logging includes the tag and appropriate levels (INFO, DEBUG, WARN, ERROR)

## Components

### Keylime Verifier Stub

**Location**: `keylime-stub/`

**Purpose**: Mock Keylime Verifier API that validates mTLS and returns fixed `AttestedClaims`

**Configuration** (Environment Variables):
- `KEYLIME_STUB_PORT`: Port (default: 8888)
- `KEYLIME_STUB_TLS_CERT`: TLS certificate path (optional)
- `KEYLIME_STUB_TLS_KEY`: TLS key path (optional)
- `KEYLIME_STUB_GEOLOCATION`: Stubbed geolocation (default: "Spain: N40.4168, W3.7038")
- `KEYLIME_STUB_INTEGRITY`: Stubbed integrity (default: "passed_all_checks")
- `KEYLIME_STUB_GPU_STATUS`: Stubbed GPU status (default: "healthy")

### SPIRE Server Integration

**Keylime Client** (`spire/pkg/server/keylime/client.go`):
- Builds requests from `SovereignAttestation`
- Handles mTLS authentication
- Calls Keylime Verifier API
- Returns `AttestedClaims`

**Policy Engine** (`spire/pkg/server/policy/engine.go`):
- Evaluates geolocation against allowed patterns (supports wildcards like `Spain:*`)
- Validates host integrity status
- Checks GPU utilization and memory thresholds
- Returns policy evaluation results

**SVID Service** (`spire/pkg/server/api/svid/v1/service.go`):
- Processes `SovereignAttestation` when feature flag enabled
- Calls Keylime client to verify evidence
- Evaluates `AttestedClaims` against policy
- Returns `AttestedClaims` in response or error on policy failure

### Policy Engine

**Policy Checks**:
1. **Geolocation**: Validates against allowed patterns
2. **Host Integrity**: Optionally requires `passed_all_checks`
3. **GPU Utilization**: Validates against maximum threshold
4. **GPU Memory**: Validates against minimum threshold

**Policy Evaluation Flow**:
1. SPIRE Server receives `SovereignAttestation` in `BatchNewX509SVID` request
2. Server calls Keylime Verifier to verify evidence and get `AttestedClaims`
3. Server evaluates `AttestedClaims` against configured policy
4. If policy passes, SVID is issued with `AttestedClaims` in response
5. If policy fails, error is returned (remediation stubbed in Phase 1)

## Regenerating Protobuf Files

After modifying `.proto` files, regenerate Go code:

**Option 1: Use the provided script** (recommended):
```bash
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1
./regenerate-protos.sh
```

**Option 2: Manual regeneration**:
```bash
cd go-spiffe && make generate
cd ../spire-api-sdk && make generate
cd ../spire && make generate
```

## Logging

All Phase 1 code includes logging with tag: **"Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)"**

**Log Levels**:
- **INFO**: Feature status, Keylime calls, policy evaluation results
- **DEBUG**: Detailed request/response data
- **WARN**: Policy violations, missing configuration
- **ERROR**: Failures in Keylime communication, policy errors

## Limitations (Phase 1)

This is a **stubbed implementation**:
1. **Keylime Verifier**: Returns fixed, hardcoded `AttestedClaims` - no actual TPM verification
2. **TPM Plugin**: No actual TPM interaction - uses stubbed data
3. **Remediation**: Policy failures return errors - no actual remediation actions
4. **Cryptographic Verification**: Certificate chain validation is stubbed

## Generating an SVID with SovereignAttestation

This section provides verified steps to generate an X509-SVID with the new `SovereignAttestation` format.

### Prerequisites

1. **SPIRE Server** running with feature flag enabled
2. **SPIRE Agent** running with feature flag enabled (if using agent-based flow)
3. **Keylime Stub** running (see [Components](#components) section)
4. **Registration Entry** created in SPIRE Server

### Step 1: Create Registration Entry

```bash
# Create a registration entry for the workload
spire-server entry create \
    -spiffeID spiffe://example.org/workload/test \
    -parentID spiffe://example.org/agent \
    -selector unix:uid:1000
```

Note the `entry_id` from the output (e.g., `entry-id-123`).

### Step 2: Generate Certificate Signing Request (CSR)

Create a CSR with the SPIFFE ID in the URI SAN:

```bash
# Generate a private key
openssl genrsa -out key.pem 2048

# Create CSR with SPIFFE ID
openssl req -new -key key.pem -out csr.pem \
    -subj "/CN=test-workload" \
    -addext "subjectAltName=URI:spiffe://example.org/workload/test"
```

Convert CSR to DER format:
```bash
openssl req -in csr.pem -out csr.der -outform DER
```

### Step 3: Prepare SovereignAttestation

For Phase 1 (stubbed), create a stubbed `SovereignAttestation`:

**Go Example**:
```go
import (
    "encoding/base64"
    "github.com/spiffe/spire-api-sdk/proto/spire/api/types"
)

// Create stubbed SovereignAttestation
sovereignAttestation := &types.SovereignAttestation{
    TpmSignedAttestation: base64.StdEncoding.EncodeToString([]byte("stubbed-tpm-quote")),
    AppKeyPublic:         "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----",
    AppKeyCertificate:    []byte("stubbed-certificate"),
    ChallengeNonce:       "nonce-123456789",
    WorkloadCodeHash:     "hash-abc123",
}
```

**JSON Example** (for REST API or testing):
```json
{
  "tpm_signed_attestation": "c3R1YmJlZC10cG0tcXVvdGU=",
  "app_key_public": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----",
  "app_key_certificate": "c3R1YmJlZC1jZXJ0aWZpY2F0ZQ==",
  "challenge_nonce": "nonce-123456789",
  "workload_code_hash": "hash-abc123"
}
```

### Step 4: Call BatchNewX509SVID API

**Using SPIRE API Client** (Go):

```go
import (
    "context"
    "io/ioutil"
    "github.com/spiffe/spire-api-sdk/proto/spire/api/server/svid/v1"
    "github.com/spiffe/spire-api-sdk/proto/spire/api/types"
    "google.golang.org/grpc"
)

// Read CSR
csrBytes, _ := ioutil.ReadFile("csr.der")

// Create request
req := &svidv1.BatchNewX509SVIDRequest{
    Params: []*svidv1.NewX509SVIDParams{
        {
            EntryId: "entry-id-123", // From Step 1
            Csr:     csrBytes,
            SovereignAttestation: sovereignAttestation, // From Step 3
        },
    },
}

// Call API (assuming you have a gRPC client)
conn, _ := grpc.Dial("unix:///tmp/spire-server/private/api.sock")
client := svidv1.NewSVIDClient(conn)

resp, err := client.BatchNewX509SVID(context.Background(), req)
if err != nil {
    // Handle error
}

// Check response
for _, result := range resp.Results {
    if result.Status.Code == 0 { // OK
        // SVID available in result.Svid
        // AttestedClaims available in result.AttestedClaims (if feature flag enabled)
        fmt.Printf("SVID ID: %s\n", result.Svid.Id)
        fmt.Printf("AttestedClaims: %v\n", result.AttestedClaims)
    } else {
        fmt.Printf("Error: %s\n", result.Status.Message)
    }
}
```

### Step 5: Verify Response

The response should include:

1. **X509-SVID**: Certificate chain in `result.Svid.CertChain`
2. **AttestedClaims** (if feature flag enabled): Verified claims from Keylime
   ```go
   if len(result.AttestedClaims) > 0 {
       claims := result.AttestedClaims[0]
       fmt.Printf("Geolocation: %s\n", claims.Geolocation)
       fmt.Printf("Host Integrity: %s\n", claims.HostIntegrityStatus)
       fmt.Printf("GPU Status: %s\n", claims.GpuMetricsHealth.Status)
   }
   ```

### Step 6: Verify Logs

Check SPIRE Server logs for:
```
INFO Unified-Identity - Phase 1: Processing SovereignAttestation
INFO Unified-Identity - Phase 1: Calling Keylime Verifier to verify evidence
INFO Unified-Identity - Phase 1: Received AttestedClaims from Keylime
INFO Unified-Identity - Phase 1: Policy evaluation passed
```

### Complete Working Script

A complete working Go script is provided in `scripts/generate-sovereign-svid.go` that demonstrates the full flow.

**Location**: `scripts/generate-sovereign-svid.go`

**Build the script:**
```bash
cd scripts
go mod tidy
go build -o generate-sovereign-svid generate-sovereign-svid.go
```

**Test the script:**
```bash
cd scripts
./test-sovereign-svid.sh
```

**Usage:**
```bash
# 1. First, create a registration entry and note the entry ID
spire-server entry create \
    -spiffeID spiffe://example.org/workload/test \
    -parentID spiffe://example.org/agent \
    -selector unix:uid:1000

# 2. Run the script with the entry ID
./generate-sovereign-svid \
    -entryID "entry-id-from-step-1" \
    -spiffeID "spiffe://example.org/workload/test" \
    -serverSocketPath "unix:///tmp/spire-server/private/api.sock" \
    -verbose

# 3. The script will:
#    - Generate a CSR automatically
#    - Create stubbed SovereignAttestation
#    - Call BatchNewX509SVID API
#    - Save the SVID certificate and private key
#    - Display AttestedClaims if feature flag is enabled
```

**Script Output Example:**
```
Unified-Identity - Phase 1: Generating SVID with SovereignAttestation
Step 1: Generating CSR...
✓ CSR generated for SPIFFE ID: spiffe://example.org/workload/test
Step 2: Preparing SovereignAttestation (stubbed)...
✓ SovereignAttestation prepared
Step 3: Connecting to SPIRE Server at unix:///tmp/spire-server/private/api.sock...
✓ Connected to SPIRE Server
Step 4: Calling BatchNewX509SVID API...
✓ SVID generated successfully
Step 5: Verifying and saving SVID...
✓ SVID Details:
  - SPIFFE ID: spiffe://example.org/workload/test
  - Expires At: 2024-11-07T10:30:00Z
  - Subject: CN=sovereign-workload
  - Serial Number: 1234567890
✓ AttestedClaims received:
  - Geolocation: Spain: N40.4168, W3.7038
  - Host Integrity: PASSED_ALL_CHECKS
  - GPU Status: healthy
  - GPU Utilization: 15.00%
  - GPU Memory: 10240 MB
✓ Certificate saved to: svid.crt
✓ Private key saved to: svid.key

✅ Successfully generated SVID with SovereignAttestation!
   Certificate: svid.crt
   Private Key: svid.key
```

**Script Features:**
- Automatically generates CSR with proper SPIFFE ID
- Creates stubbed SovereignAttestation for Phase 1 testing
- Connects to SPIRE Server via gRPC
- Calls BatchNewX509SVID with SovereignAttestation
- Verifies and displays SVID details
- Displays AttestedClaims if feature flag is enabled
- Saves certificate, private key, and AttestedClaims JSON to files

### Dumping and Highlighting SVID with Phase 1 Additions

After generating an SVID, use the `dump-svid` script to view the SVID and highlight Phase 1 additions:

**Build the script:**
```bash
cd scripts
go build -o dump-svid dump-svid.go
```

**Usage:**
```bash
# Pretty format (default, with color highlighting)
./dump-svid -cert svid.crt -attested svid_attested_claims.json

# JSON format
./dump-svid -cert svid.crt -attested svid_attested_claims.json -format json

# Detailed format (includes certificate extensions)
./dump-svid -cert svid.crt -attested svid_attested_claims.json -format detailed

# Without color (for terminals that don't support it)
./dump-svid -cert svid.crt -color false
```

**Output Example:**
```
╔════════════════════════════════════════════════════════════════╗
║              SPIFFE Verifiable Identity Document (SVID)        ║
╚════════════════════════════════════════════════════════════════╝

📋 Standard SVID Information:
──────────────────────────────────────────────────────────────────────
  Subject: CN=sovereign-workload
  Issuer: CN=SPIRE
  Serial Number: 1234567890
  Valid From: 2024-11-06T10:00:00Z
  Valid Until: 2024-11-06T11:00:00Z
  SPIFFE ID: spiffe://example.org/workload/test

🆕 Phase 1 Additions (Unified-Identity):
═══════════════════════════════════════════════════════════════════════

  ➕ 📍 Geolocation: Spain: N40.4168, W3.7038
  ➕ 🔒 Host Integrity Status: PASSED_ALL_CHECKS
  ➕ 🎮 GPU Metrics Health:
    ➕ Status: healthy
    ➕ Utilization: 15.00%
    ➕ Memory: 10240 MB

──────────────────────────────────────────────────────────────────────
✓ This SVID includes Phase 1 AttestedClaims (Unified-Identity)
```

The script highlights:
- **Standard SVID fields**: Normal formatting
- **Phase 1 additions**: Highlighted with ➕ symbol and green color
  - Geolocation
  - Host Integrity Status
  - GPU Metrics Health

**Run example script:**
```bash
./dump-svid-example.sh
```

### Notes

- **Feature Flag Required**: `SovereignAttestation` is only processed when `feature_flags = ["Unified-Identity"]` is set
- **Keylime Stub**: Must be running and accessible from SPIRE Server
- **Backward Compatibility**: If feature flag is disabled, `SovereignAttestation` field is ignored and normal SVID flow continues
- **Stubbed Data**: In Phase 1, all TPM data is stubbed - use base64-encoded test strings

## Kubernetes Integration

**⚠️ STATUS: PENDING**

Kubernetes integration with SPIRE CSI driver is documented in `k8s-integration/README.md` but is currently pending resolution of CSI driver image pull issues. The Python app demo (`python-app-demo/`) provides a working alternative for testing Phase 1 functionality.

Phase 1 is designed to support Kubernetes workloads using the SPIRE CSI driver, with SPIRE Server and Agent running **outside** the Kubernetes cluster for security.

### Quick Start

**Note:** If you have a previous setup, run `k8s-integration/teardown.sh` first.

1. **Set up Kubernetes cluster** (using kind):
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

2. **Start SPIRE outside Kubernetes**:
   ```bash
   cd k8s-integration
   ./setup-spire.sh
   ```

3. **Run end-to-end test**:
   ```bash
   cd k8s-integration
   ./test-sovereign-svid.sh
   ```

See [k8s-integration/README.md](k8s-integration/README.md) for detailed Kubernetes integration documentation.

### Dumping SVID from Kubernetes Workloads

For Kubernetes workloads, you can dump the SVID using several methods:

**Method 1: Automated Script (Recommended)**
```bash
cd k8s-integration
./dump-svid-from-k8s.sh <pod-name> <namespace> <output-dir>

# Then view with Phase 1 highlights
cd ../scripts
./dump-svid -cert <output-dir>/svid.crt
```

**Method 2: Generate from Host (Best for Phase 1 Testing)**
Since Phase 1 requires `SovereignAttestation` at generation time, generate the SVID from the host:
```bash
cd scripts
./generate-sovereign-svid \
    -entryID <ENTRY_ID> \
    -spiffeID spiffe://example.org/workload/test-k8s

# Dump with Phase 1 highlights
./dump-svid -cert svid.crt -attested svid_attested_claims.json
```

**Method 3: Manual Extraction from Pod**
```bash
# Exec into pod and extract SVID
kubectl exec -it <pod-name> -- spire-agent api fetch \
    -socketPath /run/spire/sockets/api.sock > /tmp/svid.pem

# Copy to host and extract certificate
kubectl cp <namespace>/<pod-name>:/tmp/svid.pem /tmp/svid.pem
```

See [k8s-integration/README.md](k8s-integration/README.md) for detailed instructions.

### Cleanup and Teardown

To clean up Kubernetes resources and SPIRE components:

**Full Teardown (Interactive):**
```bash
cd k8s-integration
./teardown.sh
```

This will:
- Delete Kubernetes workloads and cluster
- Stop SPIRE Server, Agent, and Keylime Stub
- Clean up sockets
- Optionally remove logs and data directories

**Quick Teardown (Non-Interactive):**
```bash
cd k8s-integration
./teardown-quick.sh
```

**Manual Cleanup:**
```bash
# Stop SPIRE processes
kill $(cat /tmp/spire-server.pid) $(cat /tmp/spire-agent.pid) $(cat /tmp/keylime-stub.pid) 2>/dev/null || true

# Delete Kubernetes cluster
sudo kind delete cluster --name aegis-spire

# Remove kubeconfig files
rm -f /tmp/kubeconfig-kind.yaml

# Remove kind cluster context from ~/.kube/config
kubectl config delete-context kind-aegis-spire 2>/dev/null || true

# Remove admin.conf from ~/.kube/
rm -f ~/.kube/admin.conf

# Remove sockets
rm -f /tmp/spire-server/private/api.sock /tmp/spire-agent/public/api.sock
```

For detailed cleanup instructions, see [k8s-integration/README.md](k8s-integration/README.md#cleanup).

## Next Steps

1. **Regenerate Protobuf Files**: Run `./regenerate-protos.sh` (if modifying proto files)
2. **Run Tests**: See [TESTING.md](TESTING.md) for detailed testing instructions
3. **Python Demo Test**: `scripts/test-python-demo.sh`
4. **Integration Testing**: Test SVID generation with SovereignAttestation using the steps above
5. **Kubernetes Testing**: ⚠️ **PENDING** - Kubernetes integration is pending resolution of CSI driver image pull issues. See [k8s-integration/README.md](k8s-integration/README.md) for details. The Python app demo provides a working alternative.

## References

- [Architecture Document](../../README-arch.md)
- [SPIRE Documentation](https://spiffe.io/docs/latest/spire/)
- [Keylime Documentation](https://keylime.readthedocs.io/)
- [SPIRE CSI Driver](https://github.com/spiffe/spiffe-csi)
