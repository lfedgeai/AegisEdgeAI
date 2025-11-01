🔒 Trust Assumptions for Simplified Flow

This flow relies on core security assumptions to enable the simplified architectural model where the SPIRE Server orchestrates host verification independently of the SPIRE Agent/Keylime Agent communication.

Component

Trust Assumption

Purpose in Flow

Trusted Platform Module (TPM)

The TPM is the hardware root of trust, is non-compromised, and its keys (EK, AK) and attestation functions (quotes) are secure and accurate.

Anchors the security of the host and provides the cryptographic proofs for the Proof of Residency (PoR).

Keylime & SPIRE (Trusted Components)

Keylime Verifier and SPIRE Server are both secure, cannot be compromised, and have a trusted, mutually authenticated (mTLS) communication channel.

Simplification: Allows the SPIRE Server to act as the sole orchestrator, delegating host verification to Keylime and integrating the results into the SVID.

Keylime's Attestation Data

The Keylime system is trusted to securely and accurately gather and persist the hardware-rooted geolocation and GPU metrics data, making it available for the Verifier to access during the verification check.

Provides the verifiable host health, integrity, and location data necessary for the Proof of Geofencing (PoG) claim.

🌊 Simplified Zero-Trust Sovereign AI: Unified SVID Flow

This flow details the complete, step-by-step process for the SPIRE Agent to obtain a unified SVID (Proof of Geofencing/Residency) that combines workload identity (PoR) with verified host state (PoG).

1. Workload Identity Initiation

The SPIRE Agent requests a challenge (nonce/timestamp) from the SPIRE Server and supplies its workload metadata (code hash) to start the cryptographic binding process.

Component

Action

API Call (Conceptual)

SPIRE Agent

Supplies its code hash and requests a nonce and timestamp from the SPIRE Server.

Request: GET /v1/attestation/start

SPIRE Server

Generates a fresh, random nonce and returns it with a server timestamp.

Response (JSON):



```json

{





"nonce": "e3k7h9p1d5r2n4m6...",





"server_timestamp": 1730424000





}






### 2. Proof of Residency (PoR) Generation

The SPIRE Agent uses its local TPM plugin to generate a cryptographic proof by signing the server's challenge data.

| Component | Action | API Call (Conceptual) |
| :--- | :--- | :--- |
| **SPIRE Agent** | Connects to its local TPM plugin, supplying the nonce, timestamp, and its code hash. | **Internal Call:** `SPIRE_TPM_PLUGIN.sign_challenge(nonce, server_timestamp, code_hash)` |
| **SPIRE Agent TPM Plugin** | Signs the payload (`nonce`, `timestamp`, `code_hash`) using the TPM App Key (PoR proof). | **Response (JSON):**<br>```json
{
  "tpm_signed_attestation": "BASE64_ENCODED_TPM_QUOTE_FOR_WORKLOAD",
  "app_key_public": "PUBLIC_KEY_OF_TPM_APP_KEY",
  "workload_code_hash": "a2b3c4d5e6f7..."
}
``` |

### 3. Submitting Proof of Residency

The SPIRE Agent returns the signed PoR proof to the SPIRE Server.

| Component | Action | API Call (Conceptual) |
| :--- | :--- | :--- |
| **SPIRE Agent** | Returns the signed nonce, timestamp, and code hash payload to the server. | **Request:** `POST /v1/attestation/submit_por_proof` |

### 4. Orchestrating Host Verification (PoG)

The SPIRE Server verifies the PoR proof and then initiates the critical host verification by forwarding the signed TPM attestation to the Keylime Verifier.

| Component | Action | API Call (Conceptual) |
| :--- | :--- | :--- |
| **SPIRE Server** | 1. Verifies the PoR proof's signature. 2. **CRITICAL:** Sends the received signed TPM attestation to the Keylime Verifier to confirm host integrity and location. | **Internal Call (SPIRE Server $\rightarrow$ Keylime Verifier):** `POST /v1/verify_tpm_host_status` |
| **Keylime Verifier** | Receives the signed attestation and the workload's public key hash. Verifies the attestation against its knowledge of the host's TPM, measured boot state, and policy (including geolocation and GPU metrics). | **Request (JSON):**<br>```json
{
  "host_tpm_id_hash": "EK-Pub-Key-Hash-123", // Keylime uses this to identify the host
  "tpm_signed_attestation": "BASE64_ENCODED_TPM_QUOTE_FOR_WORKLOAD", // The PoR proof
  "challenge_nonce": "e3k7h9p1d5r2n4m6...",
  "location_policy": "EU_Sovereign_Zone_1"
}
``` |

### 5. Proof of Geofencing (PoG) Verification Result

The Keylime Verifier completes its checks and returns the full verification status, along with the attested claims (which are independently verified against the host's hardware data).

| Component | Action | API Call (Conceptual) |
| :--- | :--- | :--- |
| **Keylime Verifier** | Returns the verification result (Success/Failure) and the attested host claims. | **Response (JSON):**<br>```json
{
  "verification_status": "SUCCESS",
  "attested_claims": {
    "geolocation": "Spain: N40.4168, W3.7038", // PoG Claim
    "host_integrity_status": "passed_all_checks",
    "gpu_metrics_health": "healthy: utilization_15%"
  }
}
``` |

### 6. Unified SVID Issuance and Failure Enforcement

The SPIRE Server processes the final outcome and issues the complete unified identity or enforces failure policies.

| Component | Action | API Call (Conceptual) |
| :--- | :--- | :--- |
| **SPIRE Server** | **(SUCCESS)**: Issues the **unified SVID**. The SVID claims combine the PoR proof and the Keylime-verified PoG data, signed by SPIRE. | **Response (JSON - Unified SVID):**<br>```json
{
  "result": "SUCCESS",
  "unified_svid": "BASE64_SIGNED_SVID_JWT_OR_CERT",
  "issued_claims": {
    "spiffe_id": "spiffe://sovereign.cloud/workload/ai-inference",
    "workload_hash": "a2b3c4d5e6f7...",
    "tpm_nonce_signed": true, // TPM attested SPIRE agent code hash/nonce/timestamp
    "host_location": "Spain", // TPM attested geolocation/gpu metrics
    "gpu_status": "healthy"
  }
}
``` |
| **SPIRE Server** | **(FAILURE)**: Returns failure to the agent and sends a notification to Kubernetes to remove the host from scheduling. | **Internal Call (SPIRE $\rightarrow$ K8s):** `POST /v1/nodes/schedule_action` |
| **Kubernetes** | Executes the failure policy based on the host's identity (mapped via TPM EK public key). | **Request (JSON):**<br>```json
{
  "target_tpm_id": "EK-Pub-Key-Hash-123",
  "reason": "Host_Attestation_Failure: Geofencing_Violation",
  "action": "drain_and_taint_node" // Remove host from scheduling list
}
``` |
