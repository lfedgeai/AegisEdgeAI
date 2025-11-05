# Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)

This phase introduces the initial implementation of the "Unified Identity" feature, focusing on the SPIRE API and policy staging with a stubbed Keylime verifier.

## Quick Links

- **Getting Started**: See [`QUICK_START.md`](QUICK_START.md) for complete step-by-step instructions to build, test, and run everything
- **Build Instructions**: See [`BUILD_INSTRUCTIONS.md`](BUILD_INSTRUCTIONS.md) for detailed build steps
- **Implementation Details**: See [`IMPLEMENTATION_SUMMARY.md`](IMPLEMENTATION_SUMMARY.md) for technical details
- **Status**: See [`COMPLETION_STATUS.md`](COMPLETION_STATUS.md) for current completion status
- **Test Results**: See [`TEST_RESULTS.md`](TEST_RESULTS.md) for comprehensive unit test results
- **End-to-End Tests**: See [`END_TO_END_TEST_STATUS.md`](END_TO_END_TEST_STATUS.md) for end-to-end test status and manual testing guide
- **Documentation Index**: See [`DOCUMENTATION.md`](DOCUMENTATION.md) for complete documentation navigation guide

## Summary of Changes

**Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)**

This phase implements the foundational API changes and policy evaluation logic for the Unified Identity feature. All changes are wrapped under the "Unified-Identity" feature flag, which is disabled by default and can be enabled via configuration.

### Protobuf Changes

1. **Workload API Protobuf (`go-spiffe/proto/spiffe/workload/workload.proto`)**:
   - Added `SovereignAttestation` message containing TPM quote, App Key public key, App Key certificate, challenge nonce, and workload code hash
   - Added `AttestedClaims` message containing geolocation, host integrity status, and GPU metrics
   - Extended `X509SVIDRequest` with optional `sovereign_attestation` field (tag 20)
   - Extended `X509SVIDResponse` with optional `attested_claims` field (tag 30)

2. **Agent API Protobuf (`spire-api-sdk/proto/spire/api/server/svid/v1/svid.proto`)**:
   - Extended `NewX509SVIDParams` with optional `sovereign_attestation` field (tag 10) to pass attestation from Agent to Server

### Feature Flag

- **Flag Name**: `Unified-Identity`
- **Default State**: Disabled (false)
- **Location**: `spire/pkg/common/fflag/fflag.go`
- **How to Enable**: Add `"Unified-Identity"` to the `feature_flags` configuration in SPIRE Server and Agent config files

### Implementation Components

#### 1. Stubbed Keylime Verifier Client (`spire/pkg/server/sovereign/keylime/client.go`)
   - Stubbed implementation that returns fixed hardcoded attested claims
   - Returns claims for Spain geolocation with healthy GPU status for Phase 1 testing
   - Validates input attestation structure
   - All code changes tagged with "Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)"

#### 2. Policy Evaluation Engine (`spire/pkg/server/sovereign/policy.go`)
   - Evaluates attested claims against configurable policies
   - Supports geolocation allowlist, GPU metrics thresholds, and host integrity checks
   - Returns policy evaluation results with detailed reasons
   - All code changes tagged with "Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)"

#### 3. SPIRE Server Integration (`spire/pkg/server/api/svid/v1/service.go`)
   - Processes sovereign attestation in `BatchNewX509SVID` requests
   - Forwards attestation to stubbed Keylime client
   - Evaluates policy and denies SVID issuance if policy check fails
   - Comprehensive logging at appropriate levels (INFO for major events, DEBUG for detailed flow)
   - All code changes tagged with "Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)"
   - Test coverage in `service_sovereign_test.go` with comprehensive test scenarios

#### 4. SPIRE Agent Integration (`spire/pkg/agent/endpoints/workload/`)
   - `handler.go`: Processes sovereign attestation from workload requests
   - `sovereign.go`: Generates stubbed attestation and validates input
   - Includes stubbed attested claims in `X509SVIDResponse` when sovereign attestation is present
   - Comprehensive logging throughout
   - All code changes tagged with "Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)"

### Prerequisites

To build and run the code in this phase, you will need to have the following installed:

* Go 1.22.0 or later
* Protocol Buffer Compiler (protoc) - Version 3.12.4 or later
* unzip utility
* Make

### Building and Enabling the Feature

The "Unified-Identity" feature is controlled via a runtime feature flag, not a build tag. 

**Quick Start**: See `QUICK_START.md` for complete step-by-step instructions.

**Brief Overview**:

1. **Regenerate Protobuf Code** (required after modifying .proto files):
   ```bash
   cd go-spiffe && make generate
   cd ../spire-api-sdk && make generate
   ```

2. **Build SPIRE Server and Agent**:
   ```bash
   cd spire
   go build ./cmd/spire-server
   go build ./cmd/spire-agent
   ```

3. **Enable the feature flag in configuration**:
   
   Add to your SPIRE Server configuration (`server.conf`):
   ```hcl
   server {
       # ... other server config ...
       feature_flags = ["Unified-Identity"]
   }
   ```
   
   Add to your SPIRE Agent configuration (`agent.conf`):
   ```hcl
   agent {
       # ... other agent config ...
       feature_flags = ["Unified-Identity"]
   }
   ```

4. **Restart SPIRE Server and Agent** to apply the configuration changes.

**Note**: When the feature flag is disabled (default), all Unified-Identity code paths are skipped, ensuring backward compatibility. See `BUILD_INSTRUCTIONS.md` for detailed build steps.

## Testing

### Unit Tests

This phase includes comprehensive unit tests for all new functionality:

1. **Keylime Client Tests** (`spire/pkg/server/sovereign/keylime/client_test.go`):
   - Feature flag enable/disable behavior
   - Input validation
   - Stubbed claim generation
   - Request building

2. **Policy Evaluation Tests** (`spire/pkg/server/sovereign/policy_test.go`):
   - Feature flag behavior
   - Policy evaluation with various claim combinations
   - Geolocation allowlist enforcement
   - GPU metrics validation
   - Host integrity checks

3. **Agent Sovereign Tests** (`spire/pkg/agent/endpoints/workload/sovereign_test.go`):
   - Stubbed attestation generation
   - Input validation
   - Feature flag behavior

To run all tests:
```bash
cd spire
# Run all sovereign-related tests
go test ./pkg/server/sovereign/... -v
go test ./pkg/server/api/svid/v1/... -run Sovereign -v
go test ./pkg/agent/endpoints/workload/... -run Sovereign -v

# Or use the comprehensive test script
cd ..
./test_all_sovereign.sh
```

**See `QUICK_START.md` for detailed testing instructions including unit tests and integration tests.**

**See `TEST_RESULTS.md` for comprehensive unit test results with both feature flag states (enabled/disabled).**

### Integration Tests

Integration tests are available in `spire/test/integration/suites/sovereign-attestation/`:
- Setup scripts for test environment
- End-to-end flow verification
- Binary build verification

**See `QUICK_START.md` Step 3 for detailed integration test instructions.**

**See `END_TO_END_TEST_STATUS.md` for comprehensive end-to-end test status and manual testing procedures.**

### Backward Compatibility

All code changes are wrapped with feature flag checks. When the "Unified-Identity" flag is disabled (default):
- All new protobuf fields are optional and ignored
- No behavior changes occur
- All existing tests pass without modification

## Logging

All code changes include comprehensive logging at appropriate levels:

- **INFO**: Major events (sovereign attestation processing, policy evaluation results, Keylime verification)
- **DEBUG**: Detailed flow information (request details, validation steps)
- **WARN**: Policy violations, validation failures
- **ERROR**: Critical errors (deserialization failures, Keylime errors)

All log messages are prefixed with "Unified-Identity - Phase 1:" for easy filtering.

## Building and Regenerating Protobuf Code

**IMPORTANT**: After modifying the `.proto` files, you must regenerate the Go protobuf code before building.

**For detailed build instructions, see `BUILD_INSTRUCTIONS.md`**

### Quick Reference

1. **Regenerate go-spiffe protobufs**:
   ```bash
   cd go-spiffe
   make generate
   ```
   Regenerates: `proto/spiffe/workload/workload.pb.go` and `workload_grpc.pb.go`

2. **Regenerate spire-api-sdk protobufs**:
   ```bash
   cd spire-api-sdk
   make generate
   ```
   Regenerates: `proto/spire/api/server/svid/v1/svid.pb.go` and related files

3. **Build SPIRE**:
   ```bash
   cd spire
   go build ./cmd/spire-server
   go build ./cmd/spire-agent
   ```

### Troubleshooting

If you see compilation errors about undefined types like `workload.SovereignAttestation` or `workload.AttestedClaims`, this means the protobuf code needs to be regenerated. The Makefiles will automatically download the required `protoc` version and tools if they're not available.

See [`BUILD_INSTRUCTIONS.md`](BUILD_INSTRUCTIONS.md) for detailed troubleshooting steps.

For test-related issues, see [`TEST_RESULTS.md`](TEST_RESULTS.md) and [`END_TO_END_TEST_STATUS.md`](END_TO_END_TEST_STATUS.md).

## Documentation

For detailed instructions, see:

- **[`QUICK_START.md`](QUICK_START.md)**: Comprehensive guide for building, testing, and running with feature flag enabled
- **[`BUILD_INSTRUCTIONS.md`](BUILD_INSTRUCTIONS.md)**: Detailed build steps and troubleshooting
- **[`IMPLEMENTATION_SUMMARY.md`](IMPLEMENTATION_SUMMARY.md)**: Technical implementation details
- **[`COMPLETION_STATUS.md`](COMPLETION_STATUS.md)**: Current status and verification checklist
- **[`TEST_RESULTS.md`](TEST_RESULTS.md)**: Detailed unit test results with both feature flag states
- **[`END_TO_END_TEST_STATUS.md`](END_TO_END_TEST_STATUS.md)**: End-to-end test status and manual testing guide
- **[`DOCUMENTATION.md`](DOCUMENTATION.md)**: Complete documentation index and navigation guide

## Next Steps (Future Phases)

- **Phase 2**: Implement full Keylime Verifier integration (replace stubbed client)
- **Phase 3**: Implement TPM plugin and hardware integration
- **Phase 4**: Embed attested claims in SVID certificate extensions
- **Phase 5**: Implement remediation actions for policy violations

## Files Modified

### Protobuf Files
- `go-spiffe/proto/spiffe/workload/workload.proto`
- `spiffe/standards/workloadapi.proto`
- `spire-api-sdk/proto/spire/api/server/svid/v1/svid.proto`

### Go Source Files
- `spire/pkg/common/fflag/fflag.go` - Feature flag definition
- `spire/pkg/server/sovereign/keylime/client.go` - Stubbed Keylime client
- `spire/pkg/server/sovereign/keylime/client_test.go` - Keylime client tests
- `spire/pkg/server/sovereign/policy.go` - Policy evaluation engine
- `spire/pkg/server/sovereign/policy_test.go` - Policy tests
- `spire/pkg/server/api/svid/v1/service.go` - Server SVID service integration
- `spire/pkg/server/api/svid/v1/service_sovereign_test.go` - Server SVID service sovereign tests
- `spire/pkg/agent/endpoints/workload/handler.go` - Agent workload handler
- `spire/pkg/agent/endpoints/workload/sovereign.go` - Agent sovereign attestation handling
- `spire/pkg/agent/endpoints/workload/sovereign_test.go` - Agent sovereign tests

### Test Files
- `test_all_sovereign.sh` - Comprehensive test script for all sovereign components
- `spire/test/integration/suites/sovereign-attestation/` - Integration test suite

All code changes are tagged with: `"Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)"`
