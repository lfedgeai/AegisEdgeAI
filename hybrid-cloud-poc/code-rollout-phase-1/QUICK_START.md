# Quick Start Guide - Phase 1 Implementation

## Overview

This comprehensive guide covers building, testing, and using the Phase 1 Unified Identity feature in SPIRE. It includes step-by-step instructions for building, running unit tests, integration tests, and enabling the feature flag.

## Prerequisites

### Required Software

1. **Go 1.22.0 or later**
   ```bash
   go version
   # Should show: go version go1.22.0 or later
   ```

2. **Protocol Buffer Compiler (protoc)**
   ```bash
   protoc --version
   # Should show: libprotoc 3.12.4 or later
   ```

3. **Build Tools**
   ```bash
   which make unzip
   # Should show paths to both tools
   ```

### Install Missing Dependencies

**On Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y unzip build-essential

# Install protoc if needed
PROTOC_VERSION=30.2
curl -LO "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip"
unzip protoc-${PROTOC_VERSION}-linux-x86_64.zip -d /tmp/protoc
sudo mv /tmp/protoc/bin/protoc /usr/local/bin/
sudo mv /tmp/protoc/include/* /usr/local/include/
```

**On macOS:**
```bash
brew install protobuf unzip
```

## Step 1: Build Everything

### 1.1 Regenerate Protobuf Code

**Regenerate go-spiffe protobufs:**
```bash
cd hybrid-cloud-poc/code-rollout-phase-1/go-spiffe
make generate
```

Expected output:
```
compiling gRPC proto/spiffe/workload/workload.proto...
compiling proto proto/spiffe/workload/workload.proto...
```

**Regenerate spire-api-sdk protobufs:**
```bash
cd ../spire-api-sdk
make generate
```

Expected output:
```
compiling proto/spire/api/server/svid/v1/svid.proto...
compiling API proto/spire/api/server/svid/v1/svid.proto...
```

### 1.2 Build SPIRE Server and Agent

```bash
cd ../spire

# Build SPIRE Server
go build ./cmd/spire-server

# Build SPIRE Agent
go build ./cmd/spire-agent
```

### 1.3 Verify Build

```bash
# Check binaries were created
ls -lh spire-server spire-agent

# Verify they run
./spire-server --version
./spire-agent --version
```

Expected output:
```
1.14.0-dev-unk
```

## Step 2: Run Unit Tests

### 2.1 Test Keylime Client

```bash
cd hybrid-cloud-poc/code-rollout-phase-1/spire
go test ./pkg/server/sovereign/keylime/... -v
```

**Expected Results:**
- `TestNewClient` - PASS
- `TestVerifyEvidence_FeatureFlagDisabled` - PASS
- `TestVerifyEvidence_FeatureFlagEnabled` - PASS
- `TestVerifyEvidence_ValidationErrors` - PASS
- `TestBuildVerifyRequest` - PASS

### 2.2 Test Policy Engine

```bash
go test ./pkg/server/sovereign/... -v
```

**Expected Results:**
- `TestDefaultPolicyConfig` - PASS
- `TestEvaluatePolicy_FeatureFlagDisabled` - PASS
- `TestEvaluatePolicy_FeatureFlagEnabled` - PASS
- `TestEvaluatePolicy_NilClaims` - PASS
- `TestEvaluatePolicy_GPUUtilizationThreshold` - PASS
- `TestEvaluatePolicy_NoGPUMetrics` - PASS
- `TestEvaluatePolicy_MultipleGeolocations` - PASS

### 2.3 Test Agent Sovereign Handling

```bash
go test ./pkg/agent/endpoints/workload/... -run Sovereign -v
```

**Expected Results:**
- `TestGenerateStubbedSovereignAttestation_FeatureFlagDisabled` - PASS
- `TestGenerateStubbedSovereignAttestation_FeatureFlagEnabled` - PASS
- `TestValidateSovereignAttestation` - PASS
- `TestProcessSovereignAttestation` - PASS

### 2.4 Test Server SVID Service

```bash
go test ./pkg/server/api/svid/v1/... -run Sovereign -v
```

**Expected Results:**
- `TestBatchNewX509SVID_WithSovereignAttestation` - PASS
- `TestBatchNewX509SVID_FeatureFlagDisabled` - PASS

### 2.5 Run All Sovereign Tests (Comprehensive)

```bash
cd hybrid-cloud-poc/code-rollout-phase-1
./test_all_sovereign.sh
```

**Expected Output:**
```
==========================================
Sovereign Attestation Test Suite
==========================================
Testing Keylime Client... PASSED
Testing Policy Engine... PASSED
Testing Server SVID Service (Sovereign)... PASSED
Testing Agent Workload Handler... PASSED

==========================================
Test Summary
==========================================
Passed: 4
Failed: 0

All tests passed!
```

## Step 3: Run Integration Tests

### 3.1 Integration Test Setup

```bash
cd hybrid-cloud-poc/code-rollout-phase-1/spire/test/integration/suites/sovereign-attestation

# Make scripts executable
chmod +x 00-setup 01-test-sovereign-attestation teardown

# Run setup
./00-setup
```

This will:
- Build SPIRE Server and Agent binaries
- Place them in the test suite directory

### 3.2 Run Integration Test

```bash
./01-test-sovereign-attestation
```

**Expected Output:**
```
Running sovereign attestation integration test...
Sovereign attestation integration test passed
```

### 3.3 Cleanup Integration Test

```bash
./teardown
```

This removes the test binaries and cleans up temporary files.

### 3.4 Full Integration Test Run

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/spire/test/integration/suites/sovereign-attestation
./00-setup && ./01-test-sovereign-attestation && ./teardown
```

**Note**: Full end-to-end integration testing requires running SPIRE Server and Agent with the feature flag enabled (see Step 4).

## Feature Flag

**Name**: `Unified-Identity`  
**Default**: Disabled (false)  
**Location**: `spire/pkg/common/fflag/fflag.go`

## Step 4: Enable Feature Flag

### 4.1 Understanding the Feature Flag

- **Flag Name**: `Unified-Identity`
- **Default**: Disabled (false)
- **Location**: `spire/pkg/common/fflag/fflag.go`
- **Behavior**: When disabled, sovereign attestation code is present but bypassed. When enabled, sovereign attestation is processed and policy is evaluated.

### 4.2 Create SPIRE Server Configuration

Create `server.conf`:
```hcl
server {
    bind_address = "127.0.0.1"
    bind_port = "8081"
    registration_uds_path = "/tmp/spire-registration.sock"
    
    # Unified-Identity - Phase 1: Enable feature flag
    feature_flags = ["Unified-Identity"]
    
    data_dir = "./data/server"
    log_level = "INFO"
    
    ca_key_type = "rsa-2048"
    ca_ttl = "168h"
    
    trust_domain = "example.org"
}

plugins {
    DataStore "sql" {
        plugin_data {
            database_type = "sqlite3"
            connection_string = "./data/server/datastore.sqlite3"
        }
    }
}
```

### 4.2 Create SPIRE Agent Configuration

Create `agent.conf`:
```hcl
agent {
    data_dir = "./data/agent"
    log_level = "INFO"
    
    # Unified-Identity - Phase 1: Enable feature flag
    feature_flags = ["Unified-Identity"]
    
    trust_domain = "example.org"
    
    server_address = "127.0.0.1"
    server_port = "8081"
    
    # Workload attestation
    workload_attestation {
        plugin "unix" {
            plugin_data {}
        }
    }
}
```

### 4.3 Initialize SPIRE Server

```bash
cd hybrid-cloud-poc/code-rollout-phase-1/spire

# Create data directory
mkdir -p data/server

# Initialize server
./spire-server run -config server.conf &
SERVER_PID=$!

# Wait for server to start
sleep 3

# Generate join token
./spire-server token generate -spiffeID spiffe://example.org/agent
# Copy the token from output
```

### 4.4 Join SPIRE Agent

```bash
# Create data directory
mkdir -p data/agent

# Start agent with join token (replace TOKEN with actual token)
./spire-agent run -config agent.conf -joinToken <TOKEN> &
AGENT_PID=$!

# Wait for agent to start
sleep 3
```

### 4.5 Verify Feature Flag is Enabled

Check server logs:
```bash
grep "Unified-Identity" data/server/*.log
```

Expected output:
```
INFO Unified-Identity feature flag enabled
INFO Unified-Identity - Phase 1: Keylime client initialized
```

Check agent logs:
```bash
grep "Unified-Identity" data/agent/*.log
```

Expected output:
```
INFO Unified-Identity feature flag enabled
```

## Step 5: Test Feature with Feature Flag Enabled

### 5.1 Create Test Workload Entry

```bash
# Create a workload registration entry
./spire-server entry create \
    -parentID spiffe://example.org/agent \
    -spiffeID spiffe://example.org/workload \
    -selector unix:uid:$(id -u)
```

### 5.2 Verify Logs Show Sovereign Attestation Processing

```bash
# Server logs
tail -f data/server/*.log | grep "Unified-Identity - Phase 1:"

# Agent logs
tail -f data/agent/*.log | grep "Unified-Identity - Phase 1:"
```

Expected log messages:
- `"Unified-Identity - Phase 1: Processing sovereign attestation request"`
- `"Unified-Identity - Phase 1: Using stubbed Keylime Verifier"`
- `"Unified-Identity - Phase 1: Policy evaluation passed"`

## Step 6: Test Feature Flag Disabled (Default)

### 6.1 Disable Feature Flag

Edit `server.conf` and `agent.conf`, remove or comment out:
```hcl
# feature_flags = ["Unified-Identity"]
```

### 6.2 Restart Services

```bash
# Kill existing processes
kill $SERVER_PID $AGENT_PID

# Restart without feature flag
./spire-server run -config server.conf &
./spire-agent run -config agent.conf -joinToken <TOKEN> &
```

### 6.3 Verify Sovereign Attestation is Ignored

When feature flag is disabled:
- Sovereign attestation in requests is ignored
- Normal SVID issuance proceeds
- No Keylime verification occurs
- No policy evaluation occurs
- No "Unified-Identity - Phase 1:" log messages appear

## Step 7: Run All Tests (Comprehensive)

### 7.1 Run All Unit Tests

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/spire

# Run all sovereign-related unit tests
go test ./pkg/server/sovereign/... -v
go test ./pkg/server/api/svid/v1/... -v -run Sovereign
go test ./pkg/agent/endpoints/workload/... -v -run Sovereign
```

### 7.2 Run Comprehensive Test Script

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1
./test_all_sovereign.sh
```

**Expected Output**:
```
==========================================
Sovereign Attestation Test Suite
==========================================

Testing Keylime Client... PASSED
Testing Policy Engine... PASSED
Testing Server SVID Service (Sovereign)... PASSED
Testing Agent Workload Handler... PASSED

==========================================
Test Summary
==========================================
Passed: 4
Failed: 0

All tests passed!
```

### 7.3 Test Feature Flag Behavior

Run tests that specifically test feature flag enabled/disabled behavior:

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/spire

# Test with feature flag enabled (tests enable it automatically)
go test ./pkg/server/sovereign/keylime/... -v -run FeatureFlagEnabled
go test ./pkg/server/sovereign/... -v -run FeatureFlagEnabled
go test ./pkg/server/api/svid/v1/... -v -run WithSovereignAttestation
go test ./pkg/agent/endpoints/workload/... -run FeatureFlagEnabled -v

# Test with feature flag disabled (default behavior)
go test ./pkg/server/sovereign/keylime/... -v -run FeatureFlagDisabled
go test ./pkg/server/sovereign/... -v -run FeatureFlagDisabled
go test ./pkg/server/api/svid/v1/... -v -run FeatureFlagDisabled
go test ./pkg/agent/endpoints/workload/... -run FeatureFlagDisabled -v
```

### 7.4 Complete Test Checklist

Run this complete checklist to verify everything works:

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1

# 1. Build Everything
cd go-spiffe && make generate && cd ..
cd spire-api-sdk && make generate && cd ..
cd spire && go build ./cmd/spire-server ./cmd/spire-agent

# 2. Verify Build
ls -lh spire-server spire-agent
./spire-server --version
./spire-agent --version

# 3. Unit Tests (comprehensive)
./test_all_sovereign.sh

# 4. Individual Test Suites
go test ./pkg/server/sovereign/keylime/... -v
go test ./pkg/server/sovereign/... -v
go test ./pkg/server/api/svid/v1/... -v -run Sovereign
go test ./pkg/agent/endpoints/workload/... -run Sovereign -v

# 5. Feature Flag Tests
go test ./pkg/server/sovereign/keylime/... -v -run FeatureFlag
go test ./pkg/server/sovereign/... -v -run FeatureFlag
go test ./pkg/server/api/svid/v1/... -v -run FeatureFlag
go test ./pkg/agent/endpoints/workload/... -run FeatureFlag -v

# 6. Integration Tests
cd test/integration/suites/sovereign-attestation
chmod +x *.sh
./00-setup && ./01-test-sovereign-attestation && ./teardown
```

All tests should pass. If any fail, check the troubleshooting section.

## Quick Reference

### Build Commands
```bash
# Regenerate protobufs
cd go-spiffe && make generate
cd ../spire-api-sdk && make generate

# Build binaries
cd ../spire
go build ./cmd/spire-server
go build ./cmd/spire-agent
```

### Test Commands
```bash
# Run all sovereign tests
./test_all_sovereign.sh

# Run specific test suites
go test ./pkg/server/sovereign/... -v
go test ./pkg/server/api/svid/v1/... -v -run Sovereign
go test ./pkg/agent/endpoints/workload/... -v -run Sovereign
```

### Feature Flag Configuration
```hcl
# In server.conf and agent.conf
feature_flags = ["Unified-Identity"]
```

### Log Filtering
```bash
# View all Unified Identity logs
grep "Unified-Identity - Phase 1:" logs/*.log

# Follow logs in real-time
tail -f logs/*.log | grep "Unified-Identity - Phase 1:"
```

## API Usage

### Workload API (X509SVIDRequest)

Workloads can optionally include sovereign attestation:

```go
req := &workload.X509SVIDRequest{
    SovereignAttestation: &workload.SovereignAttestation{
        TpmSignedAttestation: "base64-encoded-tpm-quote",
        AppKeyPublic:         "pem-or-base64-public-key",
        AppKeyCertificate:    []byte("der-certificate"),
        ChallengeNonce:       "server-issued-nonce",
        WorkloadCodeHash:     "optional-code-hash",
    },
}
```

### Response (X509SVIDResponse)

Responses include attested claims when sovereign attestation is processed:

```go
resp := &workload.X509SVIDResponse{
    Svids: []*workload.X509SVID{...},
    AttestedClaims: []*workload.AttestedClaims{
        {
            Geolocation:        "Spain: N40.4168, W3.7038",
            HostIntegrityStatus: workload.AttestedClaims_PASSED_ALL_CHECKS,
            GpuMetricsHealth: &workload.AttestedClaims_GpuMetrics{
                Status:        "healthy",
                UtilizationPct: 15.0,
                MemoryMb:      10240,
            },
        },
    },
}
```

## Policy Configuration

Default policy (in `spire/pkg/server/sovereign/policy.go`):

```go
config := &sovereignpolicy.PolicyConfig{
    AllowedGeolocations:    []string{"Spain"},
    MinGPUUtilizationPct:   0.0,
    MinGPUMemoryMB:         0,
    RequireHealthyGPUStatus: false,
}
```

Customize by modifying the `SovereignPolicyConfig` in the SVID service configuration.

## Logging

All Unified Identity logs are prefixed with:
```
"Unified-Identity - Phase 1:"
```

Filter logs:
```bash
# View all Unified Identity logs
journalctl -u spire-server | grep "Unified-Identity - Phase 1:"

# Or in log files
grep "Unified-Identity - Phase 1:" /var/log/spire/server.log
```

## Troubleshooting

### Feature Not Working

1. **Check feature flag is enabled**:
   ```bash
   grep "feature_flags" server.conf agent.conf
   ```

2. **Check logs for feature flag status**:
   ```bash
   grep "Unified-Identity feature flag" logs/*.log
   ```

3. **Verify protobuf code is regenerated**:
   ```bash
   cd go-spiffe && make generate
   cd ../spire-api-sdk && make generate
   ```

### Build Errors

If you see errors about undefined types:
- `workload.SovereignAttestation`
- `workload.AttestedClaims`

**Solution**: Regenerate protobuf code (see BUILD_INSTRUCTIONS.md)

### Test Failures

If tests fail:
1. Ensure feature flag is loaded in test: `fflag.Load([]string{"Unified-Identity"})`
2. Check test cleanup: `defer fflag.Unload()`
3. Verify protobuf code is up to date

## Architecture

### Flow Diagram

```
Workload → Agent (Workload API)
    ↓
Agent generates/processes SovereignAttestation
    ↓
Agent → Server (Agent API with SovereignAttestation)
    ↓
Server → Keylime Verifier (stubbed in Phase 1)
    ↓
Server evaluates Policy
    ↓
Server → Agent (SVID with AttestedClaims)
    ↓
Agent → Workload (Response with AttestedClaims)
```

## Key Components

1. **Keylime Client** (`spire/pkg/server/sovereign/keylime/client.go`)
   - Stubbed implementation for Phase 1
   - Returns fixed hardcoded claims

2. **Policy Engine** (`spire/pkg/server/sovereign/policy.go`)
   - Evaluates attested claims
   - Configurable policies

3. **Server Integration** (`spire/pkg/server/api/svid/v1/service.go`)
   - Processes sovereign attestation
   - Calls Keylime and evaluates policy

4. **Agent Integration** (`spire/pkg/agent/endpoints/workload/`)
   - Handles sovereign attestation from workloads
   - Generates stubbed attestation when needed

## Next Steps

- **Phase 2**: Replace stubbed Keylime with full implementation
- **Phase 3**: Add TPM plugin and hardware integration
- **Phase 4**: Embed claims in SVID certificate extensions
- **Phase 5**: Add remediation actions

## Support

For issues or questions:
1. Check BUILD_INSTRUCTIONS.md for build issues
2. Check IMPLEMENTATION_SUMMARY.md for implementation details
3. Check COMPLETION_STATUS.md for current status
4. Review logs with "Unified-Identity - Phase 1:" prefix

---

**Version**: Phase 1  
**Status**: Complete and Ready for Testing  
**Feature Flag**: `Unified-Identity` (disabled by default)

