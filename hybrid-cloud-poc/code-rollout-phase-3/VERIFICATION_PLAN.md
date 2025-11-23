# Unified-Identity Feature Flag Verification Plan

## Objective
Ensure all unified-identity changes are properly feature-flagged and that when disabled, the code behaves exactly like the original open source repositories.

## Components to Verify

### 1. SPIRE Server (https://github.com/spiffe/spire)
- **Location**: `code-rollout-phase-1/spire/`
- **Feature Flag**: `fflag.FlagUnifiedIdentity` (default: `true` - enabled)
- **Disable Syntax**: `feature_flags = ["-Unified-Identity"]` in config
- **Files to Check**:
  - `pkg/server/server.go` - Keylime client and policy engine initialization
  - `pkg/server/api/agent/v1/service.go` - SovereignAttestation processing
  - `pkg/server/api/svid/v1/service.go` - SovereignAttestation processing
  - `pkg/server/keylime/client.go` - NEW FILE (100% unified-identity)
  - `pkg/server/unifiedidentity/claims.go` - NEW FILE (100% unified-identity)
  - `pkg/server/policy/` - NEW DIRECTORY (100% unified-identity)

### 2. SPIRE Agent (https://github.com/spiffe/spire)
- **Location**: `code-rollout-phase-1/spire/`
- **Feature Flag**: `fflag.FlagUnifiedIdentity` (default: `true` - enabled)
- **Disable Syntax**: `feature_flags = ["-Unified-Identity"]` in config
- **Files to Check**:
  - `pkg/agent/client/client.go` - TPM plugin initialization, SovereignAttestation building
  - `pkg/agent/attestor/node/node.go` - SovereignAttestation building
  - `pkg/agent/tpmplugin/` - NEW DIRECTORY (100% unified-identity)

### 3. go-spiffe (https://github.com/spiffe/go-spiffe)
- **Location**: `code-rollout-phase-1/go-spiffe/`
- **Feature Flag**: N/A (proto files only, backward compatible)
- **Files to Check**:
  - `proto/spiffe/workload/workload.proto` - Added optional `sovereign_attestation` field

### 4. spire-api-sdk (https://github.com/spiffe/spire-api-sdk)
- **Location**: `code-rollout-phase-1/spire-api-sdk/`
- **Feature Flag**: N/A (proto files only, backward compatible)
- **Files to Check**:
  - `proto/spire/api/types/sovereignattestation.proto` - NEW FILE (100% unified-identity)
  - `proto/spire/api/server/agent/v1/agent.proto` - Added optional `sovereign_attestation` field
  - `proto/spire/api/server/svid/v1/svid.proto` - Added optional `sovereign_attestation` field

### 5. Keylime Verifier (https://github.com/keylime/keylime)
- **Location**: `code-rollout-phase-2/keylime/`
- **Feature Flag**: `unified_identity_enabled` (default: `true` - enabled)
- **Disable Syntax**: `unified_identity_enabled = false` in `[verifier]` section
- **Files to Check**:
  - `keylime/cloud_verifier_tornado.py` - `_tpm_app_key_verify()` method gated by feature flag
  - `keylime/app_key_verification.py` - NEW FILE (100% unified-identity)

### 6. rust-keylime Agent (https://github.com/keylime/rust-keylime)
- **Location**: `code-rollout-phase-2/rust-keylime/`
- **Feature Flag**: `unified_identity_enabled` (default: `true` - enabled)
- **Disable Syntax**: `unified_identity_enabled = false` in `[agent]` section
- **Files to Check**:
  - `keylime/src/config/base.rs` - Added `unified_identity_enabled` field
  - `keylime-agent/src/delegated_certification_handler.rs` - NEW FILE (100% unified-identity)
  - `keylime-agent/src/quotes_handler.rs` - Geolocation detection gated
  - `keylime-agent/src/api.rs` - Delegated certification endpoint registration gated

## Verification Steps

1. **For each component, verify**:
   - All new code is behind feature flag checks
   - No existing open source code paths are modified without feature flags
   - When feature flag is disabled, behavior matches original open source
   - Proto file changes are optional fields (backward compatible)

2. **Test backward compatibility**:
   - Disable feature flags in all components
   - Run existing tests to ensure they pass
   - Verify no unified-identity code paths are executed

3. **Test with feature enabled (default)**:
   - Ensure feature flags default to enabled
   - Run full integration test
   - Verify unified-identity functionality works

## Current Status

✅ SPIRE Server: Default changed to enabled, explicit disable support added
✅ SPIRE Agent: Default changed to enabled, explicit disable support added  
✅ Keylime Verifier: Default changed to enabled
✅ rust-keylime Agent: Default changed to enabled
✅ go-spiffe: Verified proto files are backward compatible
✅ spire-api-sdk: Verified proto files are backward compatible

## Next Steps

1. Verify all changes are properly gated by feature flags
2. Test backward compatibility by disabling all flags
3. Run full integration test with flags enabled (default)

