# Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)

This phase introduces the initial implementation of the "Unified Identity" feature, focusing on the SPIRE API and policy staging with a stubbed Keylime verifier.

## Summary of Changes

- **SPIRE API SDK (`spire-api-sdk`):**
  - Modified `proto/spire/api/server/svid/v1/svid.proto` to include the `SovereignAttestation` and `AttestedClaims` messages.
  - The `SovereignAttestation` message is added to the `BatchNewX509SVIDRequest` to allow the agent to send attestation data to the server.
  - The `AttestedClaims` message is added to the `BatchNewX509SVIDResponse` to allow the server to return attested claims to the agent.

- **SPIRE (`spire`):**
  - **Agent:** Modified `pkg/agent/client/client.go` to send stubbed `SovereignAttestation` data in the `BatchNewX509SVID` request.
  - **Server:** Implemented a mock Keylime verifier in `pkg/server/api/svid/v1/service.go` to process the `SovereignAttestation` data and return stubbed `AttestedClaims`. The verifier is only called when the request contains `SovereignAttestation` data.

## Compiling and Running Tests

### Prerequisites

Before you can compile the binaries or run the tests, you need to make sure you have the following tools installed:

- Go (version 1.22.0 or later)
- Docker

### Compilation

To compile the `spire-server` and `spire-agent` binaries with the Phase 1 changes, run the following command from the `hybrid-cloud-poc/code-rollout-phase-1` directory:

```bash
make -C spire build
```

The compiled binaries will be located in the `hybrid-cloud-poc/code-rollout-phase-1/spire/bin` directory.

**Note on Dependencies:** The `go-spiffe` and `spire-api-sdk` directories contain Go libraries that are used as dependencies by the `spire` project. They are not compiled into standalone binaries. Instead, they are automatically compiled into the `spire-server` and `spire-agent` binaries when you run the `make -C spire build` command.

### Running Tests

#### Unit Tests

To run the unit tests for the modified packages, use the following commands from the `hybrid-cloud-poc/code-rollout-phase-1` directory:

```bash
go test ./... -C spire/pkg/agent/client
go test ./... -C spire/pkg/server/api/svid/v1
```

#### End-to-End Test

An end-to-end test has been added to `spire/pkg/server/api/svid/v1/e2e_test.go` to verify the entire flow. To run this test, use the following command from the `hybrid-cloud-poc/code-rollout-phase-1` directory:

```bash
go test ./... -C spire/pkg/server/api/svid/v1
```
