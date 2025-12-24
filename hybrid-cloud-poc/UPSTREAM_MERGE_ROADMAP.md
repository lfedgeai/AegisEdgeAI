# Master Roadmap: Aegis Sovereign Unified Identity Upstreaming

This document serves as the **single source of truth** for both the technical roadmap and the execution strategy for refactoring the "Unified Identity" PoC into upstream-ready components.

## Executive Summary
The "Unified Identity" feature introduces a hardware-rooted relationship between SPIRE and Keylime. We follow a **3-Pillar Strategy** to transition from a "Fork & Patch" pattern to official Feature Requests (Keylime) and Plugin-based extensions (SPIRE).

---

## 1. Master Checklist & Status

### Pillar 1: Test Infrastructure (Safety Net)
*Goal: Establish a reliable, fail-fast environment to catch regressions.*
- [x] **Task 0**: Harden `test_integration.sh` (Fail-fast, structured logging)
- [x] **Task 0b**: CI Runner (`ci_test_runner.py`) for real-time monitoring

### Pillar 2: Upstreaming Implementation (Refactoring)
*Goal: Execute architectural changes through modular plugins and protocol extensions.*
- [x] **Task 1**: Keylime Agent - Delegated Certifier Endpoint (Rust)
- [x] **Task 2**: Keylime Agent - Attested Geolocation API (Rust)
- [x] **Task 2d**: Keylime Verifier - Geolocation Database & Integration (Python)
- [x] **Task 3: Keylime Verifier - Verification API & Cleanup** ([Status: Complete])
- [x] **Task 4**: SPIRE Server - Validator Plugin with Geolocation (Go) ([Status: Complete])
- [x] **Task 5**: SPIRE Agent - Collector Plugin (Go) ([Status: Complete])
- [x] **Task 6**: SPIRE Creds - Credential Composer (Go)

### Pillar 3: Production Readiness (Hardening)
*Goal: Transform the PoC into a secure, production-grade solution.*
- [x] **Task 7**: TLS Verification - Remove `InsecureSkipVerify` across all components ([Status: Complete] - Enhanced certificate generation with SANs for multi-machine support)
- [ ] **Task 8**: Secrets Management - Move CAMARA API keys to secure providers
- [ ] **Task 9**: Quality Assurance - Linting, pre-commit hooks, and issue resolution

---

## 2. Technical Strategy & Deep-Dive

### Pillar 1 Strategy: Fail-Fast Infrastructure
*   **Structured Logging**: All logs (SPIRE, Keylime, Envoy) are aggregated into `/tmp/unified_identity_test_*` for centralized analysis.
*   **State Sanitization**: `test_integration.sh --cleanup-only` performs "Nuke Mode" cleanup (clears TPM state, wipes DBs) to prevent flaky test results.

### Pillar 2 Deep-Dive: Modular Implementation

#### Task 1: Delegated Certifier Endpoint (Keylime Agent)
**Status**: ✅ FUNCTIONAL | **Implementation**: [delegated_certification_handler.rs](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/rust-keylime/keylime-agent/src/delegated_certification_handler.rs)
*   **Solution**: Formal `POST /delegated_certification/certify_app_key` endpoint to sign SPIRE "TPM App Keys".

#### Task 2: Attested Geolocation API (Keylime Agent)
**Status**: ✅ COMPLETE | **Implementation**: [geolocation_handler.rs](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/rust-keylime/keylime-agent/src/geolocation_handler.rs)
*   **Solution**: Separate `GET /v2/agent/attested_geolocation` endpoint with Nonce-based freshness and PCR 15 binding.

#### Task 2d: Verifier Database Integration
**Status**: ✅ COMPLETE | **Implementation**: [verifier_db.py](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/keylime/keylime/db/verifier_db.py)
*   **Solution**: Added `geolocation` persistence to verifier DB.

#### Task 3: Verification API & Cleanup (Keylime Verifier)
**Status**: ⚠️ FUNCTIONAL (In Progress)
*   **Goal**: Propose generic `/verify/evidence` endpoint to Keylime upstream and strip legacy mobile sensor code.

#### Task 4: SPIRE Server Validator Plugin
**Status**: ✅ COMPLETE | **Implementation**: [plugin.go](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/spire/pkg/server/plugin/credentialcomposer/unifiedidentity/plugin.go)
*   **Goal**: Move core patches into a standalone plugin package: `spire-plugin-unified-identity`.

#### Task 5: SPIRE Agent Collector Plugin
**Status**: ✅ COMPLETE | **Implementation**: [plugin.go](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/spire/pkg/agent/plugin/collector/sovereign/plugin.go)
*   **Result**: Implemented `sovereign` Collector plugin to gather TPM quotes and certificates. Refactored Agent Client to use the plugin interface.

#### Task 6: Credential Composer (SPIRE)
**Status**: ✅ COMPLETE | **Implementation**: [plugin.go](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/spire/pkg/server/plugin/credentialcomposer/unifiedidentity/plugin.go)
*   **Result**: Replaced core SVID patches with a standard `CredentialComposer`. Claims are propagated via Go context.

---

## 3. Risk Mitigation & Quality
*   **Security First**: TLS hardening (Task 7) is critical before any production use.
*   **Version Pinning**: We build against explicitly pinned versions of upstream SPIRE and Keylime to avoid breaking changes during refactoring.
*   **TPM Nuances**: Tests prioritize real hardware (10.1.0.11) while deferring pure containerization until logic is stable.

---

## 4. Verification Strategy

### Full System Test
```bash
# Run integration test on real hardware (10.1.0.11)
./ci_test_runner.py --no-color
```

### Hardware Requirements
- Real TPM 2.0 (Available on node 10.1.0.11)
- Network connectivity for distributed SPIRE/Keylime setup.
