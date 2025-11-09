# Unified-Identity - Phase 2: Core Keylime Functionality

**Status: ✅ Complete and Verified**

Phase 2 implements the core Keylime Verifier functionality to validate TPM App Key-based evidence and provide attested facts (geolocation, host integrity, GPU metrics) for the Unified Identity for Sovereign AI architecture.

## Overview

The Keylime Verifier acts as a **fact-provider** that:

1. **Validates App Key Certificate** - Verifies certificate signature chain against host Attestation Key (AK)
2. **Verifies TPM Quote** - Validates quote signature using App Key public key
3. **Validates Nonce** - Ensures nonce freshness
4. **Returns Attested Claims** - Provides geolocation, host integrity status, and GPU metrics

## Architecture

```
SPIRE Server (Phase 1)
    │
    │ POST /v2.4/verify/evidence
    │ (HTTPS, port 8881)
    ▼
Keylime Verifier (Phase 2)
    │
    │ - Validates Certificate
    │ - Verifies Quote
    │ - Returns Facts
    ▼
AttestedClaims
    │
    │ - Geolocation
    │ - Host Integrity
    │ - GPU Metrics
    ▼
SPIRE Server → Workload SVID
```

## Quick Start

### Prerequisites

- Python 3.8+
- Keylime dependencies (see `keylime/` directory)
- SPIRE Server and Agent (Phase 1)

### 1. Configure Keylime Verifier

Copy the minimal configuration:

```bash
cp verifier.conf.minimal /etc/keylime/verifier.conf
```

Or use the example configuration:

```bash
cp verifier.conf.example /etc/keylime/verifier.conf
# Edit and set: unified_identity_enabled = true
```

### 2. Enable Feature Flag

In `verifier.conf`:

```ini
[verifier]
unified_identity_enabled = true
```

### 3. Start Keylime Verifier

```bash
cd keylime
python3 -m keylime.cmd.verifier
```

### 4. Run Integration Test

```bash
./test_phase1_phase2_integration.sh
```

This script will:
- Set up TLS certificates
- Start Keylime Verifier
- Start SPIRE Server and Agent
- Generate a Sovereign SVID with AttestedClaims
- Verify end-to-end integration

## Components

### Core Modules

- **`keylime/app_key_verification.py`** - App Key certificate and quote verification
- **`keylime/fact_provider.py`** - Fact retrieval (geolocation, integrity, GPU metrics)
- **`keylime/cloud_verifier_tornado.py`** - Modified handler for `/v2.4/verify/evidence`

### Unit Tests

- **`keylime/test/test_app_key_verification.py`** - Certificate and quote verification tests
- **`keylime/test/test_fact_provider.py`** - Fact provider tests

## API

### Endpoint: `POST /v2.4/verify/evidence`

**Request**:
```json
{
  "type": "tpm",
  "data": {
    "nonce": "string",
    "quote": "base64-encoded-tpm-quote",
    "hash_alg": "sha256",
    "app_key_public": "pem-or-base64-public-key",
    "app_key_certificate": "base64-encoded-x509-certificate",
    "tpm_ak": "host-ak-public-key (optional)",
    "tpm_ek": "host-ek-hash (optional)"
  },
  "metadata": {
    "source": "SPIRE Server",
    "submission_type": "PoR/tpm-app-key"
  }
}
```

**Response**:
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
      "gpu_metrics_health": {
        "status": "healthy",
        "utilization_pct": 15.0,
        "memory_mb": 10240
      }
    },
    "audit_id": "uuid-..."
  }
}
```

## Configuration

### Required Settings

```ini
[verifier]
unified_identity_enabled = true
port = 8881
tls_dir = cv_ca
trusted_client_ca = all  # For testing (allows connections without client certs)

# Default facts (used when facts not found in store)
unified_identity_default_geolocation = Spain: N40.4168, W3.7038
unified_identity_default_integrity = passed_all_checks
unified_identity_default_gpu_status = healthy
unified_identity_default_gpu_utilization = 15.0
unified_identity_default_gpu_memory = 10240
```

See `verifier.conf.minimal` for a complete working configuration.

## Integration with Phase 1

Phase 2 integrates seamlessly with Phase 1:

1. **SPIRE Server** sends requests to `https://localhost:8881/v2.4/verify/evidence`
2. **Keylime Verifier** validates evidence and returns AttestedClaims
3. **SPIRE Server** includes AttestedClaims in Sovereign SVIDs

### Testing Integration

Use the Phase 1 Python app demo:

```bash
cd ../code-rollout-phase-1/python-app-demo
export KEYLIME_VERIFIER_URL="https://localhost:8881"
./run-demo-phase2.sh
```

## Feature Flag

All Phase 2 code is wrapped under the `unified_identity_enabled` feature flag (disabled by default).

- **Enabled**: Processes tpm-app-key verification requests
- **Disabled**: Returns 403 for tpm-app-key submissions

## Testing

### Unit Tests

```bash
cd keylime
python3 -m pytest test/test_app_key_verification.py -v
python3 -m pytest test/test_fact_provider.py -v
```

### Integration Test

```bash
./test_phase1_phase2_integration.sh
```

This comprehensive test:
- Sets up TLS environment
- Starts Keylime Verifier
- Starts SPIRE Server and Agent
- Generates Sovereign SVID
- Verifies AttestedClaims

## Logging

All Phase 2 code includes logging tagged with:
**"Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)"**

Key log messages:
- `INFO "Unified-Identity - Phase 2: Processing tpm-app-key verification request"`
- `INFO "Unified-Identity - Phase 2: Verification successful. Audit ID: ..."`
- `WARN "Unified-Identity - Phase 2: Detected stub quote for testing"` (testing mode)

## Limitations (Phase 2)

This is a **fact-provider implementation** with testing limitations:

1. **Stub Data**: Uses stub TPM quotes and certificates for testing
2. **In-Memory Store**: Facts stored in-memory (production would use database)
3. **Basic Nonce Validation**: Only length validation (full validation in Phase 3)
4. **No Hardware TPM**: No actual TPM interaction (Phase 3)

## Files

### Configuration
- `verifier.conf.minimal` - Minimal working configuration for testing
- `verifier.conf.example` - Example configuration with all options

### Testing
- `test_phase1_phase2_integration.sh` - Complete end-to-end integration test

### Implementation
- `keylime/app_key_verification.py` - App Key validation logic
- `keylime/fact_provider.py` - Attested claims provider
- `keylime/cloud_verifier_tornado.py` - Modified verification handler

## References

- [Architecture Document](../README-arch.md)
- [Phase 1 Implementation](../code-rollout-phase-1/README.md)
- [Keylime Documentation](https://keylime.readthedocs.io/)
- [SPIRE Documentation](https://spiffe.io/docs/latest/spire/)
