# Execution Strategy: Unified Identity Upstreaming

## Overview
This document outlines the strategic approach for refactoring the "Unified Identity" PoC into upstream-ready components. We will follow a **3-Pillar Strategy** to ensure stability, quality, and security throughout the process.

## Pillar 1: Test Infrastructure (Safety Net)
*Goal: Establish a reliable, fail-fast testing environment to catch regressions immediately.*

### 1.1. Harden `test_integration.sh`
*   **Current State**: Good start (`set -e`, logging), but relies on brittle SSH/IP assumptions.
*   **Action**:
    *   **Fail-Fast**: Ensure every sub-script returns a proper exit code.
    *   **Structured Logging**: Aggregate logs from all components (Server, Agent, Verifier) into a single artifact directory for CI analysis.
    *   **Watcher**: Implement a simple CI-style watcher that tails the comprehensive log and alerts on failure patterns.

### 1.2. Containerized Testing (Optional Future State)
*   **Note**: `swtpm` simulation can differ from real hardware behavior (EK Certs, specific PCR banks), adding complexity.
*   **Strategy**: **Prioritize the existing VM-based environment.**
    *   Focus on making `test_integration.sh` robust for the current setup (which uses real/provisioned TPMs).
    *   Defer containerization until the upstream logic is stable.

---

## Pillar 2: Upstreaming Implementation (Refactoring)
*Goal: Execute the architectural changes defined in the Roadmap.*

### 2.1. Keylime Protocol Extensions (Rust Team)
*   **Task 1**: Implement `delegated_certifier` endpoint for App Key signing.
*   **Task 2**: Implement `attested_geolocation` optional API.

### 2.2. Keylime Verification API (Python Team)
*   **Task 3**: Upstream `/verify/evidence` endpoint (Stateless Attestation) and remove dead mobile sensor code.

### 2.3. SPIRE Custom Plugins (Go Team)
*   **Task 4**: Build `spire-plugin-unified-identity` (Server Validator).
*   **Task 5**: Build `spire-plugin-unified-identity` (Agent Collector).
*   **Task 6**: Configure `CredentialComposer` for claims injection.

---

## Pillar 3: Production Readiness (Hardening)
*Goal: Transform the PoC into a secure, production-grade solution.*

### 3.1. Security Hardening
*   **TLS Verification**: Remove `InsecureSkipVerify: true`. Implement proper CA certificate loading for SPIRE-to-Keylime mTLS.
*   **Secrets Management**: Move CAMARA API keys and other secrets out of environment variables/code and into a proper Secrets Provider (Kubernetes Secrets, Vault, etc.).

### 3.2. Quality Assurance
*   **Pre-commit Hooks**: Add `pre-commit` hooks to run linters (clippy, golangci-lint, flake8) before every commit.
*   **GitHub Issues**: Systematically address open issues in the `AegisSovereignAI` repository related to stability and performance.

---

## 4. Risk Mitigation & enhancements
*   **Aggressive State Sanitization**: TPMs and Keylime DBs retain state. We must ensure `test_integration.sh` includes a "Nuke Mode" that clears TPM NVRAM indices and wipes the Verifier DB before every run to prevent "flaky" tests from leftover state.
*   **Partial Containerization**: While Agents run on host, we *should* Dockerize the pure software components (Mobile Sensor Service, Envoy) to reduce dependency conflicts on the test runner.
*   **Version Pinning**: Explicitly pin the versions of upstream SPIRE and Keylime we build against to avoid breaking changes during our refactoring.
