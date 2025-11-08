## Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)

**✅ STATUS: COMPLETE AND TESTED** (with **⚠️ Kubernetes Integration: INCOMPLETE**)

This directory contains the implementation of **Phase 1** of the Unified Identity for Sovereign AI architecture. This phase implements all necessary SPIRE API changes and policy logic without relying on a functional Keylime or TPM plugin.

**Phase 1 has been successfully implemented and tested end-to-end** for Linux workloads (Python app demo). Includes:
- ✅ Agent bootstrap and workload SVID flows with AttestedClaims
- ✅ Enhanced diagnostic logging with highlighted AttestedClaims
- ✅ Interactive demo with step-by-step prompts
- ✅ Automated end-to-end regression tests

## Table of Contents

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

**Phase 1 is complete and fully functional.** All components implemented, tested, and verified:

- ✅ **SPIRE Server**: Processes `SovereignAttestation`, calls Keylime stub, evaluates policy, returns `AttestedClaims`
- ✅ **SPIRE Agent**: Sends `SovereignAttestation` during bootstrap/renewal, receives and passes `AttestedClaims` to workloads
- ✅ **Keylime Stub**: Returns fixed `AttestedClaims` (geolocation, host integrity, GPU metrics)
  - ⚠ **Note**: Multiple GPU support for GPU metrics is work in progress
- ✅ **Policy Engine**: Evaluates `AttestedClaims` with configurable rules
- ✅ **Agent Bootstrap**: AttestedClaims flow verified with enhanced diagnostic logging
- ✅ **Workload SVID**: Complete flow from Python app → Agent → Server → Keylime → Policy → AttestedClaims

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

3. **Rebuild SPIRE** (if using modified binaries - see [Next Steps](#next-steps))

**Note**: If using existing SPIRE binaries without Phase 1 changes, the feature flag is ignored (backward compatible).

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
- ⚠ **Note**: Multiple GPU support for GPU metrics is work in progress

For complete details, see **[SOVEREIGN_SVID_FORMAT.md](SOVEREIGN_SVID_FORMAT.md)**.

## API Changes

### Protobuf Definitions

**New Messages**:
- `SovereignAttestation`: Contains TPM quote, app key, challenge nonce, workload code hash
- `AttestedClaims`: Contains geolocation, host integrity status, GPU metrics
  - ⚠ **Note**: Multiple GPU support for GPU metrics is work in progress

**Modified Messages** (added optional fields):
- `X509SVIDRequest` / `X509SVIDResponse` (workload.proto): `sovereign_attestation`, `attested_claims`
- `NewX509SVIDParams` / `BatchNewX509SVIDResponse.Result` (svid.proto): `sovereign_attestation`, `attested_claims`
- `AgentX509SVIDParams` / `AttestAgentResponse.Result` / `RenewAgentResponse` (agent.proto): `sovereign_attestation`, `attested_claims`

See `spire-api-sdk/proto/spire/api/types/sovereignattestation.proto` for complete definitions.

### Keylime Verifier API

**Endpoint**: `POST /v2.4/verify/evidence`

**Request**: Contains `SovereignAttestation` data (TPM quote, app key, nonce) and metadata.

**Response**: Returns `verified: true` and `attested_claims` with geolocation, host integrity status, and GPU metrics.

See `keylime-stub/main.go` for the complete API implementation and request/response format.

## Code Changes Summary

**Files Created**:
- `spire/pkg/server/keylime/client.go` - Keylime Verifier API client
- `spire/pkg/server/policy/engine.go` - Policy evaluation engine
- `spire-api-sdk/proto/spire/api/types/sovereignattestation.proto` - Protobuf definitions
- `keylime-stub/main.go` - Mock Keylime Verifier API server

**Files Modified**:
- **Protobuf files**: Added `SovereignAttestation` and `AttestedClaims` to workload, svid, and agent protos
- **SPIRE Server**: `svid/v1/service.go` and `agent/v1/service.go` - Process `SovereignAttestation`, call Keylime, evaluate policy, return `AttestedClaims`
- **SPIRE Agent**: `client/client.go`, `attestor/node/node.go`, `manager/sync.go`, `endpoints/workload/handler.go` - Send `SovereignAttestation`, receive and pass `AttestedClaims` to workloads
- **Feature Flag**: `spire/pkg/common/fflag/fflag.go` - Added `FlagUnifiedIdentity`

All changes are tagged with `// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)` and wrapped under the feature flag.

## Components

**Keylime Verifier Stub** (`keylime-stub/`): Mock Keylime Verifier API that returns fixed `AttestedClaims`. Configurable via environment variables (port, TLS certs, geolocation, integrity, GPU status).
- ⚠ **Note**: Multiple GPU support for GPU metrics is work in progress

**SPIRE Server Integration**:
- **Keylime Client** (`spire/pkg/server/keylime/client.go`): Builds requests from `SovereignAttestation`, calls Keylime API, returns `AttestedClaims`
- **Policy Engine** (`spire/pkg/server/policy/engine.go`): Evaluates geolocation, host integrity, GPU metrics against configurable rules
  - ⚠ **Note**: Multiple GPU support for GPU metrics is work in progress
- **SVID Service** (`spire/pkg/server/api/svid/v1/service.go`): Processes `SovereignAttestation`, calls Keylime, evaluates policy, returns `AttestedClaims`

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

**For programmatic access**: See `scripts/README.md` for `generate-sovereign-svid.go` and `dump-svid.go`.

**Quick usage:**
```bash
cd scripts
go build -o generate-sovereign-svid generate-sovereign-svid.go
go build -o dump-svid dump-svid.go
./generate-sovereign-svid -entryID <ENTRY_ID> -spiffeID <SPIFFE_ID>
./dump-svid -cert svid.crt -attested svid_attested_claims.json
```

**Requirements**: Feature flag enabled, Keylime stub running. In Phase 1, all TPM data is stubbed.

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

**Alternative**: The Python app demo (`python-app-demo/run-demo.sh`) provides a **fully working** alternative.

**Architecture**: Designed to support Kubernetes workloads using SPIRE CSI driver, with SPIRE Server and Agent running **outside** the cluster. Not yet complete.

See [k8s-integration/README.md](k8s-integration/README.md) for details and known issues.

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

4. **Regenerate Protobuf Files** (if modifying proto files): `./regenerate-protos.sh`

5. **Run Unit/Integration Tests**: See [TESTING.md](TESTING.md)

## References

- [Architecture Document](../../README-arch.md)
- [SPIRE Documentation](https://spiffe.io/docs/latest/spire/)
- [Keylime Documentation](https://keylime.readthedocs.io/)
- [SPIRE CSI Driver](https://github.com/spiffe/spiffe-csi)
