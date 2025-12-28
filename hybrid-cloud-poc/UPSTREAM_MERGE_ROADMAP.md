# Master Roadmap: Aegis Sovereign Unified Identity Upstreaming

<!-- Version: 2.0.0 | Last Updated: 2025-12-28 -->

This document serves as the **single source of truth** for both the technical roadmap and the execution strategy for refactoring the "Unified Identity" PoC into upstream-ready components.

## Executive Summary

The "Unified Identity" feature introduces a hardware-rooted relationship between SPIRE and Keylime. We follow a **6-Pillar Strategy** to transition from a "Fork & Patch" pattern to upstream-ready contributions:

### Upstreaming Targets

| Component | Target Project | Contribution Type |
|-----------|---------------|-------------------|
| SPIRE plugins | `spiffe/spire` | Plugin PRs |
| Keylime Agent extensions | `keylime/rust-keylime` | Feature PRs |
| Keylime Verifier extensions | `keylime/keylime` | Feature PRs |
| Envoy WASM Plugin | **Standalone (LF AI)** | New project |
| Mobile Sensor Microservice | **Standalone (LF AI)** | New project |

### Pillars

- **Pillar 0**: Open Source Governance (LICENSE, CONTRIBUTING, etc.)
- **Pillar 1**: Test Infrastructure (Safety Net)
- **Pillar 2**: Upstreaming Implementation (SPIRE + Keylime PRs)
- **Pillar 3**: Upstreaming Ecosystem (Standalone Components)
- **Pillar 4**: Production Readiness (Hardening)
- **Pillar 5**: Documentation Completeness (Cross-references, Consistency)

### Priority Levels
| Priority | Meaning | Timeline |
|----------|---------|----------|
| **P0** | Blocker - Must fix before public release | Week 1 |
| **P1** | Critical - Required for production readiness | Week 2-3 |
| **P2** | Important - Should complete for 1.0 release | Week 4-6 |
| **P3** | Nice-to-have - Can defer to future releases | Post-1.0 |

### Quick Status Dashboard

| Pillar | Complete | In Progress | Blocked | Not Started |
|--------|----------|-------------|---------|-------------|
| Pillar 0 | 6 | 0 | 0 | 1 |
| Pillar 1 | 2 | 0 | 0 | 3 |
| Pillar 2 | 10 | 1 | 0 | 0 |
| Pillar 3 | 5 | 0 | 0 | 3 |
| Pillar 4 | 2 | 0 | 1 | 4 |
| Pillar 5 | 0 | 0 | 0 | 9 |
| **Total** | **25** | **1** | **1** | **20** |

---

## Pillar 0: Open Source Governance (Pre-Release Blockers)

*Goal: Establish required governance files for open source release.*

> [!IMPORTANT]
> **All Pillar 0 tasks are P0 blockers.** The repository CANNOT be made public without these files.

| Task | Description | Priority | Status | Owner | Target |
|------|-------------|----------|--------|-------|--------|
| **Task G1** | Add top-level `LICENSE` file (Apache 2.0 recommended) | P0 | `[x]` | — | Done |
| **Task G1b** | Automate Source File License Header checks | P2 | `[ ]` | TBD | Week 3 |
| **Task G2** | Add `CONTRIBUTING.md` with DCO/CLA requirements | P0 | `[x]` | — | Done |
| **Task G3** | Add `SECURITY.md` with vulnerability reporting process | P0 | `[x]` | — | Done |
| **Task G4** | Add `CODE_OF_CONDUCT.md` (LF standard recommended) | P0 | `[x]` | — | Done |
| **Task G5** | Add `.github/ISSUE_TEMPLATE/` (bug, feature, security) | P0 | `[x]` | — | Done |
| **Task G6** | Add `.github/PULL_REQUEST_TEMPLATE.md` | P0 | `[x]` | — | Done |

### Task G1: LICENSE File
```
Location: /LICENSE
Content: Apache License 2.0 (recommended for LF AI compatibility)
Dependencies: Legal review if required
```

### Task G2: CONTRIBUTING.md
```
Location: /CONTRIBUTING.md
Content:
- Development setup instructions
- Code style guidelines (Go, Rust, Python)
- DCO sign-off requirements
- PR process and review expectations
- Testing requirements before merge
Dependencies: None
```

### Task G3: SECURITY.md
```
Location: /SECURITY.md
Content:
- Supported versions table
- Vulnerability reporting process (private disclosure)
- Security contact email
- PGP key for encrypted reports (optional)
Dependencies: Security team contact setup
```

### Task G4: CODE_OF_CONDUCT.md
```
Location: /CODE_OF_CONDUCT.md
Content: Linux Foundation Code of Conduct (standard)
Dependencies: None
```

### Tasks G5-G6: GitHub Templates
```
Location: /.github/
Files:
- ISSUE_TEMPLATE/bug_report.md
- ISSUE_TEMPLATE/feature_request.md
- ISSUE_TEMPLATE/security_vulnerability.md
- PULL_REQUEST_TEMPLATE.md
Dependencies: None
```

### Task G1b: License Header Automation (NEW)
```
Goal: Ensure all source files contain the Apache 2.0 header.
Actions:
1. Create a script to audit all .go, .rs, .py, and .sh files.
2. Integrate into CI/CD as a blocking gate.
3. Integrate into pre-commit hooks.
Dependencies: Task G1
Effort: 0.5 days
```

---

## Pillar 1: Test Infrastructure (Safety Net)

*Goal: Establish a reliable, fail-fast environment to catch regressions.*

| Task | Description | Priority | Status | Owner | Target |
|------|-------------|----------|--------|-------|--------|
| **Task 0** | Harden `test_integration.sh` (Fail-fast, structured logging) | P1 | `[x]` | — | Done |
| **Task 0b** | CI Runner (`ci_test_runner.py`) for real-time monitoring | P1 | `[x]` | — | Done |
| **Task 0c** | Add GitHub Actions CI/CD pipeline | P1 | `[ ]` | TBD | Week 2 |
| **Task 0d** | Add pre-commit hooks configuration | P2 | `[ ]` | TBD | Week 3 |
| **Task 0e** | Implement Software TPM (`swtpm`) for dev/test | P2 | `[ ]` | TBD | Week 3 |

### Task 0c: GitHub Actions CI/CD (NEW)
```yaml
Location: /.github/workflows/
Files:
- ci.yml (lint, unit tests, integration tests)
- release.yml (tagged releases, artifact signing)
- security-scan.yml (dependency scanning, SAST)
Dependencies: Tasks G1-G6 complete
Effort: 2-3 days
```

### Task 0e: Software TPM Support (NEW)
```
Goal: Enable development and testing on systems without physical TPM hardware.
Actions:
1. Integrate `swtpm` or `ibmtpm` into `scripts/setup_tpm_plugin.sh`.
2. Update `test_integration.sh` to auto-detect and use soft-TPM if no hardware is present.
3. Update README for non-hardware developer onboarding.
Dependencies: None
Effort: 2 days
```

---

## Pillar 2: Upstreaming Implementation (Refactoring)

*Goal: Execute architectural changes through modular plugins and protocol extensions.*

| Task | Description | Priority | Status | Owner | Target |
|------|-------------|----------|--------|-------|--------|
| **Task 1** | Keylime Agent - Delegated Certifier Endpoint (Rust) | P1 | `[x]` | — | Done |
| **Task 2** | Keylime Agent - Attested Geolocation API (Rust) | P1 | `[x]` | — | Done |
| **Task 2d** | Keylime Verifier - Geolocation Database & Integration | P1 | `[x]` | — | Done |
| **Task 2e** | Keylime Verifier - MSISDN in Verifier DB Schema | P1 | `[x]` | — | Done |
| **Task 2f** | SPIRE Server - MSISDN in SVID Claims (Go) | P1 | `[x]` | — | Done |
| **Task 3** | Keylime Verifier - Verification API & Cleanup | P1 | `[x]` | — | Done |
| **Task 4** | SPIRE Server - Validator Plugin with Geolocation | P1 | `[x]` | — | Done |
| **Task 5** | SPIRE Agent - Collector Plugin (Go) | P1 | `[x]` | — | Done |
| **Task 6** | SPIRE Creds - Credential Composer (Go) | P1 | `[x]` | — | Done |
| **Task 12b** | Sensor Schema Separation (Mobile vs GNSS) | P1 | `[/]` | TBD | Week 2 |

### Task 12b Details (Partial)
```
Status: Sidecar and WASM filter logic updated.
Remaining:
- [ ] Keylime pipeline transition to new namespaces
- [ ] SPIRE pipeline transition to new namespaces
- [ ] Update test fixtures for new schemas
Effort: 2-3 days
```

**Mobile Sensor Schema:**
```json
{
  "sensor_id": "string",
  "sensor_type": "mobile",
  "sensor_imei": "string",
  "sensor_imsi": "string", 
  "sensor_msisdn": "string",
  "latitude": "float",
  "longitude": "float",
  "accuracy": "float"
}
```

**GNSS Sensor Schema:**
```json
{
  "sensor_id": "string",
  "sensor_type": "gnss",
  "sensor_serial_number": "string",
  "latitude": "float",
  "longitude": "float",
  "sensor_signature": "string (optional)"
}
```

---

## Pillar 3: Upstreaming Ecosystem (Standalone Components)

*Goal: Package components that cannot be upstreamed to existing projects as standalone, distributable open source projects.*

> [!IMPORTANT]
> **Upstreaming Strategy**: Not all components go to the same place. This pillar covers components
> that will be released as **standalone projects** under LF AI governance, rather than merged into
> upstream SPIRE/Keylime/Envoy.

### Upstreaming Destination Map

| Component | Upstream Destination | Rationale |
|-----------|---------------------|-----------|
| SPIRE NodeAttestor plugin | `spiffe/spire` | Standard plugin architecture |
| SPIRE CredentialComposer | `spiffe/spire` | Standard plugin architecture |
| Keylime Delegated Certification | `keylime/rust-keylime` | New API extension |
| Keylime Geolocation API | `keylime/rust-keylime` | New API extension |
| Keylime Verifier extensions | `keylime/keylime` | Python verifier changes |
| **Envoy WASM Plugin** | **Standalone (LF AI)** | Too specialized for Envoy core |
| **Mobile Sensor Microservice** | **Standalone (LF AI)** | CAMARA integration wrapper |

> [!NOTE]
> **Architecture Decision (December 2025)**: WASM + Sidecar is the confirmed pattern. WASM filter extracts claims from certificates (unavoidable for custom X.509 extensions), sidecar handles OAuth/caching/secrets.

| Task | Description | Priority | Status | Owner | Target |
|------|-------------|----------|--------|-------|--------|
| **Task 7** | Envoy WASM Plugin - Policy-Based Verification Modes | P1 | `[x]` | — | Done |
| **Task 8** | Envoy WASM Plugin - MSISDN Extraction from SVID | P1 | `[x]` | — | Done |
| **Task 9** | Envoy WASM Plugin - Package for standalone release | P2 | `[ ]` | TBD | Week 4 |
| **Task 10** | Envoy WASM Plugin - Publish Signed WASM to OCI registry | P2 | `[ ]` | TBD | Week 5 |
| **Task 11** | Mobile Sensor Sidecar - Pure Mobile & DB-less Flow | P1 | `[x]` | — | Done |
| **Task 12** | Mobile Sensor Sidecar - Pluggable Backends | P3 | `[ ]` | TBD | Post-1.0 |

### Task 7 Details (Complete)
- Implemented `verification_mode` config: `trust`, `runtime`, `strict`
- Trust mode: No sidecar call (default, trust attestation-time verification)
- Runtime mode: Sidecar call with caching (15min TTL)
- Strict mode: Sidecar call with `skip_cache=true` (real-time)

### Task 8 Details (Complete)
- Extract `sensor_msisdn` from Unified Identity extension JSON
- Pass MSISDN to sidecar (no DB lookup needed)

### Task 9: Package for Standalone Release

> [!NOTE]
> **Why Standalone?** The Envoy WASM plugin is too specialized for Envoy core/contrib 
> (SPIFFE SVIDs + CAMARA + geolocation). It will be released as a standalone LF AI project
> while remaining in this repo for coordinated development.

```
Goal: Prepare WASM plugin for standalone distribution while keeping source in hybrid-cloud-poc

Current Location (keep as-is):
  hybrid-cloud-poc/enterprise-private-cloud/wasm-plugin/

Packaging Actions:
1. Add standalone README.md with usage outside hybrid-cloud-poc context
2. Add Dockerfile for reproducible WASM builds
3. Add Makefile with build/test/release targets
4. Create examples/ directory with Envoy configs for common scenarios
5. Document integration with any SPIFFE/SPIRE deployment (not just this PoC)
6. Register in Envoy Extension Hub for discoverability

Distribution:
- Source remains in AegisSovereignAI repo (coordinated development)
- Binary WASM published to OCI registry (ghcr.io)
- Listed in Envoy Extension Hub (discoverability)

This approach enables:
- External users can consume WASM binary without cloning repo
- Development stays coordinated with SPIRE/Keylime upstreaming
- Future extraction to standalone repo if community demands it

Dependencies: Tasks G1-G6
Effort: 2-3 days
```

### Task 10: Publish Signed Artifacts to OCI Registry
```
Goal: Enable consumption without cloning the repo

Artifacts:
- ghcr.io/lfai/aegis-envoy-wasm-plugin:latest       # WASM binary
- ghcr.io/lfai/aegis-mobile-sensor-sidecar:latest   # Container image

Build Process (GitHub Actions):
1. On git tag: build WASM from hybrid-cloud-poc/enterprise-private-cloud/wasm-plugin/
2. Sign with cosign (Sigstore)
3. Push to GitHub Container Registry
4. Generate SBOM (Software Bill of Materials)
5. Create GitHub Release with changelog

Envoy Configuration Example:
  typed_config:
    "@type": type.googleapis.com/envoy.extensions.wasm.v3.PluginConfig
    vm_config:
      runtime: "envoy.wasm.runtime.v8"
      code:
        remote:
          http_uri:
            uri: "oci://ghcr.io/lfai/aegis-envoy-wasm-plugin:v1.0.0"

Distribution Channels:
- GitHub Container Registry (OCI format) - primary
- GitHub Releases (raw .wasm) - manual deployment
- Envoy Extension Hub - discoverability

Dependencies: Task 9, Tasks G1-G6
Effort: 2 days
```

### Task 11 Details (Complete)
- Refined to "Pure Mobile" (GNSS handled by WASM, sidecar rejects non-mobile)
- Implements **DB-LESS flow**: Prioritizes `msisdn`, `latitude`, `longitude`, `accuracy` from SVID
- Falls back to DB-BASED lookup ONLY if SVID data is missing
- Added support for `sensor_imei`, `sensor_imsi`, and `sensor_serial` in mapping

### Pillar 3 Deep-Dive: Standalone Components

> [!NOTE]
> **Upstreaming Context**: These components are NOT going to upstream projects (Envoy, etc.) 
> because they are too specialized. They will be released as standalone LF AI projects, with
> source remaining in this repo for coordinated development with the upstreamed SPIRE/Keylime code.

#### Component 1: Envoy WASM Plugin
*Goal: Reusable Envoy filter for SPIFFE SVID claim extraction and policy-based location verification.*

**Why Standalone (not Envoy upstream)?**
- Extracts custom X.509 extensions specific to Unified Identity
- Requires Mobile Sensor Sidecar for CAMARA integration
- Target audience: Sovereign AI / telco / regulated industries (niche)

**Technical Approach**:
* **Source Location**: `hybrid-cloud-poc/enterprise-private-cloud/wasm-plugin/`
* **Language**: Rust (via Proxy-Wasm SDK)
* **Distribution**: OCI registry binary + Envoy Extension Hub listing
* **Consumption**: Users pull WASM binary, no need to clone AegisSovereignAI repo

**Policy Modes**:
| Mode | Behavior | Use Case |
|------|----------|----------|
| `trust` | No sidecar call | High-trust environments |
| `runtime` | Sidecar call with caching (15min TTL) | Balanced security/performance |
| `strict` | Sidecar call, no cache | Zero-trust, real-time verification |

#### Component 2: Mobile Sensor Microservice  
*Goal: Thin CAMARA API wrapper for mobile device location verification.*

**Why Standalone (not CAMARA upstream)?**
- Integration glue between WASM filter and CAMARA APIs
- Implements DB-LESS flow using SVID claims
- Caching layer for OAuth tokens and verification results

**Technical Approach**:
* **Source Location**: `hybrid-cloud-poc/mobile-sensor-microservice/`
* **Language**: Python (Flask)
* **Distribution**: Container image (ghcr.io)
* **Architecture**: Adapter pattern for multiple telco backends

---

## Pillar 4: Production Readiness (Hardening)

*Goal: Transform the PoC into a secure, production-grade solution.*

| Task | Description | Priority | Status | Owner | Target |
|------|-------------|----------|--------|-------|--------|
| **Task 13** | TLS Verification - Remove `InsecureSkipVerify` | P0 | `[x]` | — | Done |
| **Task 14** | Secrets Management - Move CAMARA API keys to secure providers | P1 | `[x]` | — | Done |
| **Task 14b** | Delegated Certification Fix (TPM2_Certify empty response) | **P0** | `[ ]` | TBD | Week 1 |
| **Task 15** | Quality Assurance - Linting, pre-commit hooks | P2 | `[ ]` | TBD | Week 3 |
| **Task 16** | Cleanup stale backup files | P1 | `[ ]` | TBD | Week 1 |
| **Task 17** | Rate limiting at Envoy gateway level | P2 | `[ ]` | TBD | Week 4 |
| **Task 18** | Standardize Observability (Metrics & Telemetry) | P1 | `[ ]` | TBD | Week 4 |

### Task 14b: Delegated Certification Fix (CRITICAL BLOCKER)

> [!CAUTION]
> **This is a P0 blocker for open source release.** The system works but attestation lacks real TPM evidence.

**Problem Statement:**
```
Failed to request certificate: Empty response from rust-keylime
SPIRE Server logs: TpmAttestation len=0, AppKeyCert len=0
```

**Investigation & Resolution (All items below are part of Task 14b):**

**Investigation Checklist:**
- [x] Debug `rust-keylime` `/v2.2/delegated_certification/certify_app_key` endpoint → **FIXED**
- [ ] Verify TPM context file path is accessible (if issue persists after fix)
- [ ] Check AK handle loading in `delegated_certification_handler.rs` (if issue persists)
- [ ] Verify `create_qualifying_data()` hash computation (if issue persists)
- [ ] Test `TPM2_Certify` directly via `tpm2-tools` (if issue persists)
- [ ] Verify App Key certificate chain: App Key → AK → EK (if issue persists)

**Root Causes Identified & Fixed (2025-12-28):**

✅ **Issue 1: JSON Response Format Mismatch**
   - The Rust endpoint was returning raw struct instead of `JsonWrapper`, causing the Python client to fail parsing the response.
   - **Fix**: Wrapped response in `JsonWrapper::success()` in Rust handler (line 287)
   - **Fix**: Updated Python client to extract from `JsonWrapper.results` field (lines 199-230)

✅ **Issue 2: HTTP vs HTTPS Protocol Mismatch**
   - The rust-keylime agent requires HTTPS (mTLS enabled by default), but Python client was using HTTP.
   - This caused "Connection reset by peer" errors.
   - **Fix**: Updated `delegated_certification.py` to automatically convert HTTP to HTTPS (line 78-84)
   - **Fix**: Updated `tpm_plugin_server.py` to default to HTTPS endpoint (line 128)

**Fixes Applied:**
1. **Rust Handler** (`delegated_certification_handler.rs`):
   - Added `Deserialize` trait to `CertifyAppKeyResponse` struct (line 61)
   - Wrapped response in `JsonWrapper::success()` (line 287)
   - Now consistent with all other rust-keylime endpoints

2. **Python Client** (`delegated_certification.py`):
   - Updated to extract from `JsonWrapper` format: `response.get("results", {}).get("result")`
   - Added proper error handling for JsonWrapper error responses
   - Automatically converts HTTP endpoints to HTTPS
   - Returns error response body instead of None for better debugging

3. **TPM Plugin Server** (`tpm_plugin_server.py`):
   - Changed default endpoint from `http://127.0.0.1:9002` to `https://127.0.0.1:9002`

**Additional Root Cause Candidates (to investigate if fix doesn't resolve issue):**
1. TPM context file not found/accessible by rust-keylime
2. AK handle mismatch between keylime-agent and TPM Plugin
3. Challenge nonce format mismatch

**Files to Investigate:**
```
hybrid-cloud-poc/rust-keylime/keylime-agent/src/delegated_certification_handler.rs
hybrid-cloud-poc/tpm-plugin/tpm_plugin_server.py
hybrid-cloud-poc/keylime/keylime/app_key_verification.py
hybrid-cloud-poc/spire/pkg/agent/tpmplugin/delegated_certification.go
```

**Success Criteria:**
- [ ] `TpmAttestation len > 0` in SPIRE Server logs
- [ ] `AppKeyCert` contains valid TPM2_Certify signature
- [ ] End-to-end attestation with real TPM evidence

**Effort:** 2-3 days (debugging complex multi-component flow)

### Task 16: Cleanup Stale Files (NEW)
```
Files to Remove:
- hybrid-cloud-poc/spire/conf/agent/spire-agent.conf.bak.*
- hybrid-cloud-poc/spire/conf/server/spire-server.conf.bak.*
- Any other *.bak, *.orig, *.tmp files

Action:
find . -name "*.bak*" -o -name "*.orig" -o -name "*.tmp" | xargs rm -f

Effort: 30 minutes
```

### Task 17: Envoy Rate Limiting (NEW)
```
Current State: Rate limiting exists in rust-keylime delegated_certification_handler
Missing: Envoy-level rate limiting for API gateway protection

Implementation:
- Add Envoy rate limit filter configuration
- Configure limits per client certificate
- Add circuit breaker for sidecar calls

Effort: 1-2 days
```

### Task 18: Observability & Telemetry (NEW)
```
Goal: Standardize telemetry for production visibility.
Actions:
1. Implement Prometheus metrics in Envoy WASM filter (request latency, verification results).
2. Implement Prometheus metrics in Mobile Sensor Microservice.
3. Define standard Grafana dashboard for "Unified Identity Health".
4. Ensure structured JSON logging across all components.
Dependencies: None
Effort: 3-4 days
```

---

## Pillar 5: Documentation Completeness (NEW)

*Goal: Ensure all documentation is accurate, complete, and cross-referenced.*

| Task | Description | Priority | Status | Owner | Target |
|------|-------------|----------|--------|-------|--------|
| **Task D1** | Create `PREREQUISITES.md` (or remove reference) | P0 | `[ ]` | TBD | Week 1 |
| **Task D2** | Create `PILLAR2_STATUS.md` (or remove reference) | P1 | `[ ]` | TBD | Week 1 |
| **Task D3** | Fix stale `file:///` URLs in architecture doc | P1 | `[ ]` | TBD | Week 1 |
| **Task D4** | Add version headers to all documentation | P2 | `[ ]` | TBD | Week 2 |
| **Task D5** | Create CHANGELOG.md | P1 | `[ ]` | TBD | Week 2 |
| **Task D6** | Standardize sensor type casing (mobile/gnss) | P2 | `[ ]` | TBD | Week 2 |
| **Task D7** | Expand troubleshooting section in README | P2 | `[ ]` | TBD | Week 3 |
| **Task D8** | Add container/Kubernetes deployment docs | P2 | `[ ]` | TBD | Week 4 |
| **Task D9** | Define Versioning & Release Strategy (SemVer) | P2 | `[ ]` | TBD | Week 2 |

### Task D1: PREREQUISITES.md
```
Option A: Create the file
Location: hybrid-cloud-poc/PREREQUISITES.md
Content: Extract prerequisite content from README.md lines 107-245
Benefit: Cleaner README, reusable prereqs

Option B: Remove reference
Edit: hybrid-cloud-poc/README.md line 245
Change: Remove "For detailed prerequisite information, see [PREREQUISITES.md]..."

Recommended: Option A
Effort: 1-2 hours
```

### Task D2: PILLAR2_STATUS.md
```
Option A: Create the file
Location: hybrid-cloud-poc/PILLAR2_STATUS.md
Content: Detailed status of all Pillar 2 tasks with code locations

Option B: Remove reference
Edit: hybrid-cloud-poc/README-arch-sovereign-unified-identity.md line 1318
Change: Remove reference or point to this roadmap

Recommended: Option B (consolidate in this roadmap)
Effort: 30 minutes
```

### Task D3: Fix Stale File URLs
```
Problem:
- Line 175: file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/spire/...
- These URLs don't work on GitHub

Fix:
- Convert to relative paths: ./spire/pkg/agent/tpmplugin/tpm_signer.go#L122
- Or remove line numbers entirely for maintainability

Files to Update:
- hybrid-cloud-poc/README-arch-sovereign-unified-identity.md

Effort: 1 hour
```

### Task D4: Version Headers
```
Add to all major documents:
<!-- Version: X.Y.Z | Last Updated: YYYY-MM-DD -->

Files:
- hybrid-cloud-poc/README.md
- hybrid-cloud-poc/README-arch-sovereign-unified-identity.md
- hybrid-cloud-poc/UPSTREAM_MERGE_ROADMAP.md (this file - done)
- All component READMEs

Effort: 1 hour
```

### Task D5: CHANGELOG.md
```
Location: /CHANGELOG.md (root) + hybrid-cloud-poc/CHANGELOG.md

Format: Keep a Changelog (https://keepachangelog.com/)

Initial Content:
## [Unreleased]
### Fixed
- Task 14b: Delegated certification empty response

## [0.1.0] - 2025-12-XX
### Added
- Initial PoC release
- Unified Identity architecture
- SPIRE plugins (NodeAttestor, CredentialComposer, Validator)
- Keylime extensions (Delegated Certification, Geolocation)
- Envoy WASM plugin with policy modes
- Mobile Sensor Microservice

Effort: 2 hours
```

### Task D6: Terminology Consistency
```
Issue: Inconsistent casing of sensor types across documents
- README.md: "mobile", "GNSS"
- Architecture doc: "mobile", "gnss"
- Code: "mobile", "gnss" (lowercase)

Decision: Use lowercase everywhere (mobile, gnss) to match code
Files to Update: README.md, README-arch-sovereign-unified-identity.md

Effort: 30 minutes
```

### Task D7: Expanded Troubleshooting
```
Current Coverage (README.md lines 725-744):
- Port conflicts
- TPM access
- Service startup order
- Log locations

Missing Topics:
- TPM initialization failures (tpm2_startup, ownership)
- CAMARA API authentication errors
- Certificate chain validation errors
- Keylime registration failures
- SPIRE agent attestation failures
- Envoy WASM filter loading errors
- Sensor ID not found in database

Effort: 2-3 hours
```

### Task D8: Container/Kubernetes Docs
```
Current State: Only bare-metal/VM deployment documented

Missing:
- Dockerfile for each component
- docker-compose.yml for local development
- Kubernetes manifests (Deployment, Service, ConfigMap)
- Helm chart (optional, P3)

Location: hybrid-cloud-poc/deploy/

Structure:
deploy/
├── docker/
│   ├── Dockerfile.spire-server
│   ├── Dockerfile.spire-agent
│   ├── Dockerfile.keylime-verifier
│   ├── Dockerfile.keylime-agent
│   ├── Dockerfile.mobile-sidecar
│   └── docker-compose.yml
├── kubernetes/
│   ├── namespace.yaml
│   ├── spire/
│   ├── keylime/
│   └── envoy/
└── README.md

Effort: 3-5 days (significant new work)
```

### Task D9: Versioning Strategy (NEW)
```
Goal: Establish a reliable release cadence and compatibility model.
Actions:
1. Define Semantic Versioning (SemVer) policy for plugins and APIs.
2. Establish a CHANGELOG.md maintenance process.
3. Design the "Pre-release" vs "Release" tag flow in GitHub Actions.
Dependencies: Task 0c (CI/CD)
Effort: 1 day
```

---

## 3. Risk Mitigation & Quality

### Security Risks

| Risk | Mitigation | Status |
|------|------------|--------|
| TLS bypass in development | Task 13 complete - removed all `InsecureSkipVerify` | ✅ |
| Hardcoded secrets | Task 14 complete - moved to environment variables | ✅ |
| Empty TPM attestation | Task 14b - P0 blocker | 🔴 |
| No vulnerability disclosure | Task G3 - add SECURITY.md | ⏳ |

### Operational Risks

| Risk | Mitigation | Status |
|------|------------|--------|
| No CI/CD pipeline | Task 0c - add GitHub Actions | ⏳ |
| Flaky tests | Task 0 complete - fail-fast infrastructure | ✅ |
| Stale documentation | Pillar 5 - documentation completeness | ⏳ |

### Legal/Compliance Risks

| Risk | Mitigation | Status |
|------|------------|--------|
| No license file | Task G1 - add Apache 2.0 LICENSE | 🔴 |
| No contribution agreement | Task G2 - add DCO to CONTRIBUTING.md | 🔴 |
| No code of conduct | Task G4 - add LF Code of Conduct | 🔴 |

---

## 4. Dependency Graph

```
                    ┌─────────────────────────────────────────┐
                    │           WEEK 1 (P0 Blockers)          │
                    └─────────────────────────────────────────┘
                                        │
         ┌──────────────────────────────┼──────────────────────────────┐
         │                              │                              │
         ▼                              ▼                              ▼
    ┌─────────┐                  ┌─────────────┐               ┌─────────────┐
    │ Task G1 │                  │  Task 14b   │               │  Task D1    │
    │ LICENSE │                  │ TPM Fix     │               │ PREREQS.md  │
    └─────────┘                  └─────────────┘               └─────────────┘
         │                              │                              │
         ▼                              │                              │
    ┌─────────┐                         │                              │
    │ Task G2 │                         │                              │
    │CONTRIB. │                         │                              │
    └─────────┘                         │                              │
         │                              │                              │
         ├──────────────────────────────┼──────────────────────────────┤
         │                              │                              │
         ▼                              ▼                              ▼
    ┌─────────┐                  ┌─────────────┐               ┌─────────────┐
    │ Task G3 │                  │  Task 16    │               │  Task D2    │
    │SECURITY │                  │ Cleanup     │               │ PILLAR2 ref │
    └─────────┘                  └─────────────┘               └─────────────┘
         │
         ▼
    ┌─────────────────────────────────────────┐
    │           WEEK 2 (P1 Critical)          │
    └─────────────────────────────────────────┘
         │
         ├────────────────┬────────────────┬────────────────┐
         ▼                ▼                ▼                ▼
    ┌─────────┐     ┌─────────┐     ┌─────────┐      ┌─────────┐
    │Task G4-6│     │Task 0c  │     │Task 12b │      │ Task D3 │
    │Templates│     │CI/CD    │     │Schema   │      │Fix URLs │
    └─────────┘     └─────────┘     └─────────┘      └─────────┘
                          │
                          ▼
    ┌─────────────────────────────────────────┐
    │           WEEK 3-4 (P2 Important)       │
    └─────────────────────────────────────────┘
         │
         ├────────────────┬────────────────┬────────────────┐
         ▼                ▼                ▼                ▼
    ┌─────────┐     ┌─────────┐     ┌─────────┐      ┌─────────┐
    │ Task 9  │     │Task 0d  │     │ Task 15 │      │Task D4-7│
    │Package  │     │Precommit│     │Linting  │      │Docs     │
    └─────────┘     └─────────┘     └─────────┘      └─────────┘
         │
         ▼
    ┌─────────┐
    │ Task 10 │
    │Artifacts│
    └─────────┘
         │
         ▼
    ┌─────────────────────────────────────────┐
    │           WEEK 5-6 (P2 Continued)       │
    └─────────────────────────────────────────┘
         │
         ├────────────────┬────────────────┐
         ▼                ▼                ▼
    ┌─────────┐     ┌─────────┐      ┌─────────┐
    │ Task 17 │     │ Task D8 │      │  1.0    │
    │RateLimit│     │K8s Docs │      │ RELEASE │
    └─────────┘     └─────────┘      └─────────┘
```

---

## 5. Verification Strategy

### Pre-Release Checklist

```bash
# 1. Governance files exist
[ -f LICENSE ] && echo "✓ LICENSE" || echo "✗ LICENSE"
[ -f CONTRIBUTING.md ] && echo "✓ CONTRIBUTING.md" || echo "✗ CONTRIBUTING.md"
[ -f SECURITY.md ] && echo "✓ SECURITY.md" || echo "✗ SECURITY.md"
[ -f CODE_OF_CONDUCT.md ] && echo "✓ CODE_OF_CONDUCT.md" || echo "✗ CODE_OF_CONDUCT.md"

# 2. No stale files
find . -name "*.bak*" -o -name "*.orig" | wc -l  # Should be 0

# 3. Documentation references valid
grep -r "PREREQUISITES.md" hybrid-cloud-poc/ | wc -l  # Should be 0 or file exists
grep -r "PILLAR2_STATUS.md" hybrid-cloud-poc/ | wc -l  # Should be 0 or file exists

# 4. No hardcoded secrets
grep -rn "InsecureSkipVerify.*true" --include="*.go" | wc -l  # Should be 0
grep -rn "password.*=" --include="*.py" --include="*.go" | wc -l  # Review each
```

### Full System Test

```bash
# Run integration test on real hardware (10.1.0.11)
cd hybrid-cloud-poc
./ci_test_runner.py --no-color
```

### Hardware Requirements
- Real TPM 2.0 (Available on node 10.1.0.11)
- Network connectivity for distributed SPIRE/Keylime setup

---

## 6. Weekly Sprint Plan

### Week 1: P0 Blockers (MUST COMPLETE)
- [ ] **Day 1-2**: Tasks G1-G4 (Governance files)
- [ ] **Day 2-3**: Task 14b (Debug delegated certification)
- [ ] **Day 4**: Tasks G5-G6 (GitHub templates)
- [ ] **Day 4**: Task D1 (PREREQUISITES.md)
- [ ] **Day 5**: Task 16 (Cleanup stale files)
- [ ] **Day 5**: Task D2 (Fix PILLAR2 reference)

**Exit Criteria**: Repository can be made public without legal/security issues.

### Week 2: P1 Critical
- [ ] Task 0c (CI/CD pipeline)
- [ ] Task 12b (Complete schema separation)
- [ ] Task D3 (Fix stale URLs)
- [ ] Task D5 (CHANGELOG.md)

**Exit Criteria**: Automated testing in place, documentation accurate.

### Week 3-4: P2 Important
- [ ] Task 0d (Pre-commit hooks)
- [ ] Task 9 (Standalone repo setup)
- [ ] Task 15 (Linting/QA)
- [ ] Tasks D4, D6, D7 (Documentation polish)

**Exit Criteria**: Code quality tooling in place, ready for external contributors.

### Week 5-6: P2 Continued + Release Prep
- [ ] Task 10 (Signed artifacts)
- [ ] Task 17 (Rate limiting)
- [ ] Task D8 (Kubernetes docs)
- [ ] Final review and 1.0 release

**Exit Criteria**: Production-ready release with full documentation.

---

## Appendix A: File Inventory for Cleanup

### Files to Remove (Task 16)
```
hybrid-cloud-poc/spire/conf/agent/spire-agent.conf.bak.*
hybrid-cloud-poc/spire/conf/server/spire-server.conf.bak.*
```

### Files to Create (Pillar 0)
```
/LICENSE
/CONTRIBUTING.md
/SECURITY.md
/CODE_OF_CONDUCT.md
/.github/ISSUE_TEMPLATE/bug_report.md
/.github/ISSUE_TEMPLATE/feature_request.md
/.github/PULL_REQUEST_TEMPLATE.md
```

### Files to Update (Pillar 5)
```
hybrid-cloud-poc/README.md (add version header, expand troubleshooting)
hybrid-cloud-poc/README-arch-sovereign-unified-identity.md (fix URLs, remove stale refs)
```

---

## Appendix B: External Dependencies & Toolchains

| Dependency | Verified Version | Target Upstream | Purpose |
|------------|------------------|-----------------|---------|
| **SPIRE** | 1.14.0 | v1.11.x+ | Identity management |
| **Keylime (Python)**| 7.13.0 | v7.14.x | Remote attestation |
| **Keylime (Rust)** | 0.2.8 | v0.3.x | Remote attestation |
| **Envoy** | 1.35.x | v1.31.x+ | API gateway |
| **tss-esapi** (Rust)| 7.6.0 | Latest | TPM bindings |
| **Go Toolchain** | 1.22.0 | v1.22+ | Build & Runtime |
| **Rust Toolchain** | 1.91.1 | Stable | Build & Runtime |
| **Python** | 3.10.12 | 3.10+ | Build & Runtime |

---

*Last Updated: 2025-12-28 | Next Review: 2025-01-04*


