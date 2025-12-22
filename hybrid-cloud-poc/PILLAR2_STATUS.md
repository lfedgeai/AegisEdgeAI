# Pillar 2: Upstreaming Implementation - Status & Roadmap

## Overview

This document tracks the status of refactoring the "Unified Identity" PoC into upstream-ready components for SPIRE and Keylime. The current PoC is **functional on real hardware** but uses a "Fork & Patch" pattern that needs refactoring for upstream acceptance.

**Hardware Environment**: 10.1.0.11 (Real TPM 2.0)

## Feature Flag Strategy

**All Unified Identity features are gated by**: `unified_identity_enabled = true`

**Rationale**:
- ✅ **Atomic enablement**: Single flag for entire feature set
- ✅ **Easier upstream review**: One cohesive PoC, not scattered features
- ✅ **Simple rollback**: Disable everything with one config change
- ✅ **Clear scope**: "This PR adds Sovereign Identity support"

**Config** (`keylime-agent.conf`):
```toml
# Unified-Identity: Sovereign SVID support (grc.* claims)
# Enables: delegated certification, geolocation attestation, TPM App Keys
unified_identity_enabled = true
```

**All new endpoints/features MUST check this flag first.**

---

## Task 1: Delegated Certifier Endpoint (Keylime Agent)

### Status: ✅ FUNCTIONAL (Production-ready with config enhancements)

**Current Implementation**: `rust-keylime/keylime-agent/src/delegated_certification_handler.rs`

**Endpoint**: `POST /delegated_certification/certify_app_key`

### What It Does
Allows SPIRE TPM Plugin to request TPM AK signature for its App Key, creating a hardware-rooted certificate chain.

### Current Features
- ✅ Feature flag gating (`unified_identity_enabled`)
- ✅ Input validation (all required fields checked)
- ✅ Challenge-response (nonce validation)
- ✅ TPM2_Certify operation (signs App Key with AK)
- ✅ Error handling with proper HTTP codes
- ✅ Request logging

### Gaps for Upstream
| Feature | Status | Priority | Effort |
|---------|--------|----------|--------|
| IP Allowlist | ❌ Missing | High | 1 day |
| Rate Limiting | ❌ Missing | Medium | 1 day |
| mTLS Auth (optional) | ❌ Missing | Low | 2 days |
| Config file options | ⚠️ Partial | High | 1 day |

### Production Roadmap
1. **Add configuration options** (1 day)
   ```toml
   [delegated_certification]
   enabled = false
   allowed_callers = ["127.0.0.1"]
   rate_limit_per_minute = 10
   ```

2. **Add IP allowlist enforcement** (1 day)
   - Check `req.peer_addr()` against config
   - Return 403 if not in allowlist

3. **Add rate limiting** (1 day)
   - Per-IP rate limiter
   - Return 429 when exceeded

4. **Write RFC for rust-keylime** (2 days)
   - Security model
   - Use cases
   - API specification

### Verification
```bash
# Works in current PoC:
./ci_test_runner.py --no-color -- --no-pause
# Check: SPIRE Agent successfully attests with TPM App Key
```

---

## Task 2: Attested Geolocation API (Keylime Agent)

### Status: ⚠️ NEEDS REFACTORING (Currently breaks Keylime protocol)

**Current Implementation**: `rust-keylime/keylime-agent/src/quotes_handler.rs`

**Problem**: Modifies core `KeylimeQuote` struct to inject `geolocation` field

### What It Does
Detects mobile sensor (USB tethered phone with IMEI/IMSI) and includes location in TPM quote response.

### Current Implementation (Hack)
```rust
// Line ~200 in quotes_handler.rs
pub struct KeylimeQuote {
    pub quote: String,
    pub hash_alg: String,
    pub geolocation: Option<GeolocationData>,  // ← HACK: Breaks schema!
}
```


### Upstream Solution
Create **separate endpoint**: `GET /v2/agent/attested_geolocation`

**New Response (Mobile Sensor)**:
```json
{
  "sensor_type": "mobile",
  "mobile": {
    "sensor_id": "12d1:1433",
    "sensor_imei": "356345043865103",
    "sensor_imsi": "214070610960475"
  },
  "tpm_signature": "base64..."  // Mandatory - AK signature
}
```

**New Response (GNSS Sensor)**:
```json
{
  "sensor_type": "gnss",
  "gnss": {
    "sensor_id": "u-blox:NEO-M9N",
    "sensor_serial_number": "SN123456",
    "latitude": 51.5074,
    "longitude": -0.1278,
    "accuracy": 10,
    "sensor_signature": "base64..."  // Optional - GNSS sensor's own sig
  },
  "tpm_signature": "base64..."  // Mandatory - AK signature
}
```

**Design Principles**:
- **Nested by type**: `mobile{}` or `gnss{}` objects based on `sensor_type`
- **Type-specific fields**: Mobile has IMEI/IMSI, GNSS has coordinates
- **TPM binding**: `tpm_signature` mandatory for both (proves attestation)
- **Extensible**: Easy to add new sensor types without conflicts


### Production Roadmap
1. **Create new endpoint** (2 days)
   - Add `GET /v2/agent/attested_geolocation`
   - Return geolocation separate from quote
   - **PCR Binding**: Extend PCR 17 with geolocation hash before generating response

2. **Add feature flag check** (1 hour)
   ```rust
   if !data.unified_identity_enabled {
       return HttpResponse::Forbidden()...
   }
   ```

3. **Remove geolocation from KeylimeQuote** (1 day)
   - Restore original struct
   - Update SPIRE plugin to call both endpoints

4. **Update SPIRE Agent plugin** (2 days)
   - Call `/integrity/quote` (standard)
   - Call `/attested_geolocation` (new)
   - Combine results

### Verification
```bash
# Test new endpoint separately:
curl http://localhost:9002/v2/agent/attested_geolocation
# Should return location data
```

**Complexity**: Medium (requires coordinated changes in Agent + SPIRE)

---

## Task 3: Verification API & Cleanup (Keylime Verifier)

### Status: ⚠️ FUNCTIONAL with DEAD CODE (Needs cleanup)

**Current Implementation**: `keylime/cloud_verifier_tornado.py`

**Endpoint**: `POST /v2.4/verify/evidence`

### What It Does
- ✅ Verifies TPM Quote on-demand (for SPIRE)
- ❌ Contains unreachable mobile sensor validation code

### Current Issues
**Dead Code**: Lines ~850-920 in `cloud_verifier_tornado.py`
```python
def _verify_mobile_sensor_geolocation(self, geolocation):
    # This code is NEVER CALLED!
    # Validation moved to Envoy WASM filter
    ...
```

**Actual Flow**:
1. SPIRE calls `/verify/evidence` with TPM quote
2. Verifier checks TPM/PCRs ✅
3. Verifier returns raw geolocation to SPIRE ✅
4. **Envoy WASM filter** validates geolocation (not Keylime!)

### Production Roadmap
1. **Remove dead code** (1 day)
   - Delete `_verify_mobile_sensor_geolocation()`
   - Remove mobile sensor microservice calls
   - Keep only TPM verification

2. **Update API documentation** (1 day)
   - Document `/verify/evidence` as "Attestation as a Service"
   - Clarify it only verifies TPM, not geolocation

3. **Propose to Keylime upstream** (2 days)
   - RFC for stateless verification API
   - Use case: External workload identity systems

### Verification
```bash
# Current test passes but runs dead code:
./ci_test_runner.py --no-color
# After cleanup: Same test should pass, faster execution
```

**Complexity**: Low (just deletion + docs)

---

## Task 4: SPIRE Server Validator Plugin

### Status: ❌ NEEDS REFACTORING (Core files patched)

**Current Implementation**: Direct patches to `spire/pkg/server/endpoints/service.go`

**Problem**: Core SPIRE code modified instead of using plugin system

### Current Hack (Lines ~450-520 in service.go)
```go
// HACK: Hardcoded check for "SovereignAttestation"
if req.AttestationData.Type == "SovereignAttestation" {
    // Call Keylime Client directly
    result := s.keylimeClient.VerifyEvidence(...)
    // Return SPIFFE ID
}
```

### Upstream Solution
Create **separate plugin**: `spire-plugin-unified-identity` (Server-side Node Attestor)

**Plugin Structure**:
```
spire-plugin-unified-identity/
├── cmd/server/
│   └── main.go              # Plugin entrypoint
├── pkg/
│   ├── validator.go         # Implements NodeAttestor interface
│   ├── keylime_client.go    # Keylime API calls
│   └── config.go            # Plugin configuration
└── plugin.conf              # Sample config
```

### Production Roadmap
1. **Extract logic to plugin** (5 days)
   - Move Keylime client code
   - Move payload parsing
   - Implement `NodeAttestor` interface

2. **Remove core patches** (2 days)
   - Restore original `service.go`
   - Configure plugin in `server.conf`

3. **Test with real hardware** (2 days)
   - Verify attestation still works
   - Check performance impact

### Verification
```bash
# Before: Patches in core files
# After: Clean core + plugin loaded
./ci_test_runner.py --no-color
grep -r "SovereignAttestation" spire/pkg/server/endpoints/
# Should return NO results after refactoring
```

**Complexity**: High (requires SPIRE plugin expertise)

---

## Task 5: SPIRE Agent Collector Plugin

### Status: ❌ NEEDS REFACTORING (Core files heavily patched)

**Current Implementation**: Patches to `spire/pkg/agent/client/client.go` and `agent.go`

**Problem**: Core orchestration logic embedded in SPIRE Agent core

### Current Hack
Core files modified to:
1. Generate TPM App Key
2. Call Keylime `/certify_app_key`
3. Get TPM quote from Keylime
4. Package for server

### Upstream Solution
Create **separate plugin**: `spire-plugin-unified-identity` (Agent-side Node Attestor)

**Challenge**: The PoC uses App Key for **mTLS transport**.
- Standard Node Attestors only provide payload over standard TLS
- This "Device-Attested TLS" pattern may need **SPIRE RFC**

### Production Roadmap
1. **Evaluate mTLS requirement** (3 days)
   - Can we move to payload-only (standard)?
   - Or propose Device-Attested TLS as new pattern?

2. **Extract to plugin** (7 days)
   - Move orchestration logic
   - Implement `NodeAttestor` interface
   - Handle TPM interactions

3. **Restore core files** (2 days)
   - Revert `client.go` patches
   - Revert `agent.go` patches

4. **RFC for SPIRE** (optional, 3 days)
   - If keeping Device-Attested TLS pattern

### Verification
```bash
./ci_test_runner.py --no-color
# Agent should attest successfully via plugin
```

**Complexity**: High (complex orchestration + potential SPIRE RFC)

---

## Task 6: Credential Composer Configuration

### Status: ✅ EASIEST (Just needs config change)

**Current Implementation**: Patches to `spire/pkg/server/ca/ca.go`

**Problem**: Core CA code force-injects X.509 extensions

### Upstream Solution
Use **standard `CredentialComposer` plugin** (already exists in SPIRE!)

### Production Roadmap
1. **Create CredentialComposer config** (1 day)
   ```hcl
   CredentialComposer "unified-identity" {
       plugin_cmd = "./credential-composer"
       plugin_data {
           include_extensions = [
               "grc.geolocation.*",
               "grc.tpm-attestation.*"
           ]
       }
   }
   ```

2. **Remove CA patches** (1 day)
   - Restore original `ca.go`
   - Deploy with CredentialComposer config

### Verification
```bash
# Inspect SVID after config change:
./scripts/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem
# Should still show grc.geolocation.* extensions
```

**Complexity**: Low (standard SPIRE feature)

---

## Summary: Production Roadmap

### Phase 1: Quick Wins (5 days total)
- ✅ Task 1: Add config options to Delegated Certifier
- ✅ Task 3: Remove dead code from Verifier
- ✅ Task 6: Switch to CredentialComposer

### Phase 2: Moderate Refactoring (10 days)
- 🔨 Task 2: Create separate geolocation endpoint

### Phase 3: Major Refactoring (20 days)
- 🔨 Task 4: Extract Server Validator plugin
- 🔨 Task 5: Extract Agent Collector plugin

### Total Effort: ~6 weeks for full upstream readiness

---

## Verification Strategy

### Current System Test
```bash
# Full integration test on real hardware (10.1.0.11):
./ci_test_runner.py --no-color

# Expected output:
# ✓ TESTS PASSED
# Duration: ~2 minutes
# No errors in logs
```

### Per-Task Verification
Each task will have specific test commands documented above.

### Hardware Requirements
- Real TPM 2.0 (✅ Available on 10.1.0.11)
- Mobile sensor (optional, for geolocation testing)
- Network connectivity for distributed setup

---

## Next Steps

1. **Run verification test** to confirm current state works
2. **Document findings** in README-arch-sovereign-unified-identity.md
3. **Prioritize tasks** based on business needs
4. **Begin Phase 1** (quick wins) if approved


---

## Implementation Note: Feature Flag Consistency

**All Tasks (1-6) require unified_identity_enabled check**:

- **Task 1 (Keylime Agent)**: ✅ Already implemented
- **Task 2 (Keylime Agent)**: Added to roadmap  
- **Task 3 (Keylime Verifier)**: Verifier-level config check
- **Task 4 (SPIRE Server Plugin)**: Plugin should check before loading
- **Task 5 (SPIRE Agent Plugin)**: Plugin should check before loading
- **Task 6 (SPIRE CredentialComposer)**: Config-driven feature

This ensures atomic enablement/disablement of the entire Unified Identity feature set.

