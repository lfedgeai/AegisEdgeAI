# Sovereign Unified Identity for Workloads

This document describes the complete end-to-end architecture flow for generating a SPIRE Agent Sovereign Unified SVID with TPM attestation and geolocation claims. The flow spans multiple components using different transport mechanisms and data formats. The workload SVID has the full certificate chain and claims, including the TPM attestation and geolocation claims, from the SPIRE Agent Sovereign Unified SVID.

## Interface Classification

**Existing Interfaces (Standard SPIRE/Keylime):**
- `spire-agent → spire-server`: Protobuf gRPC over mTLS (standard SPIRE)
- `keylime-agent → keylime-verifier`: JSON over HTTPS with mTLS (standard Keylime)

**New Interfaces (Unified Identity Extensions):**

- `spire-server → keylime-verifier`: JSON over HTTPS with mTLS (Phase 2/3 addition)
- `spire-agent → tpm-plugin-server`: JSON over UDS (Phase 3)
- `tpm-plugin-server → keylime-agent`: JSON over UDS (Phase 3)

---

## Architecture Overview

### Component Architecture Diagram

The following diagram shows the component relationships and clarifies the distinction between the TPM Plugin Gateway (Go) and TPM Plugin Server (Python):

```
┌─────────────────────────────────────────────────────────────────┐
│                    SPIRE Agent (Go Process)                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  TPM Plugin Gateway (Go)                                 │  │
│  │  - Bridge between SPIRE Agent and TPM Plugin Server       │  │
│  │  - Communicates via HTTP/UDS                              │  │
│  │  - Location: pkg/agent/tpmplugin/tpm_plugin_gateway.go   │  │
│  └───────────────┬───────────────────────────────────────────┘  │
└───────────────────┼───────────────────────────────────────────────┘
                    │
                    │ JSON over UDS
                    │ (unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock)
                    │
┌───────────────────▼───────────────────────────────────────────────┐
│              TPM Plugin Server (Python Process)                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  - Generates App Key on startup (Step 3)                  │  │
│  │  - Provides App Key public and context via /get-app-key  │  │
│  │  - Requests App Key certificate via delegated cert (Step 4)│  │
│  │  - Uses tpm2-tools for TPM operations                     │  │
│  │  - Note: Quote generation removed (handled by Keylime)     │  │
│  │  - Location: tpm-plugin/tpm_plugin_server.py              │  │
│  └───────────────┬───────────────────────────────────────────┘  │
└───────────────────┼───────────────────────────────────────────────┘
                    │
                    │ JSON over UDS
                    │ (unix:///tmp/keylime-agent.sock)
                    │
┌───────────────────▼───────────────────────────────────────────────┐
│            rust-keylime Agent (Rust Process)                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  - Provides delegated certification API                   │  │
│  │  - Uses host TPM AK to certify App Key                    │  │
│  │  - UDS-only communication (network listener disabled)     │  │
│  │  - Location: rust-keylime/keylime-agent/                 │  │
│  └───────────────┬───────────────────────────────────────────┘  │
└───────────────────┼───────────────────────────────────────────────┘
                    │
                    │ TPM Operations
                    │
┌───────────────────▼───────────────────────────────────────────────┐
│                        TPM Hardware                              │
│  - App Key (persisted at handle 0x8101000B)                      │
│  - Attestation Key (AK)                                          │
│  - Endorsement Key (EK)                                          │
└───────────────────────────────────────────────────────────────────┘
```

### Component Naming Clarification

To avoid confusion between Go and Python components:

1. **TPM Plugin Gateway (Go)**
   - **Location:** `spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go`
   - **Type:** `TPMPluginGateway`
   - **Purpose:** Bridge/gateway that runs inside SPIRE Agent (Go process)
   - **Role:** Client library that communicates with the Python server

2. **TPM Plugin Server (Python)**
   - **Location:** `tpm-plugin/tpm_plugin_server.py`
   - **Purpose:** HTTP/UDS server that handles TPM operations
   - **Role:** Actual plugin that performs TPM operations using `tpm2-tools`

**Key Distinction:**
- The **Gateway** is a Go library embedded in SPIRE Agent
- The **Server** is a separate Python process that handles TPM operations
- The Gateway communicates with the Server via HTTP over UDS

---

## Component Flow: SPIRE Agent Sovereign SVID (Periodic Refresh)

The SPIRE Agent periodically refreshes its own Sovereign SVID (approximately every 30 seconds or when the SVID is about to expire). This flow incorporates TPM attestation, host integrity checks, and geolocation to create a unified identity that binds workload identity to host hardware attestation.

### Flow Overview

```
┌─────────────────┐
│  SPIRE Agent    │
│  (Periodic)     │
└────────┬────────┘
         │
         │ Step 1: Initiate SVID Renewal
         │ Step 2: Request Nonce
         ▼
┌─────────────────┐
│  SPIRE Server   │
└────────┬────────┘
         │
         │ Step 3-4: TPM Operations (with nonce)
         │ (via TPM Plugin Gateway → TPM Plugin Server)
         ▼
┌─────────────────┐     ┌─────────────────┐
│  TPM Plugin     │────▶│ Keylime Agent   │
│  Server (Python)│     │  (Rust)         │
└─────────────────┘     └─────────────────┘
         │
         │ Step 5-6: Host Attestation
         ▼
┌─────────────────┐
│ Keylime Agent   │
│  Plugins        │
└────────┬────────┘
         │
         │ Step 7-9: Verification
         ▼
┌─────────────────┐     ┌─────────────────┐
│  SPIRE Server   │────▶│ Keylime Verifier│
└────────┬────────┘     └────────┬────────┘
         │                        │
         │                        │ Step 10a: Get Geolocation
         │                        │ (PCR 17 from Quote)
         │                        ▼
         │                ┌─────────────────┐
         │                │ Keylime Agent   │
         │                │  (Geolocation)  │
         │                └────────┬────────┘
         │                        │
         │                        │ (Quote with PCR 17)
         │                        ▼
         │                ┌─────────────────┐
         │                │ Keylime Verifier│
         │                │  (Fact Provider)│
         │                └─────────────────┘
         │
         │ Step 10: Return Unified SVID
         ▼
┌─────────────────┐
│  SPIRE Agent    │
│  (SVID Cached)  │
└─────────────────┘
```

### Detailed Step-by-Step Flow

#### Step 1: SPIRE Agent Initiates SVID Renewal

**Component:** SPIRE Agent (SVID Rotator)

**Trigger:**
- Periodic rotation (default: ~30 seconds before expiration)
- SVID expiration detected
- Manual rotation request

**Action:**
- SPIRE Agent's `svid/rotator.go` detects that rotation is needed
- Calls `RenewSVID()` or `reattest()` depending on whether reattestation is required
- Generates a new key pair and CSR for the agent SVID

**Code Location:**
- `pkg/agent/svid/rotator.go::rotateSVIDIfNeeded()`
- `pkg/agent/svid/rotator.go::rotateSVID()`
- `pkg/agent/svid/rotator.go::reattest()`

---

#### Step 2: SPIRE Agent Requests Nonce from SPIRE Server

**Component:** SPIRE Agent → SPIRE Server

**Status:** ✅ Existing (Standard SPIRE)

**Transport:** mTLS over TCP

**Protocol:** gRPC Streaming API (Protobuf)

**Port:** SPIRE Server port (typically 8081)

**RPC Method:** `AttestAgent(stream AttestAgentRequest) returns (stream AttestAgentResponse)`

**Action:**
- SPIRE Agent initiates attestation request to SPIRE Server
- SPIRE Server generates a cryptographically secure random nonce (32 bytes, hex-encoded)
- SPIRE Server returns the nonce as part of the challenge in the `AttestAgentResponse`
- The nonce is used to ensure freshness of the TPM Quote

**Request Format (Protobuf):**
```protobuf
// AttestAgentRequest (streaming gRPC)
message AttestAgentRequest {
  message Params {
    spire.api.types.AttestationData data = 1;  // Join token or existing agent identity
  }
  oneof step {
    Params params = 1;              // Initial attestation request
    bytes challenge_response = 2;    // Challenge response (if needed)
  }
}

// AttestationData (nested in Params)
message AttestationData {
  string type = 1;      // "join_token" for initial attestation
  bytes payload = 2;     // Join token string (UTF-8 encoded)
}
```

**Response Format (Protobuf):**
```protobuf
// AttestAgentResponse (streaming gRPC)
message AttestAgentResponse {
  oneof step {
    Result result = 1;
    bytes challenge = 2;  // Contains nonce (hex-encoded, 64 characters)
  }
}
```

**Nonce Format:**
- **Length:** 32 bytes (64 hex characters)
- **Encoding:** Hex string (e.g., `a010d512540d60c18ec1d3942978ff4453f465ce64eddfdd232facfe670a0d2b`)
- **Purpose:** Ensures TPM Quote freshness and prevents replay attacks

**Authentication:** TLS client certificate authentication, SPIRE trust domain validation

**Code Location:**
- Client: `pkg/agent/client/client.go::RenewSVID()`
- Server: `pkg/server/api/agent/v1/service.go::AttestAgent()`
- `pkg/server/attestation/attestation.go` (nonce generation)

**Note:** In the current implementation, the nonce may be generated locally by the agent as a fallback, but the proper flow requires the nonce to come from the SPIRE Server challenge to ensure freshness and prevent replay attacks.

---

#### Step 3: Generate TPM App Key (Automatic on Startup)

**Component:** SPIRE TPM Plugin (Internal)

**Status:** 🆕 New (Phase 3)

**Transport:** N/A (Internal TPM Plugin operation)

**Protocol:** N/A (Internal TPM Plugin operation)

**Port/Path:** N/A (Internal TPM Plugin operation)

**Implementation:** The TPM Plugin automatically generates the App Key during startup and stores it for future use. No API endpoint is required.

**Action:**
- TPM Plugin generates a new App Key using TPM on startup (if not already exists)
- App Key public key and context are stored in the work directory
- Stored values are used automatically in subsequent operations (Step 4 and Step 5)

**Storage:**
- **App Key Public Key:** Stored in memory and/or work directory
- **App Key Context:** 
  - Initially stored at `/tmp/spire-data/tpm-plugin/app.ctx` (or configured work directory)
  - After persistence, stored as persistent handle (e.g., `0x8101000B`) in TPM
  - The plugin tracks both the file path and persistent handle for compatibility

**Code Location:**
- Server: `tpm-plugin/tpm_plugin_server.py` (startup initialization)

---

#### Step 4: Get App Key and Request Certificate

**Component:** SPIRE Agent → SPIRE TPM Plugin → rust-keylime Agent

**Status:** 🆕 New (Phase 3)

**Transport:** JSON over UDS (Phase 3)

**Protocol:** JSON REST API

**Port/Path:** UDS socket (default: `/tmp/spire-data/tpm-plugin/tpm-plugin.sock`)

**Action:**
- SPIRE Agent requests App Key public key and context from TPM Plugin
- SPIRE Agent requests App Key certificate from TPM Plugin (which forwards to rust-keylime Agent)
- TPM Plugin uses the stored App Key public key and context (from Step 3)
- TPM Plugin forwards certificate request to rust-keylime Agent over UDS
- rust-keylime Agent uses the host's TPM AK (Attestation Key) to certify the App Key
- Returns a base64-encoded certificate containing TPM2_Certify output

**Request Format 1: Get App Key (JSON over UDS):**
```json
POST /get-app-key
Content-Type: application/json

{}
```

**Response Format 1: Get App Key (JSON):**
```json
{
  "status": "success",
  "app_key_public": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
  "app_key_context": "0x8101000B"  // or file path
}
```

**Request Format 2: Request Certificate (JSON over UDS):**
```json
POST /request-certificate
Content-Type: application/json

{
  "app_key_public": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
  "app_key_context_path": "0x8101000B",  // or file path
  "endpoint": "unix:///tmp/keylime-agent.sock"  // optional
}
```

**Response Format 2: Request Certificate (JSON):**
```json
{
  "status": "success",
  "app_key_certificate": "eyJhcHBfa2V5X3B1YmxpYyI6Ii0tLS0tQkVHSU4gUFVCTElDIEtFWS0tLS0tXG5NSUlCSWpBTkJna3Foa2l..."
}
```

**Note:** The `app_key_public` field is **required** and is used by the SPIRE Agent to build the `SovereignAttestation` and is required by the Keylime Verifier for verification.

**Note:** The `app_key_context` is automatically retrieved from the stored App Key context (generated in Step 3). The TPM Plugin uses the stored App Key public key and context for certificate requests.

**Certificate Format:**
The certificate is a base64-encoded JSON structure containing TPM2_Certify output:
```json
{
  "app_key_public": "-----BEGIN PUBLIC KEY-----\n...",
  "certify_data": "<base64-encoded-attestation>",
  "signature": "<base64-encoded-signature>",
  "hash_alg": "sha256",
  "format": "phase2_compatible"
}
```

**Delegated Certification Flow:**
- TPM Plugin forwards certificate request to rust-keylime Agent over UDS
- rust-keylime Agent uses the host's TPM AK (Attestation Key) to certify the App Key
- Certificate is returned to SPIRE Agent via TPM Plugin

**Code Location:**
- Client: `pkg/agent/tpmplugin/tpm_plugin_gateway.go::BuildSovereignAttestation()` → calls `/get-app-key` and `/request-certificate`
- Server: `tpm-plugin/tpm_plugin_server.py::handle_get_app_key()` and `handle_request_certificate()`
- Delegated Cert Client: `tpm-plugin/delegated_certification.py::DelegatedCertificationClient::request_certificate()`
- Keylime Agent Server: `rust-keylime/keylime-agent/src/delegated_certification_handler.rs::certify_app_key()`

---

#### Step 5: Keylime Verifier Requests TPM AK Quote from rust-keylime Agent

**Component:** Keylime Verifier → rust-keylime Agent

**Status:** 🆕 New (Phase 3)

**Transport:** HTTP over TCP/IP

**Protocol:** JSON REST API

**Port/Path:** HTTP endpoint (default: `http://<agent_ip>:9002`)

**Endpoints:**
- Keylime Verifier → rust-keylime Agent: `GET /v1.0/quotes/identity?nonce=<nonce>`

**Action:**
- Keylime Verifier requests TPM AK quote directly from rust-keylime Agent
- rust-keylime Agent generates quote using TPM AK (Attestation Key)
- Quote includes PCR 17 with geolocation data (extended during quote generation)
- Nonce from SPIRE Server is embedded in the quote's `extraData` field
- Quote format: Base64-encoded TPM quote structure

**Request Format (HTTP GET):**
```
GET /v1.0/quotes/identity?nonce=<hex-nonce-from-spire-server>
Host: <agent_ip>:9002
```

**Response Format (JSON):**
```json
{
  "result": "SUCCESS",
  "data": {
    "quote": "<base64-encoded-tpm-quote>",
    "hash_alg": "sha256",
    "enc_alg": "sha256",
    "sign_alg": "rsassa",
    "geolocation": "Spain:Madrid:Madrid:40.4168:-3.7038",
    "pubkey": "-----BEGIN PUBLIC KEY-----\n..."
  }
}
```

**Note:** The quote is generated by rust-keylime Agent using the TPM AK (not App Key). This ensures that geolocation detection logic in the rust-keylime Agent is properly utilized, as it extends geolocation into PCR 17 during quote generation.

**Geolocation in PCR 17:**
- rust-keylime Agent detects geolocation via sensors (GNSS, mobile sensor, etc.)
- Geolocation is extended into PCR 17 during quote generation
- Quote mask includes PCR 17 (bit 17 = 0x20000)
- Geolocation string is returned in the quote response

**Code Location:**
- Verifier: `keylime/keylime/cloud_verifier_tornado.py::_tpm_app_key_verify()` → requests quote from agent
- Agent: `rust-keylime/keylime-agent/src/quotes_handler.rs::identity()` → generates quote with PCR 17

---

#### Step 6: Keylime Verifier Validates App Key Certificate Using TPM AK from Database

**Component:** Keylime Verifier (Internal)

**Status:** 🆕 New (Phase 3)

**Action:**
- Keylime Verifier retrieves TPM AK from its own database
- Uses stored TPM AK to verify App Key certificate signature
- Certificate was signed by rust-keylime Agent using the host's TPM AK
- Verifier validates that the certificate signature matches the stored TPM AK

**TPM AK Lookup:**
- Verifier looks up agent by IP/port (from request or agent database)
- Retrieves `ak_tpm` field from `VerfierMain` table
- Uses this stored TPM AK to verify the App Key certificate

**Code Location:**
- `keylime/keylime/cloud_verifier_tornado.py::_tpm_app_key_verify()` → looks up TPM AK from database
- `keylime/keylime/app_key_verification.py::validate_app_key_certificate()` → verifies certificate signature

---

#### Step 7: Keylime Agent Collects Host Attestation Data

**Component:** Keylime Agent (Internal)

**Action:**
- Keylime Agent collects current host state:
  - **Geolocation:** Via geolocation plugin (GNSS, mobile sensor, etc.)
  - **GPU Status:** Via GPU integrity plugin (utilization, memory, health)
  - **Host Integrity:** PCR measurements, IMA policy checks

**Note:** This step happens asynchronously within Keylime Agent. The data is prepared for the verification request in Step 8.

**Code Location:**
- `rust-keylime/keylime-agent/src/` (various plugins)

---

#### Step 7: Assemble SovereignAttestation

**Component:** SPIRE Agent (Internal)

**Action:**
- SPIRE Agent assembles the `SovereignAttestation` Protobuf message:
  - `tpm_signed_attestation`: TPM Quote from Step 4
  - `app_key_public`: App Key public key (PEM) from Step 3
  - `app_key_certificate`: Certificate from Step 5 (base64-encoded)
  - `challenge_nonce`: **Nonce from Step 2 (SPIRE Server)**
  - `workload_code_hash`: Optional workload hash

**SovereignAttestation Protobuf Format:**
```protobuf
// SovereignAttestation (from spire.api.types)
message SovereignAttestation {
  string tpm_signed_attestation = 1;  // Base64-encoded TPM Quote (format: r<msg>:<sig>:<pcrs>)
  string app_key_public = 2;          // PEM-encoded App Key public key
  bytes app_key_certificate = 3;      // Base64-encoded certificate (optional, TPM2_Certify output)
  string challenge_nonce = 4;         // Hex-encoded nonce from SPIRE Server
  string workload_code_hash = 5;      // Optional workload code hash (e.g., "sha256:...")
}
```

**Code Location:**
- `pkg/agent/tpmplugin/tpm_plugin_gateway.go::BuildSovereignAttestation()`
- `pkg/agent/client/client.go::BuildSovereignAttestation()`

---

#### Step 8: Send Attestation Request to SPIRE Server

**Component:** SPIRE Agent → SPIRE Server

**Status:** ✅ Existing (Standard SPIRE) - Extended with SovereignAttestation

**Transport:** mTLS over TCP

**Protocol:** gRPC Streaming API (Protobuf)

**Port:** SPIRE Server port (typically 8081)

**RPC Method:** `AttestAgent(stream AttestAgentRequest) returns (stream AttestAgentResponse)`

**Action:**
- SPIRE Agent sends `AttestAgentRequest` with:
  - `AttestationData`: Join token or existing agent identity
  - `AgentX509SVIDParams`: CSR + `SovereignAttestation`

**Request Format (Protobuf):**
```protobuf
// AttestAgentRequest (streaming gRPC)
message AttestAgentRequest {
  message Params {
    spire.api.types.AttestationData data = 1;
    AgentX509SVIDParams params = 2;  // Contains SovereignAttestation
  }
  oneof step {
    Params params = 1;              // Initial attestation request
    bytes challenge_response = 2;    // Challenge response (if needed)
  }
}

// AttestationData (nested in Params)
message AttestationData {
  string type = 1;      // "join_token" for initial attestation
  bytes payload = 2;     // Join token string (UTF-8 encoded)
}

// AgentX509SVIDParams (nested in Params)
message AgentX509SVIDParams {
  bytes csr = 1;  // Certificate Signing Request (DER-encoded X.509 CSR)
  spire.api.types.SovereignAttestation sovereign_attestation = 2;  // Optional
}
```

**Authentication:** TLS client certificate authentication, SPIRE trust domain validation

**Code Location:**
- Client: `pkg/agent/client/client.go::RenewSVID()`
- Server: `pkg/server/api/agent/v1/service.go::AttestAgent()`

**Note:** This is the standard SPIRE attestation interface. The Sovereign SVID flow extends this by including `SovereignAttestation` in the `AgentX509SVIDParams` field.

---

#### Step 9: SPIRE Server Verifies Workload Attestation

**Component:** SPIRE Server (Internal)

**Action:**
- SPIRE Server validates the agent's workload attestation:
  - Verifies join token or existing agent identity
  - Validates CSR signature
  - Checks agent registration entry
  - **Validates that the nonce in SovereignAttestation matches the nonce issued in Step 2**

**Code Location:**
- `pkg/server/api/agent/v1/service.go::AttestAgent()`
- `pkg/server/attestation/attestation.go`

---

#### Step 10: SPIRE Server Verifies Host Attestation via Keylime Verifier

**Note:** This step includes:
- Step 5: Keylime Verifier requests TPM AK quote from rust-keylime Agent
- Step 6: Keylime Verifier validates App Key certificate using TPM AK from database
- Step 10a: Geolocation retrieval (integrated into quote request)

**Note:** This step includes Step 10a (geolocation retrieval) as part of the verification process.

**Component:** SPIRE Server → Keylime Verifier

**Status:** 🆕 New (Phase 2/3 Addition)

**Transport:** mTLS over HTTPS

**Protocol:** JSON REST API

**Port:** localhost:8881

**Endpoint:** `POST /v2.4/verify/evidence`

**TLS Configuration:**
- Self-signed certificates for testing (`InsecureSkipVerify: true`)
- Production: CA certificate validation required
- Client certificate authentication (mTLS)

**Action:**
- SPIRE Server extracts `SovereignAttestation` from the request
- Sends verification request to Keylime Verifier
- Keylime Verifier:
  - **Retrieves TPM AK from its own database** (using agent IP/port or other identifiers)
  - **Validates App Key certificate using TPM AK from database** (verifies TPM2_Certify signature)
  - Requests TPM AK quote from rust-keylime Agent (Step 5)
  - Verifies TPM Quote signature using TPM AK (from database)
  - **Extracts nonce from quote's `extraData` field and validates it matches the nonce from Step 2**
  - **Verifies PCR 17 contains geolocation hash (TPM-attested geolocation)**
  - Retrieves attested claims (geolocation, host integrity, GPU metrics) via fact provider

**Note:** The geolocation is TPM-attested via PCR 17 extension, but the actual geolocation string is retrieved separately (see Step 10a below).

**Request Format (JSON):**
```json
{
  "type": "tpm-app-key",
  "data": {
    "nonce": "a010d512540d60c18ec1d3942978ff4453f465ce64eddfdd232facfe670a0d2b",
    "quote": "r<base64-message>:<base64-signature>:<base64-pcrs>",
    "hash_alg": "sha256",
    "app_key_public": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
    "app_key_certificate": "<base64-encoded-certificate>",
    "tpm_ak": "",
    "tpm_ek": ""
  },
  "metadata": {
    "source": "SPIRE Server",
    "submission_type": "PoR/tpm-app-key",
    "audit_id": ""
  }
}
```

**Response Format (JSON):**
```json
{
  "results": {
    "verified": true,
    "verification_details": {
      "app_key_certificate_valid": true,
      "app_key_public_matches_cert": true,
      "quote_signature_valid": true,
      "nonce_valid": true,
      "timestamp": 1701234567
    },
    "attested_claims": {
      "geolocation": "Spain: N40.4168, W3.7038",
      "host_integrity_status": "passed_all_checks",
      "gpu_metrics_health": {
        "status": "healthy",
        "utilization_pct": 45.2,
        "memory_mb": 8192
      }
    },
    "audit_id": "0eebf40b-c9b8-497a-80d6-c09976eb5091"
  }
}
```

> **Note:** If no mobile/GNSS sensors or GPU telemetry sources are detected, the
> corresponding values in `attested_claims` are returned as `null` and no longer
> fall back to synthetic defaults.

**HTTP Headers:**
```
Content-Type: application/json
```

**Error Responses:**
- `400 Bad Request`: Missing required fields
- `422 Unprocessable Entity`: Quote verification failed
- `500 Internal Server Error`: Server error

**Code Location:**
- Client: `pkg/server/keylime/client.go::VerifyEvidence()`
- Server: `keylime/cloud_verifier_tornado.py::_tpm_app_key_verify()`

---

#### Step 10a: Keylime Verifier Retrieves TPM-Attested Geolocation from Keylime Agent

**Parent Step:** Step 10 (SPIRE Server Verifies Host Attestation via Keylime Verifier)

**Component:** Keylime Verifier → Keylime Agent

**Status:** 🆕 New (Phase 3 Addition)

**Transport:** HTTP over localhost (or HTTPS with mTLS if enabled)

**Protocol:** JSON REST API

**Port:** localhost:9002 (rust-keylime Agent)

**Endpoint:** `GET /v2.2/quotes/integrity` (with PCR 17 in mask)

**Timing:** This step occurs as part of Step 10 when the Keylime Verifier needs to retrieve and verify geolocation claims. It happens during the standard Keylime attestation flow when the Verifier requests a quote from the Agent. The geolocation is embedded in PCR 17 of the quote response.

**Action:**
- Keylime Verifier requests a TPM Quote from Keylime Agent
- Keylime Agent:
  1. Gets current geolocation (from sensors or `KEYLIME_AGENT_GEOLOCATION`; if unavailable, records `"none"`)
  2. Hashes geolocation with nonce and timestamp
  3. Extends the hash into PCR 17
  4. Generates TPM Quote including PCR 17
  5. Returns quote with PCR 17 containing geolocation attestation

**Request Format (HTTP GET):**
```
GET /v2.2/quotes/integrity?nonce=<nonce>&mask=<mask>&partial=1&ima_ml_entry=0
```

**Query Parameters:**
- `nonce`: Cryptographic nonce for quote freshness
- `mask`: PCR mask (must include bit 17 = 0x20000 for PCR 17)
- `partial`: Whether to include public key (0 = include, 1 = exclude)
- `ima_ml_entry`: IMA measurement list entry number

**Response Format (JSON):**
```json
{
  "results": {
    "quote": "<base64-encoded-tpm-quote>",
    "hash_alg": "sha256",
    "enc_alg": "ecc",
    "sign_alg": "ecdsa",
    "pubkey": "<pem-encoded-public-key>",
    "pcrs": {
      "17": "<pcr-17-digest-hex>"
    }
  }
}
```

**Geolocation Extraction:**
- The geolocation string itself is **not directly extractable** from PCR 17 (it's hashed)
- The Keylime Verifier retrieves the actual geolocation string via:
  1. **Agent metadata** in Verifier database (if agent is registered)
  2. **Fact provider** (`fact_provider.py::get_attested_claims()`) which:
     - Checks verifier database for agent metadata with geolocation
     - Falls back to fact store (if host identified by EK/AK)
     - Returns `null` when no sensor data or stored metadata is available (no synthetic GNSS default)
  3. **Verification:** The Verifier validates that PCR 17 contains the expected geolocation hash by:
     - Re-hashing the retrieved geolocation string with the nonce and timestamp
     - Comparing the hash with PCR 17 value from the quote

**Geolocation PCR Extension Process (Agent Side):**
1. Agent gets geolocation: `get_current_geolocation()` → returns string like `"US:California:San Francisco:37.7749:-122.4194"`
2. Agent hashes: `hash_geolocation_data(geolocation, nonce, timestamp)` → SHA256 hash
3. Agent extends: `tpm_context.reset_and_extend_pcr(PcrHandle::Pcr17, digest_values)`
4. Agent generates quote: Includes PCR 17 in quote mask (bit 17 = 0x20000)

**Code Location:**
- Agent: `rust-keylime/keylime-agent/src/quotes_handler.rs::integrity()`
- Agent: `rust-keylime/keylime-agent/src/geolocation.rs::extend_geolocation_into_pcr()`
- Verifier: `keylime/cloud_verifier_tornado.py::invoke_get_quote()`
- Verifier: `keylime/fact_provider.py::get_attested_claims()`

**Note:** In the current implementation, the geolocation string is retrieved from the Verifier's fact provider (database/metadata/defaults), not directly from the Agent API. The PCR 17 attestation proves that the geolocation was measured into the TPM at quote time, but the actual geolocation value must be retrieved separately and then verified against PCR 17.

**Flow Continuation:** After Step 10a completes, the Keylime Verifier returns the attested claims (including geolocation) to the SPIRE Server as part of Step 10's response. The SPIRE Server then continues with Step 11 to issue the Unified SVID.

---

#### Step 11: SPIRE Server Issues Unified SVID

**Component:** SPIRE Server → SPIRE Agent

**Status:** ✅ Existing (Standard SPIRE) - Extended with Unified Identity claims

**Transport:** mTLS over TCP (same connection as Step 8)

**Protocol:** gRPC Streaming API (Protobuf)

**Action:**
- SPIRE Server signs the agent's X.509 SVID with:
  - SPIFFE ID: `spiffe://example.org/spire/agent/join_token/<token-id>`
  - Unified Identity claims embedded in X.509 certificate extension (OID: `1.3.6.1.4.1.99999.1`)
  - AttestedClaims in Protobuf response

**Response Format (Protobuf):**
```protobuf
// AttestAgentResponse (streaming gRPC)
message AttestAgentResponse {
  message Result {
    spire.api.types.X509SVID svid = 1;
    bool reattestable = 2;
    repeated spire.api.types.AttestedClaims attested_claims = 3;
  }
  oneof step {
    Result result = 1;        // Attestation complete
    bytes challenge = 2;      // Challenge issued (if needed)
  }
}

// X509SVID (from spire.api.types)
message X509SVID {
  string spiffe_id = 1;                    // Agent SPIFFE ID
  repeated bytes cert_chain = 2;            // PEM-encoded certificate chain
  bytes private_key = 3;                    // PKCS#8 DER-encoded private key
  google.protobuf.Timestamp expires_at = 4; // Certificate expiration
}

// AttestedClaims (from spire.api.types)
message AttestedClaims {
  string geolocation = 1;                   // "Spain: N40.4168, W3.7038"
  HostIntegrityStatus host_integrity_status = 2;  // Enum: PASSED_ALL_CHECKS, FAILED, PARTIAL
  GpuMetricsHealth gpu_metrics_health = 3;  // GPU health metrics
}
```

**X.509 Certificate Extension:**
The SVID certificate includes unified identity claims in a custom extension:
- **OID:** `1.3.6.1.4.1.99999.1` (AttestedClaims Extension - used for both legacy and unified identity claims)
- **Critical:** `false` (non-critical extension)
- **Value:** Raw JSON bytes (UTF-8 encoded)
- **Claims JSON Structure:**
```json
{
  "grc.workload": {
    "workload-id": "spiffe://example.org/spire/agent/join_token/<token-id>",
    "key-source": "tpm-app-key"
  },
  "grc.tpm-attestation": {
    "app-key-public": "-----BEGIN PUBLIC KEY-----\n...",
    "app-key-certificate": "<base64-encoded-certificate>",
    "quote": "r<base64-message>:<base64-signature>:<base64-pcrs>",
    "challenge-nonce": "<hex-nonce>"
  },
  "grc.geolocation": {
    "physical-location": {
      "format": "precise",
      "precise": {
        "latitude": 40.4168,
        "longitude": -3.7038
      }
    },
    "jurisdiction": {
      "country": "Spain"
    },
    "tpm-attested-location": true,
    "tpm-attested-pcr-index": 17
  }
}
```

**Extension Encoding:**
- The JSON is serialized to UTF-8 bytes
- Embedded directly in the X.509 certificate extension value field
- No additional encoding (not base64-encoded within the extension)
- Accessible via standard X.509 parsing libraries

**Code Location:**
- Server: `pkg/server/api/agent/v1/service.go::AttestAgent()`
- Certificate Builder: `pkg/server/credtemplate/builder.go::BuildAgentX509SVIDTemplate()`
- Claims Builder: `pkg/server/unifiedidentity/claims.go::BuildClaimsJSON()`

---

#### Step 12: SPIRE Agent Caches Unified SVID

**Component:** SPIRE Agent (Internal)

**Action:**
- SPIRE Agent receives and caches the unified SVID
- SVID is stored in agent's SVID store
- SVID is used for:
  - Agent-to-Server communication (mTLS)
  - Workload API authentication
  - Future SVID renewals

**Code Location:**
- `pkg/agent/svid/rotator.go::rotateSVID()`
- `pkg/agent/svid/store/service.go`

---

### Timing and Performance

- **Step 1 (Initiate Renewal):** ~1-5ms
- **Step 2 (Get Nonce from Server):** ~10-50ms
- **Step 3-4 (TPM Operations):** ~100-500ms
- **Step 5 (Delegated Certification):** ~50-200ms
- **Step 6 (Host Data Collection):** ~10-50ms (asynchronous)
- **Step 7 (Assembly):** ~1-5ms
- **Step 8 (gRPC Request):** ~10-50ms
- **Step 9 (Workload Verification):** ~5-20ms
- **Step 10 (Host Verification):** ~200-1000ms
- **Step 11-12 (SVID Issuance & Caching):** ~10-50ms

**Total:** ~397-1930ms per refresh cycle

**Refresh Frequency:** Approximately every 30 seconds (or when SVID is about to expire)

---

## Component Flow: Workload SVID (Standard SPIRE Flow)

Workloads request SVIDs from the SPIRE Agent via the Workload API. This flow is independent of the Sovereign SVID flow and follows standard SPIRE behavior. The workload SVID does not include TPM attestation or host integrity claims—it only includes workload identity based on the workload's selectors.

### Flow Overview

```
┌─────────────────┐
│   Workload      │
│  (Application)  │
└────────┬────────┘
         │
         │ Step 1: Request SVID via Workload API
         ▼
┌─────────────────┐
│  SPIRE Agent    │
│  Workload API   │
└────────┬────────┘
         │
         │ Step 2: Attest Workload
         │ Step 3: Match Registration Entry
         │ Step 4: Fetch SVID from SPIRE Server
         │        (Agent authenticates with Sovereign SVID)
         ▼
┌─────────────────┐
│  SPIRE Server   │
│  (Verifies &    │
│   Issues SVID)  │
└────────┬────────┘
         │
         │ Step 5: Return SVID to Workload
         ▼
┌─────────────────┐
│   Workload       │
│  (SVID Received) │
└─────────────────┘
```

### Detailed Step-by-Step Flow

#### Step 1: Workload Requests SVID

**Component:** Workload → SPIRE Agent

**Status:** ✅ Existing (Standard SPIRE)

**Transport:** UNIX Domain Socket (UDS) or TCP

**Protocol:** gRPC (SPIFFE Workload API)

**Port/Path:** 
- UDS: `/tmp/spire-agent/public/api.sock` (default)
- TCP: `localhost:8080` (if configured)

**Endpoint:** `SpiffeWorkloadAPI.FetchX509SVID`

**Action:**
- Workload connects to SPIRE Agent's Workload API
- Sends `FetchX509SVIDRequest` (empty request for all available SVIDs)
- Workload is authenticated via process attestation (PID, cgroup, etc.)

**Request Format (Protobuf):**
```protobuf
message X509SVIDRequest {
  // Empty - requests all available SVIDs for the workload
}
```

**Authentication:** Process attestation (PID, cgroup, k8s pod, container ID, etc.)

**Code Location:**
- `pkg/agent/endpoints/workload/handler.go::FetchX509SVID()`
- `go-spiffe/proto/spiffe/workload/workload.proto`

---

#### Step 2: SPIRE Agent Attests Workload

**Component:** SPIRE Agent (Internal)

**Action:**
- SPIRE Agent performs workload attestation:
  - Extracts selectors from the workload's process context
  - Selectors include: PID, cgroup, k8s pod, container ID, etc.
  - Validates workload is running in expected environment

**Code Location:**
- `pkg/agent/endpoints/workload/handler.go::FetchX509SVID()`
- `pkg/agent/workloadattestor/` (various attestors)

---

#### Step 3: SPIRE Agent Matches Registration Entry

**Component:** SPIRE Agent (Internal)

**Action:**
- SPIRE Agent matches workload selectors against registration entries
- Finds matching registration entry with:
  - SPIFFE ID for the workload
  - Selector set matching the workload
  - Parent SPIFFE ID (typically the agent's SPIFFE ID)

**Code Location:**
- `pkg/agent/manager/manager.go::MatchingRegistrationEntries()`
- `pkg/agent/cache/cache.go`

---

#### Step 4: SPIRE Agent Fetches SVID from SPIRE Server (if needed)

**Component:** SPIRE Agent → SPIRE Server

**Status:** ✅ Existing (Standard SPIRE)

**Transport:** mTLS over TCP

**Protocol:** gRPC (Protobuf)

**Port:** SPIRE Server port (typically 8081)

**RPC Method:** `BatchNewX509SVID(BatchNewX509SVIDRequest) returns (BatchNewX509SVIDResponse)`

**Action:**
- SPIRE Agent checks cache for existing SVID
- If cached SVID is valid and not expiring soon, skips this step and goes to Step 5
- If SVID needs refresh, SPIRE Agent:
  - **Authenticates to SPIRE Server using its own Sovereign SVID** (mTLS client certificate)
  - Sends `BatchNewX509SVIDRequest` with workload CSR and entry ID
  - SPIRE Server:
    1. **Verifies agent's identity** using the agent's Sovereign SVID (from mTLS)
    2. **Checks authorization** - verifies the agent is authorized to request SVIDs for the workload entry
    3. **Validates workload entry** - checks registration entry matches the workload selectors
    4. **Signs workload SVID** using SPIRE Server's CA
    5. Returns `BatchNewX509SVIDResponse` with signed workload SVID

**Request Format (Protobuf):**
```protobuf
message BatchNewX509SVIDRequest {
  repeated NewX509SVIDParams params = 1;
}

message NewX509SVIDParams {
  string entry_id = 1;           // Registration entry ID
  bytes csr = 2;                 // Certificate Signing Request (DER-encoded)
  SovereignAttestation sovereign_attestation = 3;  // Optional (for workloads with TPM attestation)
}
```

**Response Format (Protobuf):**
```protobuf
message BatchNewX509SVIDResponse {
  repeated BatchNewX509SVIDResponse_Result results = 1;
}

message BatchNewX509SVIDResponse_Result {
  types.X509SVID svid = 1;        // Signed workload SVID
  types.Status status = 2;        // Success or error status
}

message X509SVID {
  types.SPIFFEID id = 1;          // Workload SPIFFE ID
  repeated bytes cert_chain = 2;    // Certificate chain: [Workload SVID, Intermediate CA (if any), Root CA]
  int64 expires_at = 3;            // Expiration timestamp
}
```

**Authentication:**
- SPIRE Agent authenticates using its **Sovereign SVID** as the mTLS client certificate
- SPIRE Server extracts the agent's SPIFFE ID from the client certificate (`CallerID`)
- SPIRE Server verifies the agent's SVID is valid and not expired

**Authorization:**
- SPIRE Server checks if the agent (identified by `CallerID`) is authorized to request SVIDs for the workload entry
- The workload entry's `parent_id` must match the agent's SPIFFE ID
- SPIRE Server uses `LookupAuthorizedEntries()` to verify authorization

**Certificate Chain:**
- The workload SVID certificate chain includes: **[Workload SVID, Agent SVID, Intermediate CA (if any), Root CA]**
- **The agent's Sovereign SVID IS included in the certificate chain** (for policy enforcement)
- The agent's SVID is inserted after the workload SVID but before the CA chain
- This allows policy engines to identify which agent issued the workload SVID
- Both the agent's Sovereign SVID and workload SVID are signed by the same SPIRE Server CA

**Policy Enforcement:**
- The agent's SVID is included in the workload SVID certificate chain to enable policy enforcement
- Workloads can extract the agent's SPIFFE ID from the certificate chain to verify which agent issued their SVID
- Policy engines can use this information to enforce agent-specific policies (e.g., only allow workloads from specific agents)
- The agent's SVID is retrieved from the mTLS connection context via `rpccontext.CallerX509SVID(ctx)`

**Code Location:**
- Client: `pkg/agent/client/client.go::FetchWorkloadUpdate()`
- Client: `pkg/agent/manager/manager.go::FetchWorkloadUpdate()`
- Server: `pkg/server/api/svid/v1/service.go::BatchNewX509SVID()`
- Server: `pkg/server/endpoints/auth.go` (agent authentication middleware)

---

#### Step 5: SPIRE Agent Returns SVID to Workload

**Component:** SPIRE Agent → Workload

**Status:** ✅ Existing (Standard SPIRE)

**Transport:** gRPC (SPIFFE Workload API)

**Protocol:** Streaming gRPC

**Action:**
- SPIRE Agent caches the SVID received from SPIRE Server (or uses cached SVID if still valid)
- Returns SVID to workload via Workload API

**Response Format (Protobuf):**
```protobuf
message X509SVIDResponse {
  repeated X509SVID svids = 1;
}

message X509SVID {
  string spiffe_id = 1;                    // Workload SPIFFE ID (e.g., "spiffe://example.org/python-app")
  repeated bytes x509_svid_key = 2;        // Private key (PKCS#8 DER-encoded)
  repeated bytes x509_svid = 3;           // Certificate chain (PEM-encoded)
  repeated bytes bundle = 4;              // Trust bundle (PEM-encoded)
}
```

**Example Response:**
```protobuf
X509SVIDResponse {
  svids: [
    {
      spiffe_id: "spiffe://example.org/python-app"
      x509_svid_key: [<PKCS#8 DER private key>]
      x509_svid: [
        "-----BEGIN CERTIFICATE-----\nMIIDXTCCAkWgAwIBAgIJAKZ7Z3Z...\n-----END CERTIFICATE-----",
        "-----BEGIN CERTIFICATE-----\nMIIDXTCCAkWgAwIBAgIJAKZ7Z3Z...\n-----END CERTIFICATE-----"
      ]
      bundle: [
        "-----BEGIN CERTIFICATE-----\nMIIDXTCCAkWgAwIBAgIJAKZ7Z3Z...\n-----END CERTIFICATE-----"
      ]
    }
  ]
}
```

**Note:** The workload SVID certificate chain includes:
- **Workload SVID:** The leaf certificate for the workload
- **Agent SVID:** The agent's Sovereign SVID (included for policy enforcement)
- **CA Chain:** Intermediate CA (if any) and Root CA

The workload SVID certificate chain does NOT include:
- TPM attestation data (unless workload provides its own SovereignAttestation)
- Host integrity claims (unless workload provides its own SovereignAttestation)
- Geolocation claims (unless workload provides its own SovereignAttestation)

**Certificate Chain Structure:**
- **Workload SVID:** Signed by SPIRE Server CA, contains workload SPIFFE ID (leaf certificate)
- **Agent SVID:** The agent's Sovereign SVID, inserted for policy enforcement
- **Intermediate CA (if any):** Intermediate certificate authority
- **Root CA:** SPIRE Server's root certificate authority

**Agent's Sovereign SVID Role:**
- Used for **authentication** when SPIRE Agent connects to SPIRE Server (mTLS client certificate)
- Used for **authorization** - SPIRE Server verifies agent is authorized to request workload SVIDs
- **INCLUDED** in the workload SVID certificate chain (for policy enforcement)
- Both agent and workload SVIDs are signed by the same SPIRE Server CA, creating a trust relationship
- Policy engines can extract the agent's SPIFFE ID from the certificate chain to enforce agent-specific policies

The workload SVID contains:
- Workload SPIFFE ID
- Standard X.509 certificate fields (subject, issuer, validity, etc.)
- Certificate chain (Workload SVID → Agent SVID → CA chain)
- Trust bundle for validation
- Private key for mTLS authentication
- **AttestedClaims Extension (OID: 1.3.6.1.4.1.99999.1)** with ONLY `grc.workload` claims:
  ```json
  {
    "grc.workload": {
      "workload-id": "spiffe://example.org/python-app",
      "key-source": "workload-key",
      "public-key": "-----BEGIN PUBLIC KEY-----\n...",
      "workload-code-hash": "sha256:..."
    }
  }
  ```
  **Note:** Workload SVID does NOT include `grc.tpm-attestation` or `grc.geolocation` claims. These are only present in the Agent SVID, as TPM attestation is handled by the SPIRE agent.

**Code Location:**
- `pkg/agent/endpoints/workload/handler.go::FetchX509SVID()`
- `pkg/agent/manager/manager.go::FetchWorkloadUpdate()`
- `pkg/agent/cache/cache.go`

---

### Key Differences: Sovereign SVID vs. Workload SVID

| Aspect | Sovereign SVID (Agent) | Workload SVID |
|--------|------------------------|---------------|
| **Requestor** | SPIRE Agent (itself) | Workload (application) |
| **Frequency** | Periodic (~30s) | On-demand (when workload requests) |
| **Attestation** | TPM + Host Integrity + Geolocation | Process selectors only |
| **Claims** | Unified Identity (TPM, geolocation, GPU) | Workload identity only (`grc.workload`) |
| **Certificate Extension** | Custom OID with unified claims (`grc.workload` + `grc.tpm-attestation` + `grc.geolocation`) | Custom OID with workload claims only (`grc.workload`) |
| **Dependencies** | TPM Plugin, Keylime Agent, Keylime Verifier | SPIRE Agent only |
| **Used for Workload SVID** | Authentication & Authorization (mTLS) | N/A (this is the workload SVID) |
| **In Workload SVID Chain** | Yes (included for policy enforcement) | Yes (workload SVID is the leaf cert) |

---

## Quick Reference: Interface Summary Table

| Interface | Status | Transport | Protocol | Port/Path | Request Format | Response Format |
|-----------|--------|-----------|----------|-----------|----------------|-----------------|
| **spire-agent → spire-server** | ✅ Existing (Standard SPIRE) | mTLS over TCP | gRPC (Protobuf) | Server port (8081) | AttestAgentRequest | AttestAgentResponse |
| **keylime-agent → keylime-verifier** | ✅ Existing (Standard Keylime) | mTLS over HTTPS | JSON REST | localhost:8881 | JSON POST (quote requests) | JSON response |
| **keylime-verifier → keylime-agent** | ✅ Existing (Standard Keylime) | HTTP over localhost (or HTTPS with mTLS if enabled) | JSON REST | localhost:9002 | HTTP GET (quote requests with PCR 17) | JSON response (quote with PCR 17) |
| **spire-server → keylime-verifier** | 🆕 New (Phase 2/3) | mTLS over HTTPS | JSON REST | localhost:8881 | JSON POST (verify evidence) | JSON response |
| **spire-agent → spire-tpm-plugin** | 🆕 New (Phase 3) | JSON over UDS (Phase 3) | JSON | UDS: `/tmp/spire-data/tpm-plugin/tpm-plugin.sock` | JSON POST | JSON response |
| **spire-tpm-plugin → keylime-agent** | 🆕 New (Phase 3) | JSON over UDS (Phase 3) | JSON | UDS: `/tmp/keylime-agent.sock` or as configured | JSON POST | JSON response |

**Note:** The `spire-agent → spire-tpm-plugin` interface uses JSON over UDS (Phase 3) as the transport mechanism. The client requires `TPM_PLUGIN_ENDPOINT` to be set (defaults to `unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock` if not specified). HTTP over localhost is not supported for security reasons.

**Note:** The `spire-tpm-plugin → keylime-agent` interface uses JSON over UDS (Phase 3) as the transport mechanism. The rust-keylime Agent listens on a UDS socket (default: `/tmp/keylime-agent.sock`) and the network listener is disabled by default (`enable_network_listener = false`). This ensures that both components must be on the same physical host, preventing remote routing of connections. HTTP over localhost is not supported for security reasons.

## Nonce Flow

The nonce is generated by the SPIRE Server and flows through the system as follows:

1. **SPIRE Server generates nonce** (hex-encoded random bytes, typically 32 bytes = 64 hex chars)
2. **SPIRE Agent receives nonce** via gRPC challenge (if challenge-response flow) or uses join token
3. **TPM Plugin uses nonce** for TPM Quote generation (converted to hex if needed)
4. **Quote contains nonce** in TPMS_ATTEST.extraData field (as hex bytes)
5. **Keylime Verifier validates nonce** by extracting from quote and comparing

**Nonce Format:**
- **SPIRE Server:** Hex string (e.g., `a010d512540d60c18ec1d3942978ff4453f465ce64eddfdd232facfe670a0d2b`)
- **TPM Quote:** Hex bytes in TPMS_ATTEST.extraData
- **Verification:** Hex string comparison (after extracting from quote)

## Data Transformation Summary

| Data Item | Format at Source | Format at Destination | Transformation |
|-----------|------------------|----------------------|----------------|
| App Key Public | PEM (from TPM) | PEM (in SovereignAttestation) | None |
| TPM Quote | Binary TPM structures | Base64 string `r<msg>:<sig>:<pcrs>` | Base64 encoding |
| Certificate | TPM2_Certify output (JSON) | Base64-encoded bytes | JSON → Base64 |
| Nonce | Hex string | Hex bytes (in quote) | String → bytes |
| AttestedClaims | Protobuf | JSON (in cert extension) | Protobuf → JSON |
| Unified Identity Claims | Go struct | JSON bytes | JSON marshaling |

---

## Complete Data Flow Summary

### 1. Initial Attestation Trigger
- **Component:** SPIRE Agent
- **Action:** Agent starts or SVID expires, triggers attestation flow
- **Transport:** Internal (Go function calls)

### 2. TPM App Key Generation
- **From:** SPIRE Agent (Go)
- **To:** TPM Plugin (Python)
- **Transport:** Process execution (subprocess)
- **Format:** CLI arguments → JSON stdout
- **Data:** App Key public key (PEM), context file path

### 3. TPM Quote Generation
- **From:** SPIRE Agent (Go)
- **To:** TPM Plugin (Python)
- **Transport:** Process execution (subprocess)
- **Format:** CLI arguments → Base64 quote string
- **Data:** TPM Quote (r<message>:<signature>:<pcrs>)

### 4. App Key Certificate Request
- **From:** TPM Plugin (Python)
- **To:** rust-keylime Agent (Rust)
- **Transport:** UDS (JSON over UDS)
- **Format:** JSON request/response
- **Data:** App Key public key, context path → Base64 certificate

### 5. SovereignAttestation Assembly
- **Component:** SPIRE Agent (Go)
- **Action:** Assembles SovereignAttestation protobuf message
- **Data:** Quote, App Key public, certificate, nonce

### 6. Attestation Request to SPIRE Server
- **From:** SPIRE Agent (Go)
- **To:** SPIRE Server (Go)
- **Transport:** gRPC over TLS (TCP)
- **Format:** Protobuf stream
- **Data:** AttestAgentRequest with SovereignAttestation

### 7. Evidence Verification Request
- **From:** SPIRE Server (Go)
- **To:** Keylime Verifier (Python)
- **Transport:** HTTPS (localhost:8881)
- **Format:** JSON request/response
- **Data:** Quote, App Key public, certificate, nonce → AttestedClaims

### 8. SVID Signing with Claims
- **Component:** SPIRE Server (Go)
- **Action:** Signs X.509 SVID with unified identity claims in extension
- **Data:** SPIFFE ID, CSR, AttestedClaims → X.509 certificate

### 9. Attestation Response
- **From:** SPIRE Server (Go)
- **To:** SPIRE Agent (Go)
- **Transport:** gRPC over TLS (same connection)
- **Format:** Protobuf stream
- **Data:** AttestAgentResponse with X509SVID and AttestedClaims

---

## Transport Mechanisms Summary

| Interface | Transport | Protocol | Port/Path | Authentication |
|-----------|-----------|----------|-----------|----------------|
| SPIRE Agent → TPM Plugin | UDS | JSON REST | UDS socket | None (local only) |
| TPM Plugin → rust-keylime Agent | UDS | JSON REST | UDS socket | None (local only) |
| SPIRE Agent → SPIRE Server | TLS over TCP | gRPC (Protobuf) | Server port (8081) | TLS client cert |
| SPIRE Server → Keylime Verifier | HTTPS | JSON REST | localhost:8881 | TLS (self-signed for testing) |
| Keylime Verifier → Keylime Agent | HTTP/HTTPS | JSON REST | localhost:9002 | HTTP (or mTLS if enabled) |

---

## Data Format Summary

| Interface | Request Format | Response Format | Encoding |
|-----------|---------------|-----------------|----------|
| SPIRE Agent → TPM Plugin | JSON over UDS | JSON | UTF-8 |
| TPM Plugin → rust-keylime Agent | JSON over UDS | JSON | UTF-8 |
| SPIRE Agent → SPIRE Server | Protobuf | Protobuf | Binary (gRPC) |
| SPIRE Server → Keylime Verifier | JSON | JSON | UTF-8 |
| Keylime Verifier → Keylime Agent | HTTP GET (query params) | JSON (quote with PCR 17) | UTF-8 |

---

## Key Data Structures

### SovereignAttestation (Protobuf)
```protobuf
message SovereignAttestation {
  string tpm_signed_attestation = 1;  // Base64 TPM Quote
  string app_key_public = 2;          // PEM public key
  bytes app_key_certificate = 3;      // Base64 certificate
  string challenge_nonce = 4;         // Hex nonce
  string workload_code_hash = 5;      // Optional
}
```

### AttestedClaims (Protobuf)
```protobuf
message AttestedClaims {
  string geolocation = 1;
  HostIntegrityStatus host_integrity_status = 2;
  GpuMetricsHealth gpu_metrics_health = 3;
}
```

### Unified Identity Claims (JSON in Certificate Extension)
```json
{
  "grc.workload": {...},
  "grc.tpm-attestation": {...},
  "grc.geolocation": {...}
}
```

---

## Security Considerations

1. **TPM Plugin Communication:** UDS-only communication (JSON over UDS), ensuring both SPIRE Agent and TPM Plugin must be on the same physical host
2. **rust-keylime Agent:** UDS-only communication for delegated certification interface (default: `/tmp/keylime-agent.sock`). Network listener is disabled by default (`enable_network_listener = false`) to prevent remote routing of connections. This ensures both TPM Plugin and rust-keylime Agent must be on the same physical host.
3. **SPIRE Agent ↔ Server:** TLS with client certificate authentication
4. **SPIRE Server ↔ Keylime Verifier:** HTTPS with self-signed certs (testing) or CA validation (production)
5. **Nonce Validation:** Server-generated nonce ensures freshness
6. **Quote Verification:** Cryptographic signature validation using App Key

---

## Error Handling

Each interface includes error handling:
- **TPM Plugin:** JSON error responses, exit codes
- **rust-keylime Agent:** HTTP status codes (400, 403, 500) with JSON error messages
- **SPIRE gRPC:** gRPC status codes (InvalidArgument, Internal, etc.)
- **Keylime Verifier:** HTTP status codes (400, 422, 500) with detailed failure information

---

## Demonstration

```bash
./code-rollout-phase-3/test_phase3_complete.sh
```

---

## References

- Protobuf Definitions: `spire-api-sdk/proto/spire/api/`
- TPM Plugin: `code-rollout-phase-3/tpm-plugin/`
- rust-keylime Agent: `code-rollout-phase-3/rust-keylime/keylime-agent/`
- Keylime Verifier: `code-rollout-phase-2/keylime/keylime/`
- Unified Identity Claims: `federated-jwt.md`


