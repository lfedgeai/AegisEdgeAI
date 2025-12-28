# Master Roadmap: Aegis Sovereign Unified Identity Upstreaming

This document serves as the **single source of truth** for both the technical roadmap and the execution strategy for refactoring the "Unified Identity" PoC into upstream-ready components.

## Executive Summary
The "Unified Identity" feature introduces a hardware-rooted relationship between SPIRE and Keylime. We follow a **4-Pillar Strategy** to transition from a "Fork & Patch" pattern to official Feature Requests (Keylime), Plugin-based extensions (SPIRE), and Standalone Integration Components.

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
- [x] **Task 2e**: Keylime Verifier - MSISDN in Verifier DB Schema (Python) ([Status: Complete])
  - Add `/lookup_msisdn` endpoint to sidecar for MSISDN lookup
  - Call sidecar from Keylime verifier during attestation
- [x] **Task 2f**: SPIRE Server - MSISDN in SVID Claims (Go) ([Status: Complete])
  - Add `SensorMsisdn` field to Geolocation proto message
  - Add `grc.geolocation.sensor_msisdn` to attested claims
  - Extract from Keylime verification response
- [x] **Task 3**: Keylime Verifier - Verification API & Cleanup ([Status: Complete])
- [x] **Task 4**: SPIRE Server - Validator Plugin with Geolocation (Go) ([Status: Complete])
- [x] **Task 5**: SPIRE Agent - Collector Plugin (Go) ([Status: Complete])
- [x] **Task 6**: SPIRE Creds - Credential Composer (Go)

### Pillar 3: Upstreaming Ecosystem (Standalone Components)
*Goal: Release integration components as standalone, reusable open source projects.*

> [!NOTE]
> **Architecture Decision (December 2025)**: WASM + Sidecar is the confirmed pattern. WASM filter extracts claims from certificates (unavoidable for custom X.509 extensions), sidecar handles OAuth/caching/secrets.

> [!IMPORTANT]
> **Simplification**: With MSISDN and location data embedded in SVID claims (Task 2f), the sidecar implements a **DB-LESS flow** that bypasses database lookups. It remains a thin CAMARA API wrapper with intelligent caching.

- [x] **Task 7**: Envoy WASM Plugin - Policy-Based Verification Modes ([Status: Complete])
  - Implemented `verification_mode` config: `trust`, `runtime`, `strict`
  - Trust mode: No sidecar call (default, trust attestation-time verification)
  - Runtime mode: Sidecar call with caching (15min TTL)
  - Strict mode: Sidecar call with `skip_cache=true` (real-time)
- [x] **Task 8**: Envoy WASM Plugin - MSISDN Extraction from SVID ([Status: Complete])
  - Extract `sensor_msisdn` from Unified Identity extension JSON
  - Pass MSISDN to sidecar (no DB lookup needed)
- [ ] **Task 9**: Envoy WASM Plugin - Standalone Repo Setup (includes sidecar) [RELEVANT: For open-source upstreaming]
- [ ] **Task 10**: Envoy WASM Plugin - Publish Signed WASM + Sidecar Image [RELEVANT: For production distribution]
- [x] **Task 11**: Mobile Sensor Sidecar - Pure Mobile & DB-less Flow ([Status: Complete])
  - Refined to "Pure Mobile" (GNSS handled by WASM, sidecar rejects non-mobile).
  - Implements **DB-LESS flow**: Prioritizes `msisdn`, `latitude`, `longitude`, `accuracy` from SVID.
  - Falls back to DB-BASED lookup ONLY if SVID data is missing.
  - Added support for `sensor_imei`, `sensor_imsi`, and `sensor_serial` in mapping.
- [ ] **Task 12**: Mobile Sensor Sidecar - Pluggable Backends [RELEVANT: For multi-telco support]
- [/] **Task 12b**: Sensor Schema Separation (Mobile vs GNSS) ([Status: Partial])
  - **Mobile Sensor Schema**: `{sensor_id, sensor_imei, sensor_imsi, sensor_msisdn, latitude, longitude, accuracy}`
  - **GNSS Sensor Schema**: `{sensor_id, sensor_serial_number, latitude, longitude, sensor_signature (optional)}`
  - **Status Update**: Sidecar and WASM filter logic updated. Keylime/SPIRE pipeline transition to new namespaces pending.

### Pillar 4: Production Readiness (Hardening)
*Goal: Transform the PoC into a secure, production-grade solution.*
- [x] **Task 13**: TLS Verification - Remove `InsecureSkipVerify` across all components ([Status: Complete])
- [x] **Task 14**: Secrets Management - Move CAMARA API keys to secure providers ([Status: Complete])
- [ ] **Task 14b**: Delegated Certification Fix (Pre-Open-Source Blocker)
  - **Issue**: `Failed to request certificate: Empty response` from rust-keylime during TPM2_Certify
  - **Impact**: `TpmAttestation len=0, AppKeyCert len=0` in SPIRE Server logs (attestation succeeds but without real TPM evidence)
  - Debug rust-keylime `/v2.2/delegated_certification/certify_app_key` endpoint
  - Fix empty response in `delegated_certification.py` → rust-keylime flow
  - Verify App Key certificate is properly signed by AK
- [ ] **Task 15**: Quality Assurance - Linting, pre-commit hooks, and issue resolution

---

## 2. Technical Strategy & Deep-Dive

### Pillar 1 Strategy: Fail-Fast Infrastructure
*   **Structured Logging**: All logs (SPIRE, Keylime, Envoy) are aggregated into `/tmp/unified_identity_test_*` for centralized analysis.
*   **State Sanitization**: `test_integration.sh --cleanup-only` performs "Nuke Mode" cleanup (clears TPM state, wipes DBs) to prevent flaky test results.

### Pillar 2 Deep-Dive: Modular Implementation
*(See Task details in Master Checklist above)*

### Pillar 3 Deep-Dive: Upstreaming Ecosystem

#### Component 1: Envoy WASM Plugin (`envoy-wasm-camara-auth`)
*Goal: Create a reusable Envoy filter for policy-based CAMARA location verification.*

**Technical Approach**:
*   **Repo**: Standalone `envoy-wasm-camara-auth`.
*   **Language**: Rust (via Proxy-Wasm SDK) for safety and toolchain.
*   **Functionality**: Extracts claims (including MSISDN) from SPIRE SVIDs, applies policy-based verification, injects auth headers.
*   **Policy Modes**: Trust (default, no CAMARA), Runtime (cached CAMARA), Strict (real-time CAMARA).
*   **Distribution**: Signed `.wasm` binaries (GitHub Releases / OCI).

#### Component 2: Mobile Sensor Sidecar (`mobile-gps-verifier`)
*Goal: Create a thin CAMARA API wrapper for location verification.*

**Technical Approach**:
*   **Repo**: Standalone `mobile-gps-verifier`.
*   **Language**: Python (FastAPI) or Go.
*   **Simplification**: No database lookup (MSISDN comes from SVID claims via WASM filter).
*   **Caching**: Token caching (OAuth), response caching (configurable TTL).
*   **Architecture**: Adapter pattern for Telco APIs vs Mock backends.

---

## 3. Risk Mitigation & Quality (Pillar 4)
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

