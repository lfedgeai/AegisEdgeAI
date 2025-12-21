# Upstream Merge Roadmap: Unified Identity

## Executive Summary
The "Unified Identity" feature introduces a symbiotic relationship between SPIRE and Keylime. The current "Hybrid Cloud PoC" implements these changes via a **Fork & Patch** pattern. To merge this upstream, we must separate these into distinct Feature Requests (for Keylime) and Custom Plugins (for SPIRE).

## Summary Checklist
| Component | Task | Strategy | Complexity | Owner |
| :--- | :--- | :--- | :--- | :--- |
| **Keylime Agent** | **Task 1**: Add `delegated_certifier` endpoint | **Feature Request (Core)** | Medium | Rust Team |
| **Keylime Agent** | **Task 2**: Add `attested_geolocation` API | **Separate Optional Endpoint** | Medium | Rust Team |
| **Keylime Verifier** | **Task 3**: Add Verification API & Cleanup | **New API + Cleanup** | Medium | Python Team |
| **SPIRE Server** | **Task 4**: Create `spire-plugin-unified-identity` (Validator) | **Separate Custom Plugin** | High | Go Team |
| **SPIRE Agent** | **Task 5**: Create `spire-plugin-unified-identity` (Collector) | **Separate Custom Plugin** | High | Go Team |
| **SPIRE Creds** | **Task 6**: Config `CredentialComposer` to inject claims | **Standard Configuration** | Low | Go Team |

---

## Task Breakdown

### Task 1: "Delegated Certifier" Endpoint (Keylime Agent)
*Allow the Keylime Agent to sign external keys (like SPIRE's App Key) using the TPM.*

*   **The Problem**: SPIRE Agent generates a "TPM App Key" for mTLS. It needs this key to be signed by the TPM's Attestation Key (AK) so the server can trust it.
*   **The PoC "Hack"**: A custom HTTP endpoint `/certify_app_key` was added to `delegated_certification_handler.rs` in the Rust Agent. It blindly signs keys if a specific file exists.
*   **The Upstream Solution**: **Feature Request: "Delegated Credential Issuance"**.
    *   Propose a formal, configurable API endpoint in `rust-keylime` that allows signing external keys.
    *   Must feature strict authentication (or be disabled by default) to prevent abuse.

### Task 2: "Attested Geolocation" Optional API (Keylime Agent)
*Add a separate, optional endpoint for retrieving geolocation bound to the device.*

*   **The Problem**: The standard Keylime protocol only returns the TPM Quote and PCRs. Currently, "Unified Identity" modifies this core response payload to inject `geolocation`, which breaks schema compatibility.
*   **The PoC "Hack"**: The `KeylimeQuote` struct was modified to include an optional `geolocation` field.
*   **The Upstream Solution**: **Separate Optional API**.
    *   Instead of modifying the core `/identity` or `/integrity` endpoints, add a **new optional endpoint** (e.g., `GET /v2/agent/attested_geolocation`).
    *   This endpoint returns the signed geolocation data (or a quote including it).
    *   *Benefit*: Allows clients who care about "Sovereign Identity" to fetch it, while keeping the core Keylime protocol clean and standard.

### Task 3: Add Verification API & Cleanup (Keylime Verifier)
*Enable "Attestation as a Service" for SPIRE and cleanup dead code.*

*   **The Request**: SPIRE needs to check the TPM Quote. It calls the custom `/verify/evidence` endpoint.
*   **The Problem**: This endpoint is actively used by SPIRE but contains dead/legacy code for "Mobile Sensor verification".
*   **The Upstream Solution**:
    1.  **Upstream `/verify/evidence`**: Propose this generic endpoint to Keylime. It allows external systems (like SPIRE) to submit a Quote and get a verification result (Stateless/On-demand Attestation).
    2.  **Remove Legacy Logic**: Strip out the `_verify_mobile_sensor` calls from this handler. The handler should *only* verify the Trusted Platform claims (TPM/PCRs) and return the raw geolocation data to the caller (SPIRE) without judging it.

### Task 4: "Validator" Node Attestor (SPIRE Server)
*Validate the Unified Identity evidence on the SPIRE Server.*

*   **The Problem**: SPIRE Server doesn't know how to talk to Keylime or validate this specific "SovereignAttestation" payload.
*   **The PoC "Hack"**: Core file `service.go` was modified (`AttestAgent` method) to manually parse the custom payload and call the Keylime Client.
*   **The Upstream Solution**: **`spire-plugin-unified-identity` (Server Side)**.
    *   Move all the logic from `service.go` into a custom **Node Attestor Plugin**.
    *   This plugin receives the payload, calls the Keylime Verifier (Task 3 API), and returns the successful SPIFFE ID to the Core.

### Task 5: "Collector" Node Attestor (SPIRE Agent)
*Collect the Unified Identity evidence on the SPIRE Agent.*

*   **The Problem**: SPIRE Agent needs to orchestrate the complex dance of "Get App Key -> Sign with Keylime -> Get Quote -> Send to Server".
*   **The PoC "Hack"**: Core files `agent.go` and `client.go` were heavily patched to perform this orchestration before the standard SVID rotation even starts.
*   **The Upstream Solution**: **`spire-plugin-unified-identity` (Agent Side)**.
    *   Move the orchestration logic into a custom **Node Attestor Plugin**.
    *   The plugin handles the communication with the local Keylime Agent (Task 1 & 2) and packages the proof into a standard completion payload.

### Task 6: "SPIRE Creds" (Credential Injection)
*Inject Custom Claims (Geolocation, Integrity) into the X.509 Certificate.*

*   **The Problem**: By default, SPIRE only puts the **SPIFFE ID** into the certificate. It ignores extra metadata.
*   **The PoC "Hack"**: Modified the Core SPIRE CA Code (`ca.go`) to force-inject these new fields into the X.509 certificate.
*   **The Upstream Solution**: **`CredentialComposer`**.
    *   Use the standard **Credential Composer Plugin Interface** available in modern SPIRE.
    *   Configure it (or write a tiny plugin) to listen for the attributes verified in Task 4 and add them as standard X.509 Extensions.
