# Unified-Identity - Phase 3: rust-keylime Agent Integration

**Status:** ✅ **INTEGRATION IMPLEMENTED** (Full TPM implementation pending)

## Overview

Per the architecture document (README-arch.md), the SPIRE Agent TPM plugin communicates with the **rust-keylime agent** (not the Python Keylime agent) for delegated certification. This document describes the integration.

## Architecture

```
SPIRE Agent (Low Privilege)
    │
    │ HTTP POST /v2.2/delegated_certification/certify_app_key
    │ (localhost:9002)
    ▼
rust-keylime Agent (High Privilege)
    │
    │ Uses AK context
    │ TPM2_Certify
    ▼
TPM (AK signs App Key certificate)
```

## Implementation

### rust-keylime Agent Changes

**New Module:** `keylime-agent/src/delegated_certification_handler.rs`
- Implements `/v2.2/delegated_certification/certify_app_key` endpoint
- Accepts App Key public key and context path
- Uses AK to certify App Key via TPM2_Certify
- Returns base64-encoded certificate

**API Integration:** `keylime-agent/src/api.rs`
- Added delegated certification scope to API v2.2
- Endpoint: `/v2.2/delegated_certification/certify_app_key`

**Module Registration:** `keylime-agent/src/main.rs`
- Added `delegated_certification_handler` module

### Python TPM Plugin Changes

**Updated:** `tpm-plugin/delegated_certification.py`
- Changed from Python Keylime agent to rust-keylime agent
- Default endpoint: `http://localhost:9002/v2.2/delegated_certification/certify_app_key`
- Supports both HTTP and UNIX socket (for future use)
- Updated request/response format to match rust-keylime API

## API Specification

### Request Format

```json
{
  "api_version": "v1",
  "command": "certify_app_key",
  "app_key_public": "PEM-encoded public key",
  "app_ctx": "/path/to/app_key.ctx"
}
```

### Response Format

```json
{
  "result": "SUCCESS",
  "app_key_certificate": "base64-encoded certificate"
}
```

Or on error:

```json
{
  "result": "ERROR",
  "error": "Error message"
}
```

## Configuration

### rust-keylime Agent

The rust-keylime agent must be running with:
- Feature flag enabled: `export UNIFIED_IDENTITY_ENABLED=true`
- Listening on port 9002 (default) or configured port
- AK context available and loaded

### SPIRE Agent TPM Plugin

The Python TPM plugin client defaults to:
- Endpoint: `http://localhost:9002/v2.2/delegated_certification/certify_app_key`
- Can be overridden via `DelegatedCertificationClient(endpoint="...")`

## Status

### ✅ Completed

- rust-keylime agent handler module created
- API endpoint registered
- Python client updated to use rust-keylime agent
- HTTP communication implemented
- Feature flag support

### ⚠️ Pending (Full Implementation)

- **App Key Loading**: Need to implement loading App Key handle from TPM context file
- **TPM Certification**: Full TPM2_Certify implementation using rust-keylime TPM module
- **Certificate Formatting**: Format attestation + signature as proper certificate structure
- **Error Handling**: Complete error handling for all TPM operations
- **Testing**: Integration tests with real TPM

## Next Steps

1. Implement App Key loading from context file in rust-keylime handler
2. Complete TPM certification using `tpm_context.certify_credential()`
3. Format certificate properly (X.509 or TPM-specific format)
4. Add comprehensive error handling
5. Test with real TPM hardware

## References

- Architecture Document: `README-arch.md` (Section 2a: Delegated Certification)
- rust-keylime TPM Module: `rust-keylime/keylime/src/tpm.rs`
- rust-keylime Agent: `rust-keylime/keylime-agent/src/`

