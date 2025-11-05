# Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)

## Overview

This directory contains the implementation of **Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)** for the Unified Identity for Sovereign AI project. This phase implements all necessary SPIRE API changes and policy logic in the SPIRE Server without relying on a functional Keylime or TPM plugin.

## Architecture

Phase 1 implements the following components:

1. **Proto Definitions**: Extended the SPIRE Workload API with `SovereignAttestation` and `AttestedClaims` messages
2. **SPIRE Agent**: Modified to accept and log `SovereignAttestation` in `X509SVIDRequest` (stubbed for Phase 1)
3. **SPIRE Server**: Policy evaluation engine that processes `AttestedClaims` from Keylime
4. **Stubbed Keylime Verifier**: Mock HTTP server that returns fixed, hardcoded `AttestedClaims` responses

## Feature Flag

All Phase 1 changes are wrapped under the **`Unified-Identity`** feature flag, which is **disabled by default**. To enable it:

### For SPIRE Server

Add to your server configuration file:

```hcl
server {
    # ... other config ...
    
    feature_flags = ["Unified-Identity"]
}
```

### For SPIRE Agent

Add to your agent configuration file:

```hcl
agent {
    # ... other config ...
    
    feature_flags = ["Unified-Identity"]
}
```

### Rebuild

After enabling the feature flag, rebuild SPIRE:

```bash
cd spire
make build
```

## Components

### 1. Proto Definitions (`go-spiffe/proto/spiffe/workload/workload.proto`)

Added new messages:
- `SovereignAttestation`: Contains TPM-signed attestation, App Key public key, certificate, nonce, and workload code hash
- `AttestedClaims`: Contains verified facts from Keylime (geolocation, host integrity status, GPU metrics)
- Extended `X509SVIDRequest` with optional `sovereign_attestation` field
- Extended `X509SVIDResponse` with optional `attested_claims` field

### 2. SPIRE Agent Changes (`spire/pkg/agent/endpoints/workload/handler.go`)

- Modified `FetchX509SVID` to accept and log `SovereignAttestation` when present
- Logs attestation data at DEBUG level with tag `[Unified-Identity Phase 1]`
- In Phase 1, attestation is logged but not forwarded to server (will be implemented in later phases)

### 3. SPIRE Server Changes (`spire/pkg/server/unifiedidentity/`)

#### Keylime Client (`keylime_client.go`)
- HTTP client for communicating with Keylime Verifier
- Sends verification requests to `POST /v2.4/verify/evidence`
- Converts JSON responses to protobuf `AttestedClaims`

#### Policy Engine (`policy.go`)
- Evaluates `AttestedClaims` against configurable policies
- Policy checks:
  - **Geolocation**: Validates against allowed geolocation patterns
  - **Host Integrity**: Requires `PASSED_ALL_CHECKS` status
  - **GPU Metrics**: Validates GPU status and utilization thresholds
- Returns `PolicyEvaluationResult` with allowed/denied status and reason

### 4. Stubbed Keylime Verifier (`keylime-stub/`)

A mock HTTP server that:
- Accepts `POST /v2.4/verify/evidence` requests
- Validates request format (nonce, quote, base64 encoding)
- Returns fixed, hardcoded `AttestedClaims`:
  - Geolocation: `"Spain: N40.4168, W3.7038"`
  - Host Integrity: `"passed_all_checks"`
  - GPU Metrics: `status: "healthy"`, `utilization_pct: 15.0`, `memory_mb: 10240`

## Building and Running

### Prerequisites

- Go 1.24+
- Make
- Protocol Buffers compiler (protoc)

### Build SPIRE

```bash
cd spire
make build
```

### Run Stubbed Keylime Verifier

```bash
cd keylime-stub
go run verifier.go
```

The verifier will start on port 8888 by default. To change the port, modify the code or use environment variables.

### Build and Run Tests

```bash
# Run all tests
cd spire
go test ./pkg/server/unifiedidentity/...

# Run Keylime stub tests
cd keylime-stub
go test ./...
```

## Testing

### Unit Tests

#### Policy Engine Tests (`spire/pkg/server/unifiedidentity/policy_test.go`)
- Tests geolocation pattern matching
- Tests host integrity validation
- Tests GPU metrics validation
- Tests policy evaluation with various claim combinations

#### Keylime Stub Tests (`keylime-stub/verifier_test.go`)
- Tests HTTP endpoint handling
- Tests request validation
- Tests response formatting
- Tests protobuf conversion

### End-to-End Tests

See `tests/e2e/` directory for end-to-end test scenarios.

## Example Usage

### 1. Start Stubbed Keylime Verifier

```bash
cd keylime-stub
go run verifier.go
```

### 2. Configure SPIRE Server with Feature Flag

```hcl
server {
    bind_address = "0.0.0.0"
    bind_port = 8081
    
    feature_flags = ["Unified-Identity"]
    
    # ... other config ...
}
```

### 3. Configure SPIRE Agent with Feature Flag

```hcl
agent {
    server_address = "localhost"
    server_port = 8081
    
    feature_flags = ["Unified-Identity"]
    
    # ... other config ...
}
```

### 4. Send Request with SovereignAttestation (Workload API)

When a workload sends an `X509SVIDRequest` with `SovereignAttestation`, the agent will:
- Log the attestation data (if feature flag enabled)
- Process the request normally (Phase 1: no server forwarding yet)

## Logging

All Phase 1 code includes logging with the tag `[Unified-Identity Phase 1]`:

- **DEBUG**: Detailed information about attestation processing, policy evaluation
- **INFO**: Successful verification and policy evaluation results
- **WARN**: Policy violations, verification failures
- **ERROR**: Critical errors, request processing failures

Example log output:
```
[Unified-Identity Phase 1] Received SovereignAttestation in X509SVIDRequest
[Unified-Identity Phase 1] Sending verification request to Keylime
[Unified-Identity Phase 1] Successfully verified attestation with Keylime
[Unified-Identity Phase 1] Policy evaluation passed
```

## Code Comments

All Phase 1 code changes are tagged with:
```
// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)
```

This tag makes it easy to identify all Phase 1 changes in the codebase.

## Known Limitations (Phase 1)

1. **Stubbed Keylime**: The Keylime Verifier is a stub that always returns fixed responses. Real cryptographic verification will be implemented in Phase 2.

2. **No Agent-Server Integration**: Agents log `SovereignAttestation` but don't forward it to the server yet. This will be implemented in later phases.

3. **No TPM Integration**: TPM quote generation and App Key certificate creation are not implemented. This will be implemented in Phase 3.

4. **Fixed Policy**: Policy configuration is currently hardcoded. Dynamic policy configuration will be added in later phases.

## Next Steps

- **Phase 2**: Implement core Keylime functionality (fact-provider logic)
- **Phase 3**: Hardware integration and delegated certification
- **Phase 4**: Full end-to-end integration with hardware TPM

## Directory Structure

```
code-rollout-phase-1/
├── go-spiffe/                    # SPIFFE Go library with proto definitions
│   └── proto/spiffe/workload/
│       └── workload.proto        # Extended with SovereignAttestation and AttestedClaims
├── spire/                        # SPIRE server and agent
│   └── pkg/
│       ├── agent/endpoints/workload/
│       │   └── handler.go        # Agent workload API handler (modified)
│       ├── common/fflag/
│       │   └── fflag.go          # Feature flags (Unified-Identity added)
│       └── server/unifiedidentity/
│           ├── keylime_client.go # Keylime HTTP client
│           ├── policy.go         # Policy evaluation engine
│           └── policy_test.go    # Policy unit tests
├── keylime-stub/                 # Stubbed Keylime Verifier
│   ├── verifier.go               # HTTP server implementation
│   └── verifier_test.go          # Unit tests
└── README.md                     # This file
```

## Troubleshooting

### Feature Flag Not Working

1. Ensure the feature flag is correctly spelled: `"Unified-Identity"` (case-sensitive)
2. Rebuild SPIRE after enabling the flag
3. Check logs for `[Unified-Identity Phase 1]` messages to confirm the flag is active

### Keylime Verifier Not Responding

1. Check that the verifier is running: `curl http://localhost:8888/v2.4/verify/evidence`
2. Verify the port is not already in use
3. Check firewall settings

### Policy Evaluation Failures

1. Review policy configuration in `policy.go`
2. Check logs for specific policy violation reasons
3. Verify `AttestedClaims` contain expected values

## Contributing

When making changes to Phase 1 code:

1. Add the tag `// Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)` to all new code
2. Include appropriate logging with `[Unified-Identity Phase 1]` prefix
3. Add unit tests for new functionality
4. Update this README if adding new features or changing behavior

## References

- [Architecture Document](../../README-arch.md)
- [SPIRE Documentation](https://spiffe.io/docs/latest/spire/)
- [SPIFFE Workload API Specification](https://github.com/spiffe/spiffe/blob/main/standards/SPIFFE_Workload_API.md)

