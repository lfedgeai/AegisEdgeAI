# Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)

This phase introduces the initial implementation of the "Unified Identity" feature, focusing on the SPIRE API and policy staging with a stubbed Keylime verifier.

## Summary of Changes

This phase introduces a new RPC, `PerformSovereignAttestation`, to the Workload API. This RPC is used to perform a sovereign attestation flow, which is a process of verifying the identity of a workload in a sovereign cloud environment.

The `PerformSovereignAttestation` RPC is feature-flagged using the `unified_identity` build tag. When this build tag is enabled, the RPC is handled by a stubbed implementation that returns a canned response. When the build tag is not present, the RPC returns an "unimplemented" error.

### Prerequisites

To build and run the code in this phase, you will need to have the following installed:

* Go 1.25.3 or later
* Docker

### Compilation - how to turn on feature flag

To enable the "Unified Identity" feature, you will need to build the SPIRE agent with the `unified_identity` build tag. You can do this by running the following command:

```
go build -tags unified_identity ./cmd/spire-agent
```

## New Tests

### Unit Tests

This phase adds unit tests for the `PerformSovereignAttestation` RPC. The tests are located in the `pkg/agent/endpoints/workload` directory and are split into two files:

* `handler_unified_identity_test.go`: This file contains the tests for the unified identity implementation of the `PerformSovereignAttestation` RPC. These tests are only run when the `unified_identity` build tag is present.
* `handler_stub_test.go`: This file contains the tests for the stub implementation of the `PerformSovereignAttestation` RPC. These tests are only run when the `unified_identity` build tag is not present.

### End-to-End Test

There are no end-to-end tests in this phase. End-to-end tests will be added in a future phase.

### Current Tests - Backward compatibility

All existing tests have been run and they all pass. This ensures that the changes in this phase are backward compatible.
