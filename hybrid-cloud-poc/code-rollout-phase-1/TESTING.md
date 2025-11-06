# Testing Guide - Phase 1

## Unified-Identity - Phase 1: SPIRE API & Policy Staging (Stubbed Keylime)

This document provides comprehensive testing instructions for Phase 1, covering both unit tests and integration tests with rebuilt and existing SPIRE binaries.

## Unit Tests

### Running Unit Tests

**All unit tests:**
```bash
cd spire
go test ./pkg/server/keylime/... ./pkg/server/policy/... ./pkg/server/api/svid/v1/... -v
```

**Component-specific tests:**
```bash
# Keylime client
go test ./pkg/server/keylime/... -v

# Policy engine
go test ./pkg/server/policy/... -v

# SVID service (includes feature flag tests)
go test ./pkg/server/api/svid/v1/... -v

# Feature flag
go test ./pkg/common/fflag/... -v
```

### Feature Flag Tests

**Test with feature flag disabled (default):**
```bash
cd spire
go test ./pkg/server/api/svid/v1/... -v -run "FeatureFlag.*Disabled"
```

**Test with feature flag enabled:**
```bash
cd spire
go test ./pkg/server/api/svid/v1/... -v -run "SovereignAttestation|PolicyFailure"
```

**Test feature flag toggle:**
```bash
cd spire
go test ./pkg/server/api/svid/v1/... -v -run "FeatureFlagToggle"
```

### Test Scenarios

1. **`TestFeatureFlagDisabled`** - Verifies feature flag is disabled by default
2. **`TestFeatureFlagDisabledWithSovereignAttestation`** - SovereignAttestation ignored when flag disabled
3. **`TestFeatureFlagDisabledWithoutKeylimeClient`** - Service works without Keylime client when disabled
4. **`TestSovereignAttestationIntegration`** - Full flow when feature flag enabled
5. **`TestPolicyFailure`** - Policy evaluation failure handling
6. **`TestFeatureFlagToggle`** - Feature flag can be toggled on/off

### Test Coverage

```bash
cd spire
go test ./pkg/server/keylime/... -cover
go test ./pkg/server/policy/... -cover
go test ./pkg/server/api/svid/v1/... -cover
```

**Coverage Goals:**
- Keylime Client: >80%
- Policy Engine: >90%
- SVID Service Integration: >70%
- Feature Flag Logic: 100% (enabled and disabled states)

## Integration Tests

### Prerequisites

1. **Keylime Stub** must be running
2. **SPIRE Server** (either rebuilt with changes or existing binary)
3. **SPIRE Agent** (either rebuilt with changes or existing binary)
4. **Protobuf files regenerated** (if using rebuilt binaries)

### Test Case 1: Using Rebuilt SPIRE Server/Agent

This scenario tests the full implementation with all Phase 1 changes.

#### Step 1: Regenerate Protobuf Files

```bash
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1
./regenerate-protos.sh
```

#### Step 2: Build SPIRE with Feature Flag Support

```bash
cd spire
make build
```

This produces:
- `bin/spire-server` - SPIRE Server with Phase 1 changes
- `bin/spire-agent` - SPIRE Agent with Phase 1 changes

#### Step 3: Start Keylime Stub

```bash
cd keylime-stub
go run main.go
# Or with custom config:
KEYLIME_STUB_PORT=8888 KEYLIME_STUB_GEOLOCATION="Spain:Madrid" go run main.go
```

Verify stub is running:
```bash
curl http://localhost:8888/health
# Should return: {"status":"healthy","mode":"stub"}
```

#### Step 4: Configure SPIRE Server

Create `spire-server.conf`:
```hcl
server {
    bind_address = "0.0.0.0"
    bind_port = 8081
    trust_domain = "example.org"
    log_level = "DEBUG"
    
    # Enable Unified-Identity feature flag
    feature_flags = ["Unified-Identity"]
    
    # Keylime configuration (when feature flag enabled)
    # Note: These would be parsed by SPIRE Server configuration
    # For Phase 1, these are placeholders - actual config parsing
    # would need to be implemented
    
    data_dir = "/tmp/spire-server"
    
    plugins {
        DataStore "sql" {
            plugin_data {
                database_type = "sqlite3"
                connection_string = "/tmp/spire-server/datastore.sqlite3"
            }
        }
    }
}
```

#### Step 5: Start SPIRE Server

```bash
./bin/spire-server run -config spire-server.conf
```

Verify logs show:
```
INFO Unified-Identity - Phase 1: Feature flag Unified-Identity enabled
```

#### Step 6: Configure SPIRE Agent

Create `spire-agent.conf`:
```hcl
agent {
    data_dir = "/tmp/spire-agent"
    log_level = "DEBUG"
    
    # Enable Unified-Identity feature flag
    feature_flags = ["Unified-Identity"]
    
    trust_domain = "example.org"
    server_address = "localhost"
    server_port = 8081
}
```

#### Step 7: Start SPIRE Agent

```bash
./bin/spire-agent run -config spire-agent.conf
```

#### Step 8: Test Integration

1. **Create Registration Entry:**
```bash
./bin/spire-server entry create \
    -spiffeID spiffe://example.org/workload/test \
    -parentID spiffe://example.org/agent \
    -selector unix:uid:1000
```

2. **Request SVID with SovereignAttestation** (using SPIRE API):
```bash
# Use spire-server API or agent to request SVID
# The SovereignAttestation would be included in BatchNewX509SVID request
```

3. **Verify Logs:**
   - SPIRE Server logs should show: "Unified-Identity - Phase 1: Processing SovereignAttestation"
   - Keylime stub logs should show: "Unified-Identity - Phase 1: Received verify evidence request"
   - Policy evaluation logs should appear

4. **Verify Response:**
   - SVID should be issued successfully
   - Response should include `attested_claims` field

### Test Case 2: Using Existing SPIRE Server/Agent

This scenario tests backward compatibility - existing SPIRE binaries should work without Phase 1 changes.

#### Prerequisites

- Use existing SPIRE binaries (without Phase 1 changes)
- Feature flag is **disabled by default**

#### Step 1: Start Existing SPIRE Server

```bash
# Use existing spire-server binary
spire-server run -config spire-server.conf
# Note: No feature_flags = ["Unified-Identity"] in config
```

#### Step 2: Start Existing SPIRE Agent

```bash
# Use existing spire-agent binary
spire-agent run -config spire-agent.conf
# Note: No feature_flags = ["Unified-Identity"] in config
```

#### Step 3: Test Backward Compatibility

1. **Create Registration Entry:**
```bash
spire-server entry create \
    -spiffeID spiffe://example.org/workload/test \
    -parentID spiffe://example.org/agent \
    -selector unix:uid:1000
```

2. **Request SVID (normal flow):**
   - Request should succeed without SovereignAttestation
   - No Keylime calls should be made
   - No errors should occur

3. **Verify Logs:**
   - No "Unified-Identity - Phase 1" logs should appear
   - Normal SPIRE operation logs only

#### Step 4: Test with SovereignAttestation (Ignored)

If a request includes `SovereignAttestation` field:
- Request should still succeed (normal SVID flow)
- `SovereignAttestation` field is ignored (feature flag disabled)
- No Keylime calls are made
- No policy evaluation occurs

### Test Case 3: Feature Flag Toggle

Test enabling/disabling feature flag without rebuilding.

#### With Feature Flag Disabled

1. Configure SPIRE Server/Agent **without** `feature_flags = ["Unified-Identity"]`
2. Rebuild SPIRE (to include Phase 1 code)
3. Start SPIRE Server/Agent
4. Verify: SovereignAttestation is ignored, no Keylime calls

#### With Feature Flag Enabled

1. Configure SPIRE Server/Agent **with** `feature_flags = ["Unified-Identity"]`
2. Restart SPIRE Server/Agent (same binaries)
3. Verify: SovereignAttestation is processed, Keylime calls made

## Workload Attestor Tests

### Test Both Workload Attestors

The SPIRE Agent is configured with both `unix` and `k8s` workload attestors. Test both:

```bash
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/k8s-integration
./test-workload-attestors.sh
```

This test:
1. Verifies SPIRE Server and Agent are running
2. Tests `unix` workload attestor:
   - Creates registration entry with `unix:uid` selector
   - Verifies entry is created correctly
3. Tests `k8s` workload attestor (if Kubernetes cluster exists):
   - Creates registration entry with `k8s:ns` and `k8s:sa` selectors
   - Verifies entry is created correctly
4. Checks agent logs for both attestors
5. Provides cleanup commands

**Manual Testing:**

**Unix Workload Attestor:**
```bash
# Create entry
spire-server entry create \
    -spiffeID spiffe://example.org/workload/test-unix \
    -parentID spiffe://example.org/spire/agent/... \
    -selector unix:uid:$(id -u)

# Verify entry
spire-server entry show -id <entry-id>
```

**K8s Workload Attestor:**
```bash
# Create entry
spire-server entry create \
    -spiffeID spiffe://example.org/workload/test-k8s \
    -parentID spiffe://example.org/spire/agent/... \
    -selector k8s:ns:default \
    -selector k8s:sa:test-workload

# Verify entry
spire-server entry show -id <entry-id>
```

## Integration Test Checklist

### Rebuilt SPIRE (Phase 1 Changes)

- [ ] Protobuf files regenerated successfully
- [ ] SPIRE Server builds without errors
- [ ] SPIRE Agent builds without errors
- [ ] Keylime stub starts and responds
- [ ] SPIRE Server starts with feature flag enabled
- [ ] SPIRE Agent starts with feature flag enabled
- [ ] Registration entries can be created
- [ ] SVID requests with SovereignAttestation work
- [ ] Keylime stub receives requests
- [ ] Policy evaluation works correctly
- [ ] AttestedClaims returned in response
- [ ] Logs include "Unified-Identity - Phase 1" tags
- [ ] Unix workload attestor works (test with `unix:uid` selector)
- [ ] K8s workload attestor works (test with `k8s:ns` and `k8s:sa` selectors)
- [ ] Both workload attestors can be used simultaneously

### Existing SPIRE (Backward Compatibility)

- [ ] Existing SPIRE Server starts normally
- [ ] Existing SPIRE Agent starts normally
- [ ] Normal SVID requests work (without SovereignAttestation)
- [ ] Requests with SovereignAttestation field are ignored (no errors)
- [ ] No Keylime calls are made
- [ ] No "Unified-Identity - Phase 1" logs appear
- [ ] Backward compatibility maintained

### Feature Flag Behavior

- [ ] Feature flag disabled by default (no config needed)
- [ ] Feature flag can be enabled via config
- [ ] Feature flag can be disabled via config (remove from array)
- [ ] Feature flag state persists across restarts
- [ ] Toggling feature flag works without rebuild

## Debugging Tests

### Enable Verbose Logging

```bash
cd spire
go test ./pkg/server/api/svid/v1/... -v -args -test.v
```

### Run Single Test

```bash
cd spire
go test ./pkg/server/api/svid/v1/... -v -run TestFeatureFlagDisabled$
```

### Run Tests with Race Detection

```bash
cd spire
go test ./pkg/server/api/svid/v1/... -race
```

### View Test Coverage

```bash
cd spire
go test ./pkg/server/api/svid/v1/... -coverprofile=coverage.out
go tool cover -html=coverage.out
```

### Check Logs for Unified-Identity Tag

```bash
# In SPIRE Server/Agent logs
grep "Unified-Identity - Phase 1" /var/log/spire-server.log

# In Keylime stub logs
grep "Unified-Identity - Phase 1" keylime-stub.log
```

## Common Issues

### Issue: "feature flags have not been loaded"
**Solution**: Ensure tests call `fflag.Load()` or `fflag.Unload()`:
```go
defer fflag.Unload() // Always clean up
```

### Issue: Protobuf generation fails
**Solution**: Check that `protoc` is installed and Makefiles are correct:
```bash
which protoc
cd spire-api-sdk && make generate
```

### Issue: Type conversion errors after protobuf generation
**Solution**: Verify field names match generated code:
- Check `sovereignattestation.pb.go` for exact field names
- Update code to use correct field names (e.g., `TpmSignedAttestation` vs `tpm_signed_attestation`)

### Issue: Keylime stub not receiving requests
**Solution**: 
- Verify stub is running: `curl http://localhost:8888/health`
- Check SPIRE Server config points to correct Keylime URL
- Verify mTLS certificates are configured correctly
- Check SPIRE Server logs for connection errors

### Issue: Feature flag not working
**Solution**:
- Verify feature flag is in config: `grep "Unified-Identity" spire-server.conf`
- Rebuild SPIRE after enabling feature flag
- Check logs for "Feature flag Unified-Identity enabled" message

## Test Data

### Stubbed SovereignAttestation
```go
sovereignAttestation := &types.SovereignAttestation{
    TpmSignedAttestation: "dGVzdC1xdW90ZQ==", // base64("test-quote")
    AppKeyPublic:         "test-public-key",
    AppKeyCertificate:    []byte("test-cert"),
    ChallengeNonce:       "test-nonce-123",
    WorkloadCodeHash:     "test-hash",
}
```

### Stubbed AttestedClaims
```go
attestedClaims := &keylime.AttestedClaims{
    Geolocation:         "Spain: N40.4168, W3.7038",
    HostIntegrityStatus: "passed_all_checks",
    GPUMetricsHealth: struct {
        Status        string
        UtilizationPct float64
        MemoryMB      int64
    }{
        Status:        "healthy",
        UtilizationPct: 15.0,
        MemoryMB:      10240,
    },
}
```
