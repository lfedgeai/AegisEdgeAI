# Master Roadmap: Aegis Sovereign Unified Identity Upstreaming

This document serves as the **single source of truth** for refactoring the "Unified Identity" PoC into upstream-ready components for SPIRE and Keylime.

## Executive Summary
The "Unified Identity" feature introduces a hardware-rooted relationship between SPIRE and Keylime. Currently implemented as a **Fork & Patch** pattern, this roadmap tracks the transition to Feature Requests (Keylime) and Plugin-based extensions (SPIRE).

### Feature Flag Strategy
All Unified Identity features are gated by a single atomic flag in the agent configuration:
**Config** (`keylime-agent.conf`):
```toml
# Unified-Identity: Sovereign SVID support
# Enables: delegated certification, geolocation attestation, TPM App Keys
unified_identity_enabled = true
```
**All new endpoints and features MUST check this flag first.**

---

## Master Checklist

### Pillar 1: Test Infrastructure (Safety Net)
- [x] Create/Harden `test_integration.sh` (Fail-fast, structured logging)
- [x] Set up clean error reporting for CI/Watcher

### Pillar 2: Upstreaming Implementation (Refactoring)
- [x] **Task 1**: Keylime Agent - Delegated Certifier Endpoint
- [x] **Task 2**: Keylime Agent - Attested Geolocation API
- [x] **Task 2d**: Keylime Verifier - Geolocation Database & Integration
- [ ] **Task 3**: Keylime Verifier - Add Verification API & Cleanup
- [ ] **Task 4**: SPIRE Server - Validator Plugin with Geolocation Claims
- [ ] **Task 5**: SPIRE Agent - Collector Plugin (`spire-plugin-unified-identity`)
- [ ] **Task 6**: SPIRE Creds - Credential Composer

### Pillar 3: Production Readiness (Hardening)
- [ ] Address Keylime Client TLS (`InsecureSkipVerify`)
- [ ] Secure Secrets Management (CAMARA API Keys)
- [ ] Resolve AegisSovereignAI GitHub Issues

---

## Technical Task Deep-Dive

### Task 1: Delegated Certifier Endpoint (Keylime Agent)
**Status**: ✅ FUNCTIONAL 
**Implementation**: [delegated_certification_handler.rs](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/rust-keylime/keylime-agent/src/delegated_certification_handler.rs)

*   **Problem**: SPIRE Agent generates a "TPM App Key" and needs it signed by the TPM's Attestation Key (AK).
*   **Upstream Solution**: Formal `POST /delegated_certification/certify_app_key` endpoint.
*   **Hardening Roadmap**: 
    - [x] IP Allowlist enforcement.
    - [x] Rate limiting.
    - [ ] Configuration options in `keylime.conf`.

### Task 2: Attested Geolocation API (Keylime Agent)
**Status**: ✅ COMPLETE
**Implementation**: [geolocation_handler.rs](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/rust-keylime/keylime-agent/src/geolocation_handler.rs)

*   **Problem**: Injecting geolocation into core Keylime quotes breaks schema compatibility.
*   **Upstream Solution**: Separate `GET /v2/agent/attested_geolocation` endpoint.
*   **Security (Task 2c)**: Implemented Nonce-based freshness and PCR 15 binding to prevent TOCTOU attacks.

### Task 2d: Verifier Database Integration
**Status**: ✅ COMPLETE
**Implementation**: [verifier_db.py](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/keylime/keylime/db/verifier_db.py), [app_key_verification.py](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/keylime/keylime/app_key_verification.py), [cloud_verifier_common.py](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/keylime/keylime/cloud_verifier_common.py)

*   **Problem**: Geolocation data was being fetched but not persisted to the database for audit and validation.
*   **Solution**: Added `geolocation` column to verifier database schema, implemented PCR 15 extraction from quotes, and integrated geolocation persistence into the verification workflow.
*   **Integration Test**: Verified PCR 15 is correctly included in TPM quotes, extracted by the verifier, and persisted to the database.

### Task 3: Add Verification API & Cleanup (Keylime Verifier)
**Status**: ⚠️ FUNCTIONAL with DEAD CODE
**Implementation**: `keylime/cloud_verifier_tornado.py`

*   **Goal**: Enable "Attestation as a Service" for SPIRE and strip legacy mobile sensor logic.
*   **Roadmap**: Propose generic `/verify/evidence` endpoint to Keylime upstream.

### Task 4: SPIRE Server Validator Plugin (with Geolocation)
**Status**: ❌ NEEDS REFACTORING
**Implementation (Current Hack)**: [service.go](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/spire/pkg/server/api/agent/v1/service.go) and [claims.go](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/spire/pkg/server/unifiedidentity/claims.go)

*   **Goal**: Move core patches into a custom `NodeAttestor` plugin.
*   **Scope**: Extract Keylime client calls, payload parsing, and geolocation claim mapping logic into the plugin.

### Task 5: SPIRE Agent Collector Plugin
**Status**: ❌ NEEDS REFACTORING
*   **Implementation (Current Hack)**: Patches to `agent.go` and `client.go` in SPIRE Agent core.
*   **Goal**: Move the complex orchestration (TPM Key -> Keylime sign -> Quote -> Server) into an Agent Node Attestor plugin.

### Task 6: Credential Composer (SPIRE)
**Status**: ✅ EASIEST
*   **Goal**: Replace core `ca.go` patches with standard SPIRE `CredentialComposer` plugin configuration to inject claims into X.509 SVIDs.

---

## Verification Strategy

### Full System Test
```bash
# Run integration test on real hardware (10.1.0.11)
./ci_test_runner.py --no-color
```

### Hardware Requirements
- Real TPM 2.0 (Available on node 10.1.0.11)
- Network connectivity for distributed SPIRE/Keylime setup.
