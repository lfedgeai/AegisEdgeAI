## Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)

**✅ STATUS: COMPLETE AND TESTED** (with **⚠️ Kubernetes Integration: INCOMPLETE**)

This directory contains the implementation of **Phase 1** of the Unified Identity for Sovereign AI architecture. This phase implements all necessary SPIRE API changes and policy logic without relying on a functional Keylime or TPM plugin.

**Phase 1 has been successfully implemented and tested end-to-end** for Linux workloads (Python app demo). The complete flow includes:
- ✅ **Agent Bootstrap**: Agent receives AttestedClaims during initial attestation (verified with enhanced diagnostic logging)
- ✅ **Agent SVID Renewal**: AttestedClaims attached to agent SVID renewals
- ✅ **Workload SVID**: Complete flow from workload → agent → server → Keylime stub → policy engine → AttestedClaims
- ✅ **Enhanced Diagnostic Logging**: Comprehensive logging with highlighted AttestedClaims in server and agent logs, including:
  - Server logs when `SovereignAttestation` is received during bootstrap
  - Server logs when `AttestedClaims` are attached to agent bootstrap SVID
  - Agent logs when `AttestedClaims` are received during bootstrap
  - Detailed diagnostic messages for troubleshooting
- ✅ **Interactive Demo**: Step-by-step demo with user prompts to review logs at each stage
- ✅ **Automated Tests**: Comprehensive end-to-end regression tests verifying all flows with log verification

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Implementation Status](#implementation-status)
- [Quick Start Demo](#quick-start-demo)
- [Feature Flag](#feature-flag)
- [Sovereign SVID Format](#sovereign-svid-format)
- [API Changes](#api-changes)
- [Code Changes Summary](#code-changes-summary)
- [Components](#components)
- [Regenerating Protobuf Files](#regenerating-protobuf-files)
- [Logging](#logging)
- [Limitations (Phase 1)](#limitations-phase-1)
- [Generating an SVID with SovereignAttestation](#generating-an-svid-with-sovereignattestation)
- [Kubernetes Integration](#kubernetes-integration)
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

- ✅ **SPIRE Server**: Processes `SovereignAttestation` during agent bootstrap and workload SVID requests, calls Keylime stub, evaluates policy, returns `AttestedClaims`
- ✅ **SPIRE Agent**: Sends `SovereignAttestation` to server during bootstrap and SVID renewals, receives and logs `AttestedClaims`, passes `AttestedClaims` to workloads via Workload API
- ✅ **Keylime Stub**: Returns fixed `AttestedClaims` (geolocation, host integrity, GPU metrics)
- ✅ **Policy Engine**: Evaluates `AttestedClaims` with configurable rules (geolocation, integrity, GPU)
- ✅ **Agent Bootstrap Flow**: Agent receives AttestedClaims during initial attestation (AttestAgent)
  - Server logs when `SovereignAttestation` is received (DEBUG level)
  - Server logs when `AttestedClaims` are attached (INFO level with full details)
  - Agent logs when `AttestedClaims` are received (INFO level with full details)
- ✅ **Agent SVID Renewal Flow**: AttestedClaims attached to agent SVID renewals (RenewAgent)
- ✅ **Workload SVID Flow**: Complete path from Python app → Agent → Server → Keylime → Policy → AttestedClaims
- ✅ **Enhanced Diagnostic Logging**: Comprehensive logging with highlighted AttestedClaims in server and agent logs:
  - Server diagnostic messages for troubleshooting (WARN level for missing/invalid data)
  - Agent bootstrap and renewal log messages (INFO level)
  - Workload SVID processing log messages (INFO/DEBUG level)
  - All logs highlighted in demo scripts and automated tests

### Quick Start Demo

**Interactive Demo** (recommended):
```bash
cd python-app-demo
./run-demo.sh
```
- Step-by-step execution with interactive prompts to review logs
- Shows agent bootstrap and workload SVID with AttestedClaims
- Highlights all relevant Unified-Identity logs

**Automated Test**:
```bash
cd scripts
./test-python-demo.sh
```
- Verifies agent bootstrap AttestedClaims and workload SVID
- Validates SVID certificate and AttestedClaims JSON structure
- Checks all Unified-Identity log messages

See `python-app-demo/README.md` for detailed documentation.

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

**`AgentX509SVIDParams`** (in `agent.proto`):
- Added optional `sovereign_attestation` field (tag 20)

**`AttestAgentResponse.Result`** (in `agent.proto`):
- Added optional `attested_claims` field (tag 30)

**`RenewAgentResponse`** (in `agent.proto`):
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

5. **`spire/pkg/server/api/agent/v1/service.go`**
   - Added `SovereignAttestation` processing during agent bootstrap (AttestAgent)
   - Added `SovereignAttestation` processing during agent SVID renewal (RenewAgent)
   - Added **enhanced diagnostic logging** for `SovereignAttestation` reception and processing:
     - `DEBUG`: Logs when `SovereignAttestation` is received during agent bootstrap
     - `INFO`: Logs when `AttestedClaims` are attached to agent bootstrap SVID (with full details)
     - `WARN`: Diagnostic messages if `SovereignAttestation` is missing, `params.Params` is nil, or processing returns nil claims
   - Attaches `AttestedClaims` to agent bootstrap and renewal responses

6. **`spire/pkg/agent/client/client.go`**
   - Added `SovereignAttestation` to agent SVID renewal requests when feature flag enabled
   - Extracts and stores `AttestedClaims` from server responses
   - Logs `AttestedClaims` when received during agent SVID renewal

7. **`spire/pkg/agent/attestor/node/node.go`**
   - Added `SovereignAttestation` to agent bootstrap requests (AttestAgent) when feature flag enabled
   - Extracts and logs `AttestedClaims` from agent bootstrap responses

8. **`spire/pkg/agent/manager/cache/workload.go`**
   - Added `AttestedClaims` field to `Identity` and `X509SVID` structs

9. **`spire/pkg/agent/manager/sync.go`**
   - Passes `AttestedClaims` from client to cache when fetching SVIDs

10. **`spire/pkg/agent/endpoints/workload/handler.go`**
    - Converts and includes `AttestedClaims` in Workload API responses
    - Passes `AttestedClaims` to workloads via gRPC Workload API

11. **`spire/pkg/server/api/svid/v1/service_test.go`**
   - Added integration tests for SovereignAttestation processing
   - Added feature flag disabled/enabled tests
   - Added policy failure tests

12. **`spire-api-sdk/Makefile`**
   - Added `sovereignattestation.proto` to protos list

**Note**: All code changes are tagged with `// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)` and wrapped under the feature flag.

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
- Evaluates `AttestedClaims` against policy (geolocation, host integrity, GPU metrics)
- Returns `AttestedClaims` in response or error on policy failure

## Regenerating Protobuf Files

After modifying `.proto` files, regenerate Go code:
```bash
./regenerate-protos.sh
```

Or manually: `cd go-spiffe && make generate && cd ../spire-api-sdk && make generate && cd ../spire && make generate`

## Logging

All Phase 1 code includes logging with tag: **"Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)"**

**Log Levels**:
- **INFO**: Feature status, Keylime calls, policy evaluation results, AttestedClaims attached to SVIDs
- **DEBUG**: Detailed request/response data, SovereignAttestation received, AttestedClaims added to responses
- **WARN**: Policy violations, missing configuration, SovereignAttestation processing issues
- **ERROR**: Failures in Keylime communication, policy errors

**Key Log Messages**:
- **Agent Bootstrap**: `DEBUG` "Received SovereignAttestation in agent bootstrap request", `INFO` "AttestedClaims attached to agent bootstrap SVID", `INFO` "Received AttestedClaims during agent bootstrap"
- **Workload SVID**: `INFO` "Processing SovereignAttestation", `DEBUG` "Added AttestedClaims to response"
- **Diagnostics**: `WARN` messages for missing/invalid `SovereignAttestation` or processing failures

Demo scripts and automated tests highlight these log messages for easy verification.

## Limitations (Phase 1)

This is a **stubbed implementation**:
1. **Keylime Verifier**: Returns fixed, hardcoded `AttestedClaims` - no actual TPM verification
2. **TPM Plugin**: No actual TPM interaction - uses stubbed data
3. **Remediation**: Policy failures return errors - no actual remediation actions
4. **Cryptographic Verification**: Certificate chain validation is stubbed

## Generating an SVID with SovereignAttestation

**Recommended**: Use the Python app demo (`python-app-demo/run-demo.sh`) which demonstrates the complete flow automatically.

**For programmatic access**, use the provided scripts:

### Using the Go Script

See `scripts/README.md` for details on `generate-sovereign-svid.go` and `dump-svid.go`.

**Quick usage:**
```bash
cd scripts
# Build scripts
go build -o generate-sovereign-svid generate-sovereign-svid.go
go build -o dump-svid dump-svid.go

# Generate SVID (after creating registration entry)
./generate-sovereign-svid -entryID <ENTRY_ID> -spiffeID <SPIFFE_ID>

# Dump SVID with Phase 1 highlights
./dump-svid -cert svid.crt -attested svid_attested_claims.json
```

### Notes

- **Feature Flag Required**: `SovereignAttestation` is only processed when `feature_flags = ["Unified-Identity"]` is set
- **Keylime Stub**: Must be running and accessible from SPIRE Server
- **Backward Compatibility**: If feature flag is disabled, `SovereignAttestation` field is ignored and normal SVID flow continues
- **Stubbed Data**: In Phase 1, all TPM data is stubbed - use base64-encoded test strings

## Kubernetes Integration

**⚠️ STATUS: INCOMPLETE - PENDING**

Kubernetes integration with SPIRE CSI driver is **incomplete** and currently pending resolution of several issues:

**Known Issues:**
1. **CSI Driver Image Pull**: The SPIRE CSI driver image (`ghcr.io/spiffe/spire-csi-driver:0.4.0`) has pull issues (403 Forbidden), preventing the CSI driver from being deployed
2. **Production Pattern Not Tested**: The full production pattern using the SPIRE CSI driver has not been end-to-end tested
3. **Workaround Available**: A simpler hostPath-based workload option exists for Phase 1 testing, but this is not the production pattern

**What Works:**
- ✅ SPIRE Server and Agent setup outside Kubernetes
- ✅ Kubernetes cluster creation (kind)
- ✅ Registration entry creation for Kubernetes workloads
- ✅ Simple hostPath-based workload deployment (non-production pattern)
- ✅ SVID dumping from workloads using hostPath mounts

**What Doesn't Work:**
- ❌ SPIRE CSI driver deployment (image pull issues)
- ❌ Production pattern with CSI driver volume mounts
- ❌ End-to-end testing of CSI driver workflow

**Alternative**: The Python app demo (`python-app-demo/`) provides a **fully working** alternative for testing Phase 1 functionality without Kubernetes complexity.

**Architecture**: Phase 1 is designed to support Kubernetes workloads using the SPIRE CSI driver, with SPIRE Server and Agent running **outside** the Kubernetes cluster for security. However, this integration is not yet complete.

**⚠️ Note**: For a **fully working** Phase 1 demo, use the Python app demo instead:
```bash
cd python-app-demo
./run-demo.sh
```

See [k8s-integration/README.md](k8s-integration/README.md) for incomplete Kubernetes integration details and known issues.

## Next Steps

1. **Run the Demo** (recommended):
   ```bash
   cd python-app-demo
   ./run-demo.sh
   ```

2. **Run Automated Test**:
   ```bash
   cd scripts
   ./test-python-demo.sh
   ```

3. **Rebuild SPIRE** (if using modified binaries):
   ```bash
   cd spire
   go build -o bin/spire-server ./cmd/spire-server
   go build -o bin/spire-agent ./cmd/spire-agent
   ```

4. **Regenerate Protobuf Files** (if modifying proto files):
   ```bash
   ./regenerate-protos.sh
   ```

5. **Run Unit/Integration Tests**: See [TESTING.md](TESTING.md)

6. **Kubernetes Integration**: ⚠️ **INCOMPLETE** - See [k8s-integration/README.md](k8s-integration/README.md) for status. Use Python app demo for working Phase 1 demonstration.

## References

- [Architecture Document](../../README-arch.md)
- [SPIRE Documentation](https://spiffe.io/docs/latest/spire/)
- [Keylime Documentation](https://keylime.readthedocs.io/)
- [SPIRE CSI Driver](https://github.com/spiffe/spiffe-csi)
