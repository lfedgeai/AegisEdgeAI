Architecture — Implementation Specification for PoR/PoG Flow

Introduction: Unified Identity for Sovereign AI

This document provides the technical specification for implementing the Zero-Trust Sovereign AI architecture. This system is designed to meet strict regulatory and compliance requirements (e.g., data residency and geofencing) by replacing vulnerable network-based trust controls with hardware-rooted cryptographic proofs.

The core innovation involves establishing a Unified Workload Identity by extending the SPIRE framework. This identity binds the workload's cryptographic identity with verifiable Proof of Residency (PoR) and Proof of Geofencing (PoG) facts retrieved through the Keylime Verifier. The flow is structured to reuse existing Keylime endpoints, simplifying Keylime's role to a trusted fact-provider, while centralizing final policy evaluation and SVID issuance within the SPIRE Server.

🔒 Trust Assumptions

This flow relies on several critical security primitives and architectural assumptions to enable the simplified, delegated verification model.

Component

Trust Assumption

Purpose in Flow

Trusted Platform Module (TPM)

The TPM is the hardware root of trust on the host, is non-compromised, and its keys (EK, AK) are secure and accurate.

Anchors the host's identity (EK/AK) and enables the cryptographic proofs for the Proof of Residency (PoR) via the App Key.

Keylime & SPIRE (Trusted Components)

The Keylime Verifier and SPIRE Server are both secure, non-compromised, and communicate over a trusted, mutually authenticated (mTLS) channel.

Architectural Simplification: Allows the SPIRE Server to act as the central orchestrator, delegating TPM validation to Keylime and integrating the verified facts into the SVID.

TPM Application Key (App Key)

The App Key is certified by the host's AK and is protected by the TPM, preventing extraction or cloning.

Provides the unique key used to sign the runtime PoR proof (the TPM Quote), establishing irrefutable assurance that the workload is running on the expected host.

Keylime's Attestation Data

The Keylime system is trusted to securely and accurately gather and persist the hardware-rooted geolocation and GPU metrics data, making it a reliable fact-provider.

Provides the verifiable host health, integrity, and location data necessary for the Proof of Geofencing (PoG) claim.

---

## 🔒 The AK Matching Process: Proof of Provenance

The entire purpose of the **App Key Certificate** is to bind the new workload-specific key (the App Key) to the hardware's existing, registered identity (the AK).

### 1. Keylime's Anchor (The Host Identity)
When the bare-metal host initially enrolls, the Keylime Verifier stores the host's **TPM Attestation Key (AK) Public Key** in its **Registrar**. This AK Public Key is Keylime's cryptographic anchor for that specific host.

### 2. The Certificate Chain (The Proof)
The **App Key Certificate** is generated when the SPIRE Agent's TPM plugin calls `tpm2_certify`. This certificate contains:
1.  The **App Key's Public Key**.
2.  A cryptographic signature over the certificate's contents, created by the host's **AK Private Key**.

### 3. Verification and Match
When the **SPIRE Server** forwards the certificate to the **Keylime Verifier**, the verifier performs these steps:

| Step | Action | Trust Result |
| :--- | :--- | :--- |
| **A. Retrieve Anchor** | The Verifier retrieves the **AK Public Key** from its local **Registrar** using the host identifier (e.g., EK hash). | Establishes the host's trusted identity. |
| **B. Validate Certificate** | The Verifier uses the host's **AK Public Key** to verify the digital signature on the **App Key Certificate**. | If the signature is valid, it proves the App Key was genuinely created and certified by the physical host's trusted AK. |
| **C. Validate Quote** | The Verifier uses the newly trusted **App Key Public Key** (extracted from the certificate) to verify the signature on the **TPM Quote** (the runtime PoR proof). | Proves the workload is currently live and running on the certified host. |

In short, the **App Key Certificate** acts as the crucial cryptographic bridge, allowing the Keylime Verifier to verify a runtime workload claim without ever needing to directly talk to the host's TPM, relying instead on its stored knowledge of the host's **AK public key**.

---

## Required API Modifications
To implement the above flow, we need to make specific API changes to both the SPIRE workload protobufs and the Keylime Verifier's REST API. The following sections detail these changes, including field-level validations, responsibilities, and migration notes.

## Implementation-ready API & Protobuf Specification

The following section merges the full API changes, protobuf schemas, field-level validations, OpenAPI snippets, responsibility matrix, migration notes, security guidance, tests, and an implementation checklist. This is intended to be copy/paste-ready for engineering teams implementing the flow.

1) SPIRE protobuf changes (SovereignAttestation & AttestedClaims)

Add the following messages to the SPIRE workload protobufs. Choose tag numbers that do not conflict with existing definitions in your repository.

```proto
syntax = "proto3";
package spire.workload;

// A hardware-rooted PoR package produced by the Agent.
message SovereignAttestation {
  // Base64-encoded TPM Quote (portable string). Validation: non-empty, base64, size <= 64kB
  string tpm_signed_attestation = 1;

  // The App Key public key (PEM or base64-encoded). Preferred format: PEM.
  // Validation: when present must parse; server-side validation enforced.
  string app_key_public = 2;

  // Optional base64-encoded DER or PEM certificate proving the App Key was issued/signed by the host AK.
  // Validation: when present must parse to X.509 cert; chain verification will be performed by Keylime.
  bytes app_key_certificate = 3;

  // The SPIRE Server nonce used for freshness verification.
  string challenge_nonce = 4;

  // Optional workload code hash used as an additional selector/assertion.
  string workload_code_hash = 5;
}
```

Inject into the existing request:

```proto
message X509SVIDRequest {
  // existing fields...
  SovereignAttestation sovereign_attestation = 20; // pick an unused tag
}
```

Add attested claims to responses so components can consume verified facts when needed:

```proto
message AttestedClaims {
  message GpuMetrics {
    string status = 1;        // 'healthy', 'degraded', 'failed'
    double utilization_pct = 2; // 0..100
    int64 memory_mb = 3;
  }

  string geolocation = 1;    // structured preferred; free-form fallback allowed
  enum HostIntegrity { HOST_INTEGRITY_UNSPECIFIED = 0; PASSED_ALL_CHECKS = 1; FAILED = 2; PARTIAL = 3; }
  HostIntegrity host_integrity_status = 2;
  GpuMetrics gpu_metrics_health = 3;
}

message X509SVIDResponse {
  // existing fields...
  repeated AttestedClaims attested_claims = 30;
}
```

Validation recommendations for proto fields:
- `tpm_signed_attestation`: max size 64 KiB; must be base64-valid and decode to an expected TPM quote structure.
- `app_key_certificate`: bytes with max size ~16 KiB; must parse as X.509 DER/PEM. Chain validation occurs in Keylime.
- `app_key_public`: PEM or base64; validate parsing on receipt.
- `challenge_nonce`: must match a server-issued nonce and be single-use / time-limited.

2) Keylime API (OpenAPI-style) — reuse endpoint

We reuse `POST /v2.4/verify/evidence` and document the tpm-app-key flow fields and responses.

Request (tpm-app-key annotated):

```json
{
  "data": {
    "nonce": "string",                
    "quote": "string",                
    "hash_alg": "sha256",             
    "app_key_public": "string",       
    "app_key_certificate": "string",  
    "tpm_ak": "string (optional)",
    "tpm_ek": "string (optional)"
  },
  "metadata": { "source": "SPIRE Server", "submission_type": "PoR/tpm-app-key", "audit_id": "optional" }
}
```

Response (success):

```json
{
  "results": {
    "verified": true,
    "verification_details": {
      "app_key_certificate_valid": true,
      "app_key_public_matches_cert": true,
      "quote_signature_valid": true,
      "nonce_valid": true,
      "timestamp": 1690000000
    },
    "attested_claims": {
      "geolocation": "Spain: N40.4168, W3.7038",
      "host_integrity_status": "passed_all_checks",
      "gpu_metrics_health": { "status":"healthy", "utilization_pct":15.0 }
    },
    "audit_id": "uuid-..."
  }
}
```

HTTP codes: 200 (OK — check `results.verified`), 400 (bad request), 401/403 (auth), 422 (certificate/validation errors), 500 (server err).

3) Field-level validation & constraints

- `quote` / `tpm_signed_attestation`: base64 string; must decode to valid TPM quote; size <= 64 KiB.
- `app_key_certificate`: DER bytes or PEM string; size <= 16 KiB; must parse to X.509.
- `app_key_public`: PEM/base64; must parse; when certificate present must match certificate public key.
- `nonce`: string; match server-issued nonce; valid window (e.g., 5 min); single-use.
- `geolocation`: structured preferred. If free-form, limit length (<= 256 chars).
- `gpu_metrics_health.utilization_pct`: 0..100; `memory_mb` >= 0.

4) Responsibility matrix

- SPIRE Agent: generate TPM quote; optionally create `app_key_certificate` via TPM plugin; send `SovereignAttestation` in `X509SVIDRequest`.
- SPIRE Server: issue nonce; validate request fields; forward evidence to Keylime; evaluate `attested_claims` against registration policy; embed claims in SVID or trigger remediation.
- Keylime Verifier: authenticate caller; validate `app_key_certificate` chain; verify `quote` signature using app key; validate nonce/timestamps; return `attested_claims` and `verification_details`.
- Registrar/Operator: manage trust anchors (AK CA) and registrar state.

5) Migration & backward-compatibility

- Preserve `POST /v2.4/verify/evidence` as canonical endpoint. Existing clients without app_key fields remain supported.
- Encourage SPIRE Agents to include `app_key_certificate` when available for higher assurance.
- Add metadata `submission_type = PoR/tpm-app-key` so operators can filter logs.
- Optionally add `/v2.4/verify/evidence/tpm-app-key` as an alias later.

6) Security & operational notes

- Enforce mTLS with client auth for SPIRE Server → Keylime traffic.
- Require Keylime to validate `app_key_certificate` against a configured trust store (AK/CA); consider CRL/OCSP.
- Use single-use, time-limited nonces; store seen nonces short-term to prevent replay.
- Return an `audit_id` from Keylime and persist it in SPIRE for traceability.
- Rate-limit and ACL tpm-app-key submissions; redact sensitive binary blobs in logs.

7) Tests & validation harness

- Unit tests for cert parsing, pubkey matching, quote signature verification, nonce reuse detection.
- Integration tests with swtpm and a test Keylime: full E2E from Agent -> SPIRE Server -> Keylime -> SPIRE Server policy -> SVID issuance.
- Failure-mode tests: missing cert, mismatched pubkey, reused nonce, oversized payload.

8) Implementation checklist & rollout plan

Phase 1 — Proto & Agent
- Reserve proto tags; create PR for `SovereignAttestation` and `AttestedClaims` changes.
- Update SPIRE TPM plugin to optionally emit `app_key_certificate` + app key public.

Phase 2 — Keylime
- Accept annotated `POST /v2.4/verify/evidence`; implement cert chain verification; verify quote using app key; emit `attested_claims` + `audit_id`.

Phase 3 — SPIRE Server
- Forward evidence to Keylime; evaluate `attested_claims` in policy engine; embed claims into SVID extensions and handle remediation paths.

Phase 4 — Testing & rollout
- Perform swtpm-based E2E tests; stage rollout; monitor audit logs and rate-limits.

Appendix: sample proto snippets and examples

See the protobuf snippets above (SovereignAttestation / AttestedClaims) and the Keylime JSON examples for exact request/response shapes.

---


## Full end-to-end flow (with API details)

### 1) Workload identity initiation (nonce request)

- The SPIRE Agent requests a challenge nonce from the SPIRE Server. The request includes workload selectors and an optional workload code hash.

Example request (modified `X509SVIDRequest`):

```json
{
  "spiffe_id": "spiffe://sovereign.cloud/workload/ai-inference",
  "selectors": ["k8s:ns:default", "docker:image:model-v2"],
  "sovereign_attestation": { "workload_code_hash": "a2b3c4d5e6f7..." }
}
```

Example response (modified `X509SVIDResponse`):

```json
{
  "nonce": "e3k7h9p1d5r2n4m6...",
  "server_timestamp": 1730424000,
  "svids": []
}
```

---

### 2) Proof of Residency (PoR) generation (internal to host)

- The SPIRE Agent calls a local TPM plugin to sign the challenge and produce a hardware-rooted PoR.

Internal call (example):

```
SPIRE_TPM_PLUGIN.sign_challenge(nonce, server_timestamp, code_hash)
```

Internal response (example):

```json
{
  "tpm_signed_attestation": "BASE64_ENCODED_TPM_QUOTE_FOR_WORKLOAD",
  "app_key_public": "PUBLIC_KEY_OF_TPM_APP_KEY",
  "app_key_certificate": "BASE64_ENCODED_APP_KEY_CERT_BY_AK" // OPTIONAL: SPIRE TPM plugin can generate this certificate for the App Key
  "workload_code_hash": "a2b3c4d5e6f7..."
}
```

Note: the SPIRE TPM plugin can optionally generate an `app_key_certificate` (the App Key cert signed by the AK) alongside the `tpm_signed_attestation`. When present, the SPIRE Server should forward both the `app_key_certificate` and the `tpm_signed_attestation` to the Keylime Verifier.

---

### 2a) Delegated Certification (SPIRE Agent -> Keylime Agent)

To avoid insecure file sharing of the Attestation Key (AK) context, the low-privilege SPIRE Agent delegates the App Key certification to the high-privilege Keylime Agent via a secure local API (e.g., gRPC over a UNIX socket).

**Local API Request (SPIRE Agent -> Keylime Agent):**

```json
{
  "api_version": "v1",
  "command": "certify_app_key",
  "app_key_public": "PUBLIC_KEY_OF_TPM_APP_KEY"
  "app_ctx": "PRIVATE_CONTEXT_OF_TPM_APP_KEY"
}
```

**Local API Response (Keylime Agent -> SPIRE Agent):**

```json
{
  "result": "SUCCESS",
  "app_key_certificate": "BASE64_ENCODED_APP_KEY_CERT_BY_AK"
}
```

This local, delegated flow ensures that the `ak.ctx` handle is only ever accessed by the privileged Keylime Agent, while the SPIRE Agent receives the resulting certificate without ever touching the sensitive key context. The Keylime Agent is responsible for persisting the `ak.ctx` across reboots.

---

### 3) PoR submission (SPIRE Agent → SPIRE Server)

- The SPIRE Agent submits the TPM-signed PoR to the server as part of the continued `X509SVIDRequest` stream.

Example payload:

```json
{
  "spiffe_id": "spiffe://sovereign.cloud/workload/ai-inference",
  "sovereign_attestation": {
    "tpm_signed_attestation": "BASE64_ENCODED_TPM_QUOTE_FOR_WORKLOAD",
    "app_key_public": "PUBLIC_KEY_OF_TPM_APP_KEY",
    "app_key_certificate": "BASE64_ENCODED_APP_KEY_CERT_BY_AK", // NEW: certificate proving the App Key's legitimacy
    "challenge_nonce": "e3k7h9p1d5r2n4m6..."
  }
}
```

---

### 4) Orchestrating host verification (SPIRE Server → Keylime Verifier)

- The SPIRE Server verifies the PoR signature locally and delegates location and additional host checks to Keylime via the new endpoint.

Example request (SPIRE → Keylime):

Revised Keylime role

We reuse Keylime's existing verifier endpoint `POST /v2.4/verify/evidence` but simplify its responsibilities: Keylime should only validate the TPM quote (signature and nonce) and return the raw, hardware-attested facts. Policy evaluation (PoG, GPU thresholds) is performed by the SPIRE Server's policy engine.

Minimal request shape (SPIRE → Keylime):

```json
{
  "data": {
    "nonce": "e3k7h9p1d5r2n4m6...",
    "quote": "BASE64_ENCODED_TPM_QUOTE_FOR_WORKLOAD",
    "hash_alg": "sha256",
    "tpm_ak": "PUBLIC_KEY_OF_HOSTS_AK (optional)",
    "tpm_ek": "HOST_EK_KEY_HASH (optional)",
    "app_key_public": "PUBLIC_KEY_OF_TPM_APP_KEY",
    "app_key_certificate": "BASE64_ENCODED_APP_KEY_CERT_BY_AK" // OPTIONAL: certificate proving the App Key's legitimacy (can be generated by SPIRE TPM plugin)
  },
  "metadata": { "source": "SPIRE Server", "submission_type": "PoR" }
}
```

Keylime MUST verify the App Key Certificate prior to using the App Key to validate the runtime quote. Practically this means Keylime should:

1. Validate the `app_key_certificate` signature chain up to a trusted authority (AK) or verifier store.
2. Extract the `app_key_public` from the certificate and use it to verify the `quote` signature.

Using the existing endpoint for TPM App Key submissions

We recommend reusing `POST /v2.4/verify/evidence` for TPM App Key-backed submissions. To make the contract explicit for "tpm-app-key" flows, the SPIRE Server should include the additional fields below and Keylime should perform the corresponding validations. This keeps the API backward-compatible while making App Key flows explicit.

Required/additional fields (SPIRE → Keylime, using existing endpoint):

- data.nonce (string) — SPIRE challenge nonce (existing).
- data.quote (string) — base64 TPM quote (existing).
- data.app_key_public (string) — public key of the App Key that signed the quote (new, mandatory).
- data.app_key_certificate (string) — base64 DER/PEM certificate proving the App Key was issued/signed by the Host AK (new, mandatory).
- data.tpm_ak (string) — host AK public (optional) to correlate with registrar state.
- data.tpm_ek (string) — host EK key hash (optional) to correlate host identity.
- metadata.source / metadata.submission_type — identify caller and flow (existing metadata recommended).

Keylime validation steps for tpm-app-key flows:

1. Authenticate the caller via mTLS (SPIRE Server client cert mapping).
2. Validate `app_key_certificate` chain against Keylime's trusted store (AK or configured CA). If absent, Keylime can fallback to verifying `app_key_public` only, but this reduces assurance.
3. Confirm `app_key_public` matches the public key extracted from the validated certificate (if present).
4. Verify the `quote` signature using the App Key public key and validate the nonce/time fields for freshness.
5. Optionally correlate `tpm_ak`/`tpm_ek` values with Keylime's registrar to confirm host identity.
6. Return `results.attested_claims` containing verified facts (geolocation, gpu metrics, integrity) — SPIRE will run policy checks.

Operational and security notes:

- Keep `tpm_ak`/`tpm_ek` optional to ease adoption; prefer `app_key_certificate` for proof of key provenance.
- Require mTLS and client authentication for SPIRE → Keylime calls.
- Log app_key_certificate verification results and attach an audit ID in the Keylime response to allow SPIRE to track provenance.
- Include replay protection by tying `nonce` validation to server-side sessions and validating quote timestamps / PCRs where applicable.
- Consider rate-limiting and ACLs for the tpm-app-key flows since they carry higher assurance and risk.

Example (same existing endpoint, annotated for tpm-app-key):

```json
{
  "data": {
    "nonce": "e3k7h9p1d5r2n4m6...",
    "quote": "BASE64_ENCODED_TPM_QUOTE_FOR_WORKLOAD",
    "app_key_public": "PUBLIC_KEY_OF_TPM_APP_KEY",
    "app_key_certificate": "BASE64_ENCODED_APP_KEY_CERT_BY_AK",
    "tpm_ak": "PUBLIC_KEY_OF_HOSTS_AK (optional)",
    "tpm_ek": "HOST_EK_KEY_HASH (optional)"
  },
  "metadata": { "source": "SPIRE Server", "submission_type": "PoR/tpm-app-key" }
}
```


### 5) Fact retrieval result (Keylime → SPIRE Server)

Keylime validates the TPM signature and nonce and returns the host's attested facts. It does not perform policy checks — SPIRE receives the verified facts and runs its own policy evaluation before issuing SVIDs or triggering remediation.

Response (Keylime → SPIRE Server) example:

```json
{
  "results": {
    "verified": true,
    "attested_claims": {
      "geolocation": "Spain: N40.4168, W3.7038",
      "host_integrity_status": "passed_all_checks",
      "gpu_metrics_health": "healthy: utilization_15%"
    }
  }
}
```

---

### 6) Unified SVID issuance and failure enforcement

- On success, SPIRE issues a Unified SVID that contains the verified PoR/PoG claims as certificate extensions.

Success response (example):

```json
{
  "svids": [{
    "spiffe_id": "spiffe://sovereign.cloud/workload/ai-inference",
    "x509_svid": "BASE64_SIGNED_SVID_CERTIFICATE_WITH_CUSTOM_EXTENSIONS"
  }],
  "result": "SUCCESS"
}
```

- On failure (e.g. geofence mismatch) SPIRE signals the orchestration plane to remediate (example: schedule a node action in Kubernetes).

Kubernetes remediation example:

```json
{
  "target_tpm_id": "EK-Pub-Key-Hash-123",
  "reason": "Host_Attestation_Failure: Geofencing_Violation",
  "action": "drain_and_taint_node"
}
```

---
