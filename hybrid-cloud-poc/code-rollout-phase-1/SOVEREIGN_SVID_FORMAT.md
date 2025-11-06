# Unified-Identity - Phase 1: Sovereign SVID Format

This document describes the structure and new fields added for sovereign SVIDs in Phase 1.

## Important: X.509 Certificate Unchanged

**The X.509 certificate itself is unchanged** - it remains a standard SPIFFE SVID certificate with:
- Standard X.509 fields (Subject, Issuer, Serial Number, Validity, etc.)
- SPIFFE ID in the Subject Alternative Name (URI SAN)
- Standard certificate extensions

**The new Phase 1 fields are in the API request/response, not in the certificate.**

## New Fields Overview

### 1. Request: `SovereignAttestation` (Input)

Sent in the API request when generating an SVID with sovereign attestation.

**Location:**
- `X509SVIDRequest.sovereign_attestation` (Workload API)
- `NewX509SVIDParams.sovereign_attestation` (SPIRE Server API)

**Structure:**
```protobuf
message SovereignAttestation {
    string tpm_signed_attestation = 1;  // Base64-encoded TPM Quote
    string app_key_public = 2;          // App Key public key (PEM/base64)
    bytes app_key_certificate = 3;      // Base64-encoded X.509 cert
    string challenge_nonce = 4;        // SPIRE Server nonce for freshness
    string workload_code_hash = 5;      // Optional workload code hash
}
```

**Example JSON (for reference):**
```json
{
  "tpm_signed_attestation": "AQAAABAAAAA...",
  "app_key_public": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----",
  "app_key_certificate": "MIIBkTCB...",
  "challenge_nonce": "abc123def456",
  "workload_code_hash": "sha256:abc123..."
}
```

### 2. Response: `AttestedClaims` (Output)

Returned in the API response after Keylime verification and policy evaluation.

**Location:**
- `X509SVIDResponse.attested_claims` (Workload API)
- `BatchNewX509SVIDResponse.Result.attested_claims` (SPIRE Server API)

**Structure:**
```protobuf
message AttestedClaims {
    string geolocation = 1;    // e.g., "US-CA-SF", "EU-DE-BER"
    enum HostIntegrity {
        HOST_INTEGRITY_UNSPECIFIED = 0;
        PASSED_ALL_CHECKS = 1;
        FAILED = 2;
        PARTIAL = 3;
    }
    HostIntegrity host_integrity_status = 2;
    message GpuMetrics {
        string status = 1;        // 'healthy', 'degraded', 'failed'
        double utilization_pct = 2; // 0..100
        int64 memory_mb = 3;
    }
    GpuMetrics gpu_metrics_health = 3;
}
```

**Example JSON:**
```json
{
  "geolocation": "US-CA-SF",
  "host_integrity_status": "PASSED_ALL_CHECKS",
  "gpu_metrics_health": {
    "status": "healthy",
    "utilization_pct": 45.5,
    "memory_mb": 8192
  }
}
```

## Complete Flow

### Step 1: Workload Requests SVID

**Standard Request (no sovereign attestation):**
```protobuf
X509SVIDRequest {
    // No sovereign_attestation field
}
```

**Sovereign Request (with Phase 1 additions):**
```protobuf
X509SVIDRequest {
    sovereign_attestation: {
        tpm_signed_attestation: "...",
        app_key_public: "...",
        app_key_certificate: [...],
        challenge_nonce: "abc123",
        workload_code_hash: "sha256:..."
    }
}
```

### Step 2: SPIRE Server Processes Request

1. Server receives `SovereignAttestation` in request
2. Server sends evidence to Keylime Verifier
3. Keylime returns verification results
4. Server evaluates policy (geolocation, integrity, GPU metrics)
5. If policy passes, server includes `AttestedClaims` in response

### Step 3: Response Contains Both SVID and AttestedClaims

**Standard Response:**
```protobuf
X509SVIDResponse {
    svids: [X509SVID {...}],
    crl: [...],
    federated_bundles: {...}
    // No attested_claims
}
```

**Sovereign Response (with Phase 1 additions):**
```protobuf
X509SVIDResponse {
    svids: [X509SVID {...}],  // Standard X.509 certificate (unchanged)
    crl: [...],
    federated_bundles: {...},
    attested_claims: [        // 🆕 Phase 1 addition
        {
            geolocation: "US-CA-SF",
            host_integrity_status: PASSED_ALL_CHECKS,
            gpu_metrics_health: {
                status: "healthy",
                utilization_pct: 45.5,
                memory_mb: 8192
            }
        }
    ]
}
```

## Example: Using dump-svid Script

The `dump-svid` script highlights the Phase 1 additions:

```bash
./dump-svid -cert svid.crt -attested svid_attested_claims.json
```

**Output:**
```
╔════════════════════════════════════════════════════════════════╗
║              SPIFFE Verifiable Identity Document (SVID)        ║
╚════════════════════════════════════════════════════════════════╝

📋 Standard SVID Information:
──────────────────────────────────────────────────────────────────
Subject: CN=spiffe://example.org/workload/test-k8s
Issuer: CN=SPIRE
Serial Number: 1234567890
Valid From: 2024-01-01T00:00:00Z
Valid Until: 2024-01-01T01:00:00Z
SPIFFE ID: spiffe://example.org/workload/test-k8s

🆕 Phase 1 Additions (Unified-Identity):
══════════════════════════════════════════════════════════════════

📍 Geolocation: US-CA-SF
✅ Host Integrity: PASSED_ALL_CHECKS
🎮 GPU Metrics:
   Status: healthy
   Utilization: 45.5%
   Memory: 8192 MB
```

## Field Details

### SovereignAttestation Fields

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `tpm_signed_attestation` | string | Base64-encoded TPM Quote (TPM2_Quote) | Yes |
| `app_key_public` | string | App Key public key in PEM or base64 format | Yes |
| `app_key_certificate` | bytes | Base64-encoded X.509 certificate proving App Key was issued by host AK | Optional |
| `challenge_nonce` | string | SPIRE Server nonce for freshness verification | Yes |
| `workload_code_hash` | string | Optional workload code hash (e.g., "sha256:...") | Optional |

### AttestedClaims Fields

| Field | Type | Description | Values |
|-------|------|-------------|--------|
| `geolocation` | string | Host geolocation | Free-form or structured (e.g., "US-CA-SF", "EU-DE-BER") |
| `host_integrity_status` | enum | Host integrity verification result | `HOST_INTEGRITY_UNSPECIFIED`, `PASSED_ALL_CHECKS`, `FAILED`, `PARTIAL` |
| `gpu_metrics_health` | GpuMetrics | GPU health metrics | See below |

### GpuMetrics Fields

| Field | Type | Description | Values |
|-------|------|-------------|--------|
| `status` | string | GPU health status | `"healthy"`, `"degraded"`, `"failed"` |
| `utilization_pct` | double | GPU utilization percentage | 0.0 to 100.0 |
| `memory_mb` | int64 | GPU memory in MB | Non-negative integer |

## API Endpoints

### Workload API (gRPC)

**Request:**
```protobuf
rpc FetchX509SVID(X509SVIDRequest) returns (stream X509SVIDResponse);
```

**X509SVIDRequest:**
- Optional `sovereign_attestation` field (tag 20)

**X509SVIDResponse:**
- Optional `attested_claims` field (tag 30)

### SPIRE Server API (gRPC)

**Request:**
```protobuf
rpc BatchNewX509SVID(BatchNewX509SVIDRequest) returns (BatchNewX509SVIDResponse);
```

**NewX509SVIDParams:**
- Optional `sovereign_attestation` field (tag 20)

**BatchNewX509SVIDResponse.Result:**
- Optional `attested_claims` field (tag 30)

## Important Notes

1. **X.509 Certificate Unchanged**: The actual X.509 certificate remains a standard SPIFFE SVID. No new extensions or fields are added to the certificate itself.

2. **AttestedClaims are Separate**: `AttestedClaims` are returned in the API response alongside the certificate, not embedded in the certificate.

3. **Optional Fields**: All Phase 1 fields are optional. If `SovereignAttestation` is not provided, the response will not include `AttestedClaims` (backward compatible).

4. **Feature Flag Required**: The `Unified-Identity` feature flag must be enabled for `SovereignAttestation` processing and `AttestedClaims` to be returned.

5. **Policy Evaluation**: `AttestedClaims` are only returned if:
   - Feature flag is enabled
   - `SovereignAttestation` is provided
   - Keylime verification succeeds
   - Policy evaluation passes

## Example: Complete Request/Response Flow

### Request (with SovereignAttestation)
```json
{
  "sovereign_attestation": {
    "tpm_signed_attestation": "AQAAABAAAAA...",
    "app_key_public": "-----BEGIN PUBLIC KEY-----\n...",
    "app_key_certificate": "MIIBkTCB...",
    "challenge_nonce": "abc123def456",
    "workload_code_hash": "sha256:abc123..."
  }
}
```

### Response (with AttestedClaims)
```json
{
  "svids": [
    {
      "spiffe_id": "spiffe://example.org/workload/test-k8s",
      "x509_svid": "MIIBkTCB...",
      "x509_svid_key": "...",
      "bundle": "..."
    }
  ],
  "attested_claims": [
    {
      "geolocation": "US-CA-SF",
      "host_integrity_status": "PASSED_ALL_CHECKS",
      "gpu_metrics_health": {
        "status": "healthy",
        "utilization_pct": 45.5,
        "memory_mb": 8192
      }
    }
  ]
}
```

## Viewing Sovereign SVID

Use the `dump-svid` script to view both the certificate and AttestedClaims:

```bash
# Generate SVID with AttestedClaims
./generate-sovereign-svid -entryID <ID> -spiffeID spiffe://example.org/workload/test

# View with highlights
./dump-svid -cert svid.crt -attested svid_attested_claims.json
```

The script will:
1. Display standard X.509 certificate fields
2. Highlight Phase 1 additions (AttestedClaims) in a separate section
3. Show geolocation, host integrity, and GPU metrics

