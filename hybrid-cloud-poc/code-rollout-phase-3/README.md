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
./run_phase3_full.sh
```

This wrapper script:
- Cleans up any existing SPIRE/Keylime/rust-keylime state
- Starts the Phase 2 verifier, registrar, and Phase 3 rust-keylime agent
- Boots the SPIRE server and agent, handling join-token generation automatically
- Generates a Sovereign SVID (with AttestedClaims) and runs all unit/E2E/integration checks

After completion, inspect the generated SVID:
```bash
./dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem
```

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
./run_phase3_full.sh
```

This executes the entire Cleanup → Start → Test → Sovereign SVID workflow. Use `--help`, `--cleanup-only`, or `--skip-cleanup` with this wrapper to forward the same options to `test_phase3_complete.sh`.

### Manual Unit Tests

```bash
cd tpm-plugin
python3 -m pytest test/ -v
```

### Standalone Integration Harness

```bash
./test_phase3_complete.sh
```

This is the underlying script invoked by `run_phase3_full.sh` and can be used directly when you only need the integration checks. Pass `--cleanup-only` to perform a state reset without starting services, `--skip-cleanup` to reuse an existing environment, or `--no-exit-cleanup` to leave background daemons running for inspection.

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
   Ensure the Rust toolchain, `pkg-config`, `libssl-dev`, `clang`, and `libclang-dev` are installed (see `RUST_KEYLIME_INTEGRATION.md`).
3. Run the orchestrator to clean state, start services, and verify the flow:
   ```bash
   cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/code-rollout-phase-3
   ./run_phase3_full.sh
   ```

`run_phase3_full.sh` invokes `test_phase3_complete.sh`, which can also be driven with the CLI options described above for targeted cleanup or reuse of running services.

## Integration with Previous Phases

### Phase 1 Integration

Phase 3 replaces the stub `BuildSovereignAttestationStub()` function in Phase 1 with real TPM operations.

### Phase 2 Integration ✅ FULLY INTEGRATED

Phase 3 is **fully integrated** with Phase 2's Keylime Verifier:

- **Quote Format:** `r<message>:<signature>:<pcrs>` (Phase 2 compatible)
- **Certificate Format:** Base64-encoded structure compatible with Phase 2
- **Request Format:** Compatible via Phase 1 SPIRE Server conversion
- **Verification Flow:** Phase 2 verifies Phase 3-generated quotes and certificates

See `PHASE2_INTEGRATION.md` for detailed integration documentation.

## Feature Flag

All Phase 3 code is wrapped under the `Unified-Identity` feature flag (disabled by default).

**To Enable:**
- Environment variable: `export UNIFIED_IDENTITY_ENABLED=true`
- SPIRE Agent config: `feature_flags = ["Unified-Identity"]`
- Keylime Agent config: `unified_identity_enabled = true`

## Files

### Root Level
- `README.md` - This file
- `run_phase3_full.sh` - Single-entry script for cleanup/start/test/SVID
- `test_phase3_complete.sh` - Full integration harness (invoked by the wrapper)
- `setup.sh` - Optional environment preparation helper
- `dump-svid-attested-claims.sh` - Inspect AttestedClaims embedded in an SVID

### TPM Plugin
- `tpm-plugin/tpm_plugin.py` - Main TPM plugin
- `tpm-plugin/delegated_certification.py` - Delegated cert client
- `tpm-plugin/tpm_plugin_cli.py` - CLI wrapper
- `tpm-plugin/test/` - Unit tests

### Keylime
- `keylime/keylime/delegated_certification_server.py` - Certification server

## References

- [Architecture Document](../README-arch.md)
- [Phase 1 Implementation](../code-rollout-phase-1/README.md)
- [Phase 2 Implementation](../code-rollout-phase-2/README.md)
- [Phase 2 Integration](PHASE2_INTEGRATION.md)
