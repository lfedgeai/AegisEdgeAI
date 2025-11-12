This document describes the complete end-to-end architecture flow for generating a SPIRE Agent Sovereign SVID with TPM attestation and geolocation claims. The flow spans multiple components using different transport mechanisms and data formats.

### Interface Classification

**Existing Interfaces (Standard SPIRE/Keylime):**
- `spire-agent → spire-server`: Protobuf gRPC over mTLS (standard SPIRE)
- `keylime-agent → keylime-verifier`: JSON over HTTPS with mTLS (standard Keylime)

**New Interfaces (Unified Identity Extensions):**
- `spire-server → keylime-verifier`: JSON over HTTPS with mTLS (Phase 2/3 addition)
- `spire-agent → spire-tpm-plugin`: JSON over HTTP/UDS (Phase 3)
- `spire-tpm-plugin → keylime-agent`: JSON over HTTP/UDS (Phase 3)

## Architecture Diagram

```
┌─────────────────┐
│  SPIRE Agent    │
│  (Go)           │
└────────┬────────┘
         │
         │ 1. Subprocess (CLI)
         │    Transport: Process exec
         │    Format: JSON (stdout/stderr)
         ▼
┌─────────────────┐
│  TPM Plugin     │
│  (Python)       │
└────────┬────────┘
         │
         │ 2. HTTP/JSON
         │    Transport: HTTP (localhost:9002)
         │    Format: JSON request/response
         ▼
┌─────────────────┐
│ rust-keylime    │
│ Agent (Rust)    │
└─────────────────┘
         │
         │ 3. gRPC Stream
         │    Transport: TLS over TCP
         │    Format: Protobuf
         ▼
┌─────────────────┐
│  SPIRE Server   │
│  (Go)           │
└────────┬────────┘
         │
         │ 4. HTTPS/JSON
         │    Transport: TLS (localhost:8881)
         │    Format: JSON request/response
         ▼
┌─────────────────┐
│ Keylime Verifier│
│ (Python)        │
└─────────────────┘
```

## Sequence Diagram

```
SPIRE Agent          TPM Plugin          rust-keylime      SPIRE Server        Keylime Verifier
     │                   │                    │                  │                    │
     │──1. generate-app-key───────────────────>│                  │                    │
     │                   │                    │                  │                    │
     │<──JSON: {app_key_public, context}───────│                  │                    │
     │                   │                    │                  │                    │
     │──2. generate-quote(nonce)───────────────>│                  │                    │
     │                   │                    │                  │                    │
     │<──Base64 Quote──────────────────────────│                  │                    │
     │                   │                    │                  │                    │
     │                   │──3. POST /certify_app_key────────────>│                    │
     │                   │    JSON: {app_key_public, context}    │                    │
     │                   │                    │                  │                    │
     │                   │<──JSON: {certificate}─────────────────│                    │
     │                   │                    │                  │                    │
     │──4. AttestAgent(gRPC)────────────────────────────────────────────────────────>│
     │    Protobuf: {SovereignAttestation}    │                  │                    │
     │                   │                    │                  │                    │
     │                   │                    │                  │──5. POST /verify/evidence──>│
     │                   │                    │                  │    JSON: {quote, app_key...}  │
     │                   │                    │                  │                    │
     │                   │                    │                  │<──JSON: {attested_claims}─────│
     │                   │                    │                  │                    │
     │<──AttestAgentResponse(gRPC)────────────────────────────────────────────────────│
     │    Protobuf: {X509SVID, AttestedClaims}│                  │                    │
     │                   │                    │                  │                    │
```

**Timing:**
- Step 1-2: ~100-500ms (TPM operations)
- Step 3: ~50-200ms (HTTP request to rust-keylime)
- Step 4: ~10-50ms (gRPC to SPIRE Server)
- Step 5: ~200-1000ms (Keylime verification)
- Step 6: ~10-50ms (gRPC response)
- **Total:** ~370-1800ms

## Component Flow Details

### Interface 1: SPIRE Agent → SPIRE Server (Attestation)

**Status:** ✅ Existing (Standard SPIRE)

**Transport:** mTLS over TCP

**Protocol:** gRPC (Protobuf)

**Port:** SPIRE Server port (typically 8081)

**Request Format (Protobuf):**
```protobuf
message AttestAgentRequest {
  message Params {
    spire.api.types.AttestationData data = 1;
    AgentX509SVIDParams params = 2;  // Contains SovereignAttestation
  }
  oneof step {
    Params params = 1;
    bytes challenge_response = 2;
  }
}
```

**Response Format (Protobuf):**
```protobuf
message AttestAgentResponse {
  message Result {
    spire.api.types.X509SVID svid = 1;
    bool reattestable = 2;
    repeated spire.api.types.AttestedClaims attested_claims = 3;
  }
  oneof step {
    Result result = 1;
    bytes challenge = 2;
  }
}
```

**Code Location:**
- Client: `pkg/agent/attestor/node/node.go::SendAttestationData()`
- Server: `pkg/server/api/agent/v1/service.go::AttestAgent()`

---

### Interface 2: Keylime Agent → Keylime Verifier (Quote Requests)

**Status:** ✅ Existing (Standard Keylime)

**Transport:** mTLS over HTTPS

**Protocol:** JSON REST API

**Port:** localhost:8881

**Request Format (JSON):**
```json
POST /v2.4/agents/{agent_id}/quote
{
  "nonce": "<hex-nonce>",
  "mask": "<pcr-mask>",
  ...
}
```

**Response Format (JSON):**
```json
{
  "quote": "<base64-encoded-quote>",
  "hash_alg": "sha256",
  ...
}
```

**Code Location:**
- Client: `rust-keylime/keylime-agent/src/quotes_handler.rs`
- Server: `keylime/cloud_verifier_tornado.py`

---

### Interface 3: SPIRE Server → Keylime Verifier (Evidence Verification)

**Status:** 🆕 New (Phase 2/3 Addition)

**Transport:** mTLS over HTTPS

**Protocol:** JSON REST API

**Port:** localhost:8881

**Endpoint:** `POST /v2.4/verify/evidence`

**Request Format (JSON):**
```json
{
  "type": "tpm-app-key",
  "data": {
    "nonce": "a010d512540d60c18ec1d3942978ff4453f465ce64eddfdd232facfe670a0d2b",
    "quote": "r<base64-message>:<base64-signature>:<base64-pcrs>",
    "hash_alg": "sha256",
    "app_key_public": "-----BEGIN PUBLIC KEY-----\n...",
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

**Code Location:**
- Client: `pkg/server/keylime/client.go::VerifyEvidence()`
- Server: `keylime/cloud_verifier_tornado.py::_tpm_app_key_verify()`

---

### Interface 4: SPIRE Agent → SPIRE TPM Plugin (TPM Operations)

**Status:** 🆕 New (Phase 3)

**Transport:** HTTP over UDS (or localhost HTTP)

**Protocol:** JSON REST API

**Port/Path:** UDS socket or localhost HTTP endpoint

**Note:** Current implementation uses subprocess execution, but interface is designed for HTTP/UDS.

**Request Format (JSON via HTTP POST or CLI):**
```json
POST /generate-app-key
{
  "work_dir": "/tmp/spire-data/tpm-plugin"
}
```

Or via CLI (current implementation):
```bash
python3 tpm_plugin_cli.py generate-app-key --work-dir /tmp/spire-data/tpm-plugin
```

**Response Format (JSON):**
```json
{
  "status": "success",
  "app_key_public": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
  "app_key_context": "/tmp/spire-data/tpm-plugin/app.ctx"
}
```

**Code Location:**
- Client: `pkg/agent/tpmplugin/tpm_plugin.go::GenerateAppKey()`
- Plugin: `tpm-plugin/tpm_plugin_cli.py::generate_app_key()`

---

### Interface 5: SPIRE TPM Plugin → Keylime Agent (Certificate Request)

**Status:** 🆕 New (Phase 3)

**Transport:** HTTP over UDS (or localhost HTTP)

**Protocol:** JSON REST API

**Port/Path:** UDS socket or localhost:9002

**Endpoint:** `POST /v2.2/delegated_certification/certify_app_key`

**Request Format (JSON):**
```json
{
  "api_version": "v1",
  "command": "certify_app_key",
  "app_key_public": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
  "app_key_context_path": "/tmp/spire-data/tpm-plugin/app.ctx"
}
```

**Response Format (JSON):**
```json
{
  "result": "SUCCESS",
  "app_key_certificate": "eyJhcHBfa2V5X3B1YmxpYyI6Ii0tLS0tQkVHSU4gUFVCTElDIEtFWS0tLS0tXG5NSUlCSWpBTkJna3Foa2l..."
}
```

**Certificate Format:**
- Base64-encoded JSON structure containing TPM2_Certify output:
```json
{
  "app_key_public": "...",
  "certify_data": "<base64-encoded-attestation>",
  "signature": "<base64-encoded-signature>",
  "hash_alg": "sha256",
  "format": "phase2_compatible"
}
```

**HTTP Headers:**
```
Content-Type: application/json
```

**Error Responses:**
- `400 Bad Request`: Invalid command or missing fields
- `403 Forbidden`: Feature flag disabled
- `500 Internal Server Error`: TPM operation failed

**Code Location:**
- Client: `tpm-plugin/delegated_certification.py::request_certificate()`
- Server: `rust-keylime/keylime-agent/src/delegated_certification_handler.rs::certify_app_key()`

---

---

### Interface Summary

The following interfaces are used in the Sovereign SVID flow:

1. **SPIRE Agent → SPIRE Server** (Existing): gRPC Protobuf over mTLS
2. **Keylime Agent → Keylime Verifier** (Existing): JSON over HTTPS with mTLS  
3. **SPIRE Server → Keylime Verifier** (New): JSON over HTTPS with mTLS
4. **SPIRE Agent → SPIRE TPM Plugin** (New): JSON over HTTP/UDS
5. **SPIRE TPM Plugin → Keylime Agent** (New): JSON over HTTP/UDS

---

### Detailed Interface Specifications

#### Interface 1: SPIRE Agent → SPIRE Server (Attestation Request)

**Status:** ✅ Existing (Standard SPIRE)

**Transport:** mTLS over TCP

**Protocol:** gRPC Streaming API

**RPC Method:** `AttestAgent(stream AttestAgentRequest) returns (stream AttestAgentResponse)`

**Request Format (Protobuf):**
```protobuf
// AttestAgentRequest (streaming gRPC)
message AttestAgentRequest {
  message Params {
    spire.api.types.AttestationData data = 1;
    AgentX509SVIDParams params = 2;
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

// SovereignAttestation (from spire.api.types)
message SovereignAttestation {
  string tpm_signed_attestation = 1;  // Base64-encoded TPM Quote (format: r<msg>:<sig>:<pcrs>)
  string app_key_public = 2;          // PEM-encoded App Key public key
  bytes app_key_certificate = 3;      // Base64-encoded certificate (optional, TPM2_Certify output)
  string challenge_nonce = 4;         // Hex-encoded nonce from SPIRE Server
  string workload_code_hash = 5;      // Optional workload code hash (e.g., "sha256:...")
}
```

**Example Request (JSON representation for debugging):**
```json
{
  "step": {
    "params": {
      "data": {
        "type": "join_token",
        "payload": "d6d68eaa-c78b-44c5-9..."
      },
      "params": {
        "csr": "<base64-encoded-DER-CSR>",
        "sovereign_attestation": {
          "tpm_signed_attestation": "r<base64>:<base64>:<base64>",
          "app_key_public": "-----BEGIN PUBLIC KEY-----\n...",
          "app_key_certificate": "<base64-encoded-certificate>",
          "challenge_nonce": "a010d512540d60c18ec1d3942978ff4453f465ce64eddfdd232facfe670a0d2b",
          "workload_code_hash": ""
        }
      }
    }
  }
}
```

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
  
  message GpuMetrics {
    string status = 1;        // "healthy", "degraded", "failed"
    double utilization_pct = 2; // 0.0 to 100.0
    int64 memory_mb = 3;      // Memory in MB
  }
  
  enum HostIntegrity {
    HOST_INTEGRITY_UNSPECIFIED = 0;
    PASSED_ALL_CHECKS = 1;
    FAILED = 2;
    PARTIAL = 3;
  }
}
```

**Example Response (JSON representation for debugging):**
```json
{
  "step": {
    "result": {
      "svid": {
        "spiffe_id": "spiffe://example.org/spire/agent/join_token/711fb417-c7dd-4534-b213-e46b209a6bc4",
        "cert_chain": [
          "-----BEGIN CERTIFICATE-----\nMIIDXTCCAkWgAwIBAgIJAKZ7Z3Z...\n-----END CERTIFICATE-----",
          "-----BEGIN CERTIFICATE-----\nMIIDXTCCAkWgAwIBAgIJAKZ7Z3Z...\n-----END CERTIFICATE-----"
        ],
        "private_key": "<base64-encoded-PKCS8-DER>",
        "expires_at": "2025-11-13T05:20:56Z"
      },
      "reattestable": true,
      "attested_claims": [
        {
          "geolocation": "Spain: N40.4168, W3.7038",
          "host_integrity_status": "PASSED_ALL_CHECKS",
          "gpu_metrics_health": {
            "status": "healthy",
            "utilization_pct": 45.2,
            "memory_mb": 8192
          }
        }
      ]
    }
  }
}
```

**gRPC Metadata:**
- TLS client certificate authentication
- SPIRE trust domain validation

**Code Location:**
- Client: `pkg/agent/attestor/node/node.go::SendAttestationData()`
- Server: `pkg/server/api/agent/v1/service.go::AttestAgent()`

---

#### Interface 3: SPIRE Server → Keylime Verifier (Evidence Verification)

**Status:** 🆕 New (Phase 2/3 Addition)

**Transport:** mTLS over HTTPS

**Protocol:** JSON REST API

**Endpoint:** `POST /v2.4/verify/evidence`

**Request Format (JSON):**
```json
{
  "type": "tpm-app-key",
  "data": {
    "nonce": "a010d512540d60c18ec1d3942978ff4453f465ce64eddfdd232facfe670a0d2b",
    "quote": "r<base64-message>:<base64-signature>:<base64-pcrs>",
    "hash_alg": "sha256",
    "app_key_public": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
    "app_key_certificate": "eyJhcHBfa2V5X3B1YmxpYyI6Ii0tLS0tQkVHSU4gUFVCTElDIEtFWS0tLS0tXG5NSUlCSWpBTkJna3Foa2l...",
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

**HTTP Headers:**
```
Content-Type: application/json
```

**TLS Configuration:**
- Self-signed certificates for testing (InsecureSkipVerify: true)
- Production: CA certificate validation required

**Error Responses:**
- `400 Bad Request`: Missing required fields
- `422 Unprocessable Entity`: Quote verification failed
- `500 Internal Server Error`: Server error

**Code Location:**
- Client: `pkg/server/keylime/client.go::VerifyEvidence()`
- Server: `keylime/cloud_verifier_tornado.py::_tpm_app_key_verify()`

---

#### Interface 1 (continued): SPIRE Server → SPIRE Agent (SVID Response)

**Status:** ✅ Existing (Standard SPIRE)

**Transport:** mTLS over TCP (same connection as request)

**Protocol:** gRPC Streaming API (continuation of AttestAgent stream)

**Response Format (Protobuf):**
```protobuf
message AttestAgentResponse {
  message Result {
    spire.api.types.X509SVID svid = 1;
    bool reattestable = 2;
    repeated spire.api.types.AttestedClaims attested_claims = 3;
  }
  
  Result result = 1;  // Attestation complete
}

message X509SVID {
  string spiffe_id = "spiffe://example.org/spire/agent/join_token/<token-id>";
  repeated bytes cert_chain = [
    "-----BEGIN CERTIFICATE-----\nMIIDXTCCAkWgAwIBAgIJAKZ7Z3Z...\n-----END CERTIFICATE-----",
    "-----BEGIN CERTIFICATE-----\nMIIDXTCCAkWgAwIBAgIJAKZ7Z3Z...\n-----END CERTIFICATE-----"
  ];
  bytes private_key = "...";  // PKCS#8 DER-encoded
  google.protobuf.Timestamp expires_at = {...};
}

message AttestedClaims {
  string geolocation = "Spain: N40.4168, W3.7038";
  HostIntegrityStatus host_integrity_status = PASSED_ALL_CHECKS;
  GpuMetricsHealth gpu_metrics_health = {
    status: "healthy",
    utilization_pct: 45.2,
    memory_mb: 8192
  };
}
```

**X.509 Certificate Extension:**
The SVID certificate includes a custom extension (OID: `1.3.6.1.4.1.99999.1`) containing the unified identity claims JSON:

**Extension Details:**
- **OID:** `1.3.6.1.4.1.99999.1` (AttestedClaims Extension - used for both legacy and unified identity claims)
- **Critical:** `false` (non-critical extension)
- **Value:** Raw JSON bytes (UTF-8 encoded)
- **Note:** The extension uses the same OID for both legacy AttestedClaims format and new unified identity format. The Python client checks for OID `1.3.6.1.4.1.99999.2` first (for future compatibility), then falls back to `1.3.6.1.4.1.99999.1`.

**Claims JSON Structure:**
```json
{
  "grc.workload": {
    "workload-id": "spiffe://example.org/spire/agent/join_token/<token-id>",
    "key-source": "tpm-app-key"
  },
  "grc.tpm-attestation": {
    "app-key-public": "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
    "app-key-certificate": "eyJhcHBfa2V5X3B1YmxpYyI6Ii0tLS0tQkVHSU4gUFVCTElDIEtFWS0tLS0tXG5NSUlCSWpBTkJna3Foa2l...",
    "quote": "r<base64-message>:<base64-signature>:<base64-pcrs>",
    "challenge-nonce": "a010d512540d60c18ec1d3942978ff4453f465ce64eddfdd232facfe670a0d2b"
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

## Quick Reference: Interface Summary Table

| Interface | Status | Transport | Protocol | Port/Path | Request Format | Response Format |
|-----------|--------|-----------|----------|-----------|----------------|-----------------|
| **spire-agent → spire-server** | ✅ Existing (Standard SPIRE) | mTLS over TCP | gRPC (Protobuf) | Server port (8081) | AttestAgentRequest | AttestAgentResponse |
| **keylime-agent → keylime-verifier** | ✅ Existing (Standard Keylime) | mTLS over HTTPS | JSON REST | localhost:8881 | JSON POST (quote requests) | JSON response |
| **spire-server → keylime-verifier** | 🆕 New (Phase 2/3) | mTLS over HTTPS | JSON REST | localhost:8881 | JSON POST (verify evidence) | JSON response |
| **spire-agent → spire-tpm-plugin** | 🆕 New (Phase 3) | HTTP/UDS | JSON | UDS or localhost | JSON POST | JSON response |
| **spire-tpm-plugin → keylime-agent** | 🆕 New (Phase 3) | HTTP/UDS | JSON | UDS or localhost:9002 | JSON POST | JSON response |

**Note:** Current implementation uses subprocess execution for `spire-agent → spire-tpm-plugin`, but the interface is designed to support HTTP/UDS for future flexibility.

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
- **Transport:** HTTP/1.1 (localhost:9002)
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
| SPIRE Agent → TPM Plugin | Process exec | CLI + JSON | N/A (subprocess) | Process isolation |
| TPM Plugin → rust-keylime Agent | HTTP/1.1 | JSON REST | localhost:9002 | None (local only) |
| SPIRE Agent → SPIRE Server | TLS over TCP | gRPC (Protobuf) | Server port (8081) | TLS client cert |
| SPIRE Server → Keylime Verifier | HTTPS | JSON REST | localhost:8881 | TLS (self-signed for testing) |

---

## Data Format Summary

| Interface | Request Format | Response Format | Encoding |
|-----------|---------------|-----------------|----------|
| SPIRE Agent → TPM Plugin | CLI args | JSON (stdout) | UTF-8 |
| TPM Plugin → rust-keylime Agent | JSON | JSON | UTF-8 |
| SPIRE Agent → SPIRE Server | Protobuf | Protobuf | Binary (gRPC) |
| SPIRE Server → Keylime Verifier | JSON | JSON | UTF-8 |

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

1. **TPM Plugin Communication:** Process isolation (subprocess execution)
2. **rust-keylime Agent:** Localhost-only HTTP (no authentication)
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

## References

- Protobuf Definitions: `spire-api-sdk/proto/spire/api/`
- TPM Plugin: `code-rollout-phase-3/tpm-plugin/`
- rust-keylime Agent: `code-rollout-phase-3/rust-keylime/keylime-agent/`
- Keylime Verifier: `code-rollout-phase-2/keylime/keylime/`
- Unified Identity Claims: `federated-jwt.md`

