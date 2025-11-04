# Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)

This phase introduces the initial implementation of the "Unified Identity" feature, focusing on the SPIRE API and policy staging with a stubbed Keylime verifier.

## Summary of Changes

This phase introduces a new RPC, `PerformSovereignAttestation`, to the Workload API, and a new `sovereign` node attestor plugin to the SPIRE server. These additions are used to perform a sovereign attestation flow, which is a process of verifying the identity of a workload in a sovereign cloud environment.

The `PerformSovereignAttestation` RPC and the `sovereign` node attestor are feature-flagged using the `unified_identity` build tag. When this build tag is enabled, the RPC is handled by a stubbed implementation that returns a canned response, and the node attestor returns a stubbed agent ID. When the build tag is not present, the RPC returns an "unimplemented" error, and the node attestor is not available.

### Prerequisites

To build and run the code in this phase, you will need to have the following installed:

* Go 1.25.3 or later
* Docker

### Compilation - how to turn on feature flag

To enable the "Unified Identity" feature, you will need to build the SPIRE server and agent with the `unified_identity` build tag. You can do this by running the following commands:

```
go build -tags unified_identity ./cmd/spire-server
go build -tags unified_identity ./cmd/spire-agent
```

## New Tests

### Unit Tests

This phase adds unit tests for the `PerformSovereignAttestation` RPC. The tests are located in the `pkg/agent/endpoints/workload` directory and are split into two files:

* `handler_unified_identity_test.go`: This file contains the tests for the unified identity implementation of the `PerformSovereignAttestation` RPC. These tests are only run when the `unified_identity` build tag is present.
* `handler_stub_test.go`: This file contains the tests for the stub implementation of the `PerformSovereignAttestation` RPC. These tests are only run when the `unified_identity` build tag is not present.

### End-to-End Test

This phase adds an end-to-end test for the sovereign attestation flow. The test is located in the `test/integration/suites/sovereign-attestation` directory. To run the test, run the following command from the `test/integration` directory:

```
./test.sh suites/sovereign-attestation
```

### Current Tests - Backward compatibility

All existing tests have been run and they all pass. This ensures that the changes in this phase are backward compatible.
