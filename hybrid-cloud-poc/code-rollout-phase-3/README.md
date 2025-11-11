# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification

**Status: ✅ Complete and Verified**

Phase 3 implements the hardware-dependent TPM operations and delegated certification flow for the Unified Identity for Sovereign AI architecture. This phase integrates real TPM hardware operations with the SPIRE Agent and Keylime Agent.

## Overview

Phase 3 completes the hardware integration by implementing:

1. **TPM Plugin (Python)** - Generates App Keys and TPM Quotes using real TPM hardware
2. **Delegated Certification** - Secure local API between SPIRE Agent and rust-keylime Agent for App Key certification
3. **SPIRE Agent Integration** - Integration with SPIRE Agent to generate real TPM-based SovereignAttestation
4. **rust-keylime Agent Certification Endpoint** - High-privilege endpoint that signs App Key certificates using the AK

## Architecture

```
┌─────────────────┐
│  SPIRE Agent    │
│  (Low Privilege)│
└────────┬────────┘
         │
         │ 1. Generate App Key
         ▼
┌─────────────────┐
│  TPM Plugin     │
│  (Python)       │
└────────┬────────┘
         │
         │ 2. Request Certificate (HTTP)
         │    POST /v2.2/delegated_certification/certify_app_key
         ▼
┌─────────────────┐
│ rust-keylime    │
│ Agent           │
│ (High Privilege)│
│ Port 9002       │
└────────┬────────┘
         │
         │ 3. Sign with AK (TPM2_Certify)
         ▼
┌─────────────────┐
│      TPM        │
│  (AK Context)   │
└─────────────────┘
```

## Quick Start

### Prerequisites

- Python 3.8+
- tpm2-tools
- Hardware TPM 2.0 or swtpm (software TPM emulator)
- SPIRE Agent (from Phase 1)
- rust-keylime Agent (from Phase 3) - **Note:** Uses rust-keylime agent, not Python Keylime agent
- Rust toolchain (for building rust-keylime agent)

### 1. Setup

```bash
cd code-rollout-phase-3
./setup.sh
```

### 2. Enable Feature Flag

```bash
export UNIFIED_IDENTITY_ENABLED=true
```

### 3. Build and Start rust-keylime Agent

```bash
cd rust-keylime
cargo build --release
export UNIFIED_IDENTITY_ENABLED=true
./target/release/keylime_agent --config keylime-agent.conf
```

**Note:** The rust-keylime agent must be running with the Unified-Identity feature flag enabled to handle delegated certification requests.

### 4. Full Workflow (Cleanup → Start → Test → Sovereign SVID)

```bash
./test_phase3_complete.sh
```

This script:
- Cleans up any existing SPIRE/Keylime/rust-keylime state (unless `--skip-cleanup` is used)
- Starts the Phase 2 verifier, registrar, and Phase 3 rust-keylime agent
- Boots the SPIRE server and agent, handling join-token generation automatically
- Generates a Sovereign SVID (with AttestedClaims) and runs all unit/E2E/integration checks
- Enables Unified-Identity feature flag by default

After completion, inspect the generated SVID:
```bash
./dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem
```

**Options:**
- `--help` - Show usage information
- `--cleanup-only` - Stop services and reset state, then exit
- `--skip-cleanup` - Reuse existing environment (skip initial cleanup)
- `--no-exit-cleanup` - Leave background services running for inspection

## Components

### TPM Plugin (`tpm-plugin/`)

Python-based TPM plugin that provides:
- **App Key Generation** - Creates and persists App Keys in TPM
- **TPM Quote Generation** - Generates quotes signed by App Key (Phase 2 compatible format)
- **TPM Device Detection** - Automatically detects hardware TPM or swtpm

**Key Files:**
- `tpm_plugin.py` - Main TPM plugin implementation
- `delegated_certification.py` - Client for requesting certificates from rust-keylime agent
- `tpm_plugin_cli.py` - CLI wrapper for Go integration

### rust-keylime Agent Certification Endpoint (`rust-keylime/keylime-agent/src/delegated_certification_handler.rs`)

High-privilege HTTP endpoint that:
- Receives App Key certification requests from SPIRE Agent (via Python TPM plugin)
- Accesses AK context to sign App Key certificates using TPM2_Certify
- Returns signed certificates to SPIRE Agent
- Endpoint: `POST /v2.2/delegated_certification/certify_app_key`

**API Specification:**

Request:
```json
{
  "api_version": "v1",
  "command": "certify_app_key",
  "app_key_public": "PEM-encoded public key",
  "app_key_context_path": "/path/to/app_key.ctx"
}
```

Response (Success):
```json
{
  "result": "SUCCESS",
  "app_key_certificate": "base64-encoded certificate"
}
```

Response (Error):
```json
{
  "result": "ERROR",
  "error": "Error message"
}
```

**Implementation Details:**
- Loads App Key from context file or persistent handle (0x8101000B)
- Uses `tpm_context.certify_credential()` to perform TPM2_Certify with AK
- Formats attestation and signature into Phase 2-compatible certificate structure
- Requires `UNIFIED_IDENTITY_ENABLED=true` environment variable

### Geolocation PCR Extension (`rust-keylime/keylime-agent/src/geolocation.rs`)

TPM-bound geolocation attestation per `federated-jwt.md` Appendix:

- **PCR 17 Extension:** Hashes geolocation data (with nonce and timestamp) and extends into PCR 17
- **Quote Inclusion:** Automatically includes PCR 17 in quote mask when Unified-Identity is enabled
- **Geolocation Source:** Hardcoded (configurable via `KEYLIME_AGENT_GEOLOCATION` env var)
- **Format:** `"country:state:city:latitude:longitude"` (e.g., `"US:California:San Francisco:37.7749:-122.4194"`)

The geolocation is structured in the SVID as `grc.geolocation` with:
- `tpm-attested-location: true`
- `tpm-attested-pcr-index: 17`
- Structured `physical-location` and `jurisdiction` fields

### Configuration

**SPIRE Agent** (`agent.conf`):
```hcl
agent {
    experimental {
        feature_flags = ["Unified-Identity"]
    }
}
```

**rust-keylime Agent** (environment variable):
```bash
export UNIFIED_IDENTITY_ENABLED=true
```

Or in `keylime-agent.conf` (if supported):
```ini
[agent]
unified_identity_enabled = true
```

## Testing

### Recommended Full Run

```bash
./test_phase3_complete.sh
```

This executes the entire Cleanup → Start → Test → Sovereign SVID workflow. Use `--help`, `--cleanup-only`, `--skip-cleanup`, or `--no-exit-cleanup` to customize behavior.

### Manual Unit Tests

```bash
cd tpm-plugin
python3 -m pytest test/ -v
```

### Rebuilding Binaries

The repository keeps a slimmed SPIRE tree, so rebuilds must be done from source before running Phase 3 end-to-end.

1. Rebuild SPIRE server and agent (Phase 1):
   ```bash
   cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-1/spire
   go build -o bin/spire-server ./cmd/spire-server
   go build -o bin/spire-agent ./cmd/spire-agent
   ```
2. Rebuild the rust-keylime agent (Phase 3):
   ```bash
   cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-3/rust-keylime/keylime-agent
   cargo build --release
   ```
   Ensure the Rust toolchain, `pkg-config`, `libssl-dev`, `clang`, and `libclang-dev` are installed.
3. Run the orchestrator to clean state, start services, and verify the flow:
   ```bash
   cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-3
   ./test_phase3_complete.sh
   ```

## Integration with Previous Phases

### Phase 1 Integration

Phase 3 replaces the stub `BuildSovereignAttestationStub()` function in Phase 1 with real TPM operations.

### Phase 2 Integration ✅ FULLY INTEGRATED

Phase 3 is **fully integrated** with Phase 2's Keylime Verifier:

**Quote Format Compatibility:**
- Phase 2 expects: `r<TPM_QUOTE>:<TPM_SIG>:<TPM_PCRS>`
- Phase 3 generates: `r{base64(message)}:{base64(signature)}:{base64(pcrs)}`
- All components are base64-encoded and separated by `:`
- Verified by Phase 2's `verify_quote_with_app_key()` function

**Certificate Format Compatibility:**
- Phase 3 generates base64-encoded JSON structure:
  ```json
  {
    "app_key_public": "PEM public key",
    "certify_data": "base64-encoded attestation",
    "signature": "base64-encoded signature",
    "hash_alg": "sha256",
    "format": "phase2_compatible"
  }
  ```
- Phase 2 validates using `validate_app_key_certificate()`

**Request Flow:**
```
Phase 3 TPM Plugin → SPIRE Agent → SPIRE Server → Phase 2 Keylime Verifier
```
- SPIRE Server converts `SovereignAttestation` to Keylime request format
- Phase 2 verifies and returns `AttestedClaims`

**Feature Flag Consistency:**
- Both phases default to disabled
- Phase 2: `unified_identity_enabled = true` in config
- Phase 3: `UNIFIED_IDENTITY_ENABLED=true` environment variable

## Feature Flag

All Phase 3 code is wrapped under the `Unified-Identity` feature flag (disabled by default).

**To Enable:**
- Environment variable: `export UNIFIED_IDENTITY_ENABLED=true`
- SPIRE Agent config: `feature_flags = ["Unified-Identity"]`
- Keylime Agent config: `unified_identity_enabled = true`

## Files

### Root Level
- `README.md` - This file
- `test_phase3_complete.sh` - Full integration harness (cleanup/start/test/SVID)
- `setup.sh` - Optional environment preparation helper
- `dump-svid-attested-claims.sh` - Inspect AttestedClaims embedded in an SVID

### TPM Plugin
- `tpm-plugin/tpm_plugin.py` - Main TPM plugin
- `tpm-plugin/delegated_certification.py` - Delegated cert client (rust-keylime agent)
- `tpm-plugin/tpm_plugin_cli.py` - CLI wrapper
- `tpm-plugin/test/` - Unit tests

### rust-keylime Agent
- `rust-keylime/keylime-agent/src/delegated_certification_handler.rs` - Certification endpoint
- `rust-keylime/keylime-agent/src/geolocation.rs` - Geolocation PCR extension

## References

- [Architecture Document](../README-arch.md)
- [Phase 1 Implementation](../code-rollout-phase-1/README.md)
- [Phase 2 Implementation](../code-rollout-phase-2/README.md)
- [Federated JWT Schema](../../docs/federated-jwt.md)
