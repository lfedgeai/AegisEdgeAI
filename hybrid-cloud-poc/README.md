# Unified Identity for Sovereign AI

This project implements a **Unified Identity** system that provides TPM-based attestation and geolocation claims for sovereign AI workloads.This extends SPIFFE/SPIRE with sovereign attestation capabilities. Workloads can obtain X.509 certificates (SVIDs) that include not just identity, but also **attested claims** about the host's location - all cryptographically bound to the TPM.

The system works in three integrated phases:

1. **SPIRE API & Policy** - Extends SPIRE Server and Agent APIs to support `SovereignAttestation` and `AttestedClaims`
2. **Keylime Verification** - Validates TPM evidence and provides attested facts (geolocation, integrity, GPU metrics)
3. **Hardware Integration** - Real TPM operations with delegated certification between SPIRE Agent and Keylime Agent

The end result: workloads receive SVIDs that prove not just *who* they are, but also *where* they are and *what* state their host is in - all verified by TPM hardware.

Key references: 
- [Zero-trust Sovereign AI](https://github.com/lfedgeai/AegisEdgeAI/blob/main/docs/Zero-trust%20Sovereign%20AI-public.pdf)
- [Sovereign Unified Identity Architecture - End-to-End Flow](https://github.com/lfedgeai/AegisEdgeAI/blob/main/hybrid-cloud-poc/README-arch-sovereign-unified-identity.md)

Implementation Status: Proof of Concept

## Quick Start

### Prerequisites

- Python 3.8+
- Go 1.19+ (for SPIRE)
- Rust toolchain (for rust-keylime agent)
- tpm2-tools
- Hardware TPM 2.0 or swtpm (software TPM emulator)
- `pkg-config`, `libssl-dev`, `clang`, `libclang-dev` (for rust-keylime)

### Build Components

```bash
# Build SPIRE Server and Agent
cd spire
go build -o bin/spire-server ./cmd/spire-server
go build -o bin/spire-agent ./cmd/spire-agent

# Build rust-keylime Agent
cd ../rust-keylime/keylime-agent
cargo build --release
```

### Run End-to-End Test

The easiest way to get started is to run the complete integration test:

```bash
./test_complete.sh --no-pause
```

This single command will:
- Clean up any existing state
- Start all services (Keylime Verifier, Registrar, rust-keylime Agent, SPIRE Server/Agent, TPM Plugin)
- Generate a Sovereign SVID with AttestedClaims
- Run all unit and integration tests
- Generate workflow visualization

**Test Options:**
- `--help` - Show usage information
- `--cleanup-only` - Stop services and reset state, then exit
- `--skip-cleanup` - Reuse existing environment
- `--no-pause` - Run non-interactively (recommended for automation)
- `--test-spire-agent-svid-renewal` - Test SPIRE agent SVID renewal (see [SPIRE Agent SVID Renewal Testing](#spire-agent-svid-renewal-testing))

### Inspect Generated SVID

After the test completes, inspect the generated SVID:

```bash
./scripts/dump-svid-attested-claims.sh /tmp/svid-dump/svid.pem
```

### Clean Up

Stop all services and clean up state:

```bash
./scripts/cleanup.sh
# or
./test_complete.sh --cleanup-only
```

## System Architecture

```
┌──────────────┐
│   Workload   │ Requests SVID with SovereignAttestation
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ SPIRE Agent  │ → TPM Plugin → Generates App Key & Quote
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ SPIRE Server │ → Keylime Verifier → Validates TPM Evidence
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   Workload   │ Receives SVID + AttestedClaims (geolocation, integrity, GPU)
└──────────────┘
```

**Key Components:**
- **SPIRE Server/Agent** - Workload identity and SVID issuance
- **Keylime Verifier** - TPM evidence verification and fact provider
- **rust-keylime Agent** - High-privilege TPM operations (delegated certification)
- **TPM Plugin** - App Key generation and quote creation
- **Mobile Sensor Service** - Geolocation verification via CAMARA APIs

## Configuration

### Enable Unified Identity Feature

**SPIRE Server** (`spire/conf/server/server.conf`):
```hcl
server {
    experimental {
        feature_flags = ["Unified-Identity"]
    }
}
```

**SPIRE Agent** (`spire/conf/agent/agent.conf`):
```hcl
agent {
    experimental {
        feature_flags = ["Unified-Identity"]
    }
}
```

**Keylime Verifier** (`keylime/verifier.conf.minimal`):
```ini
[verifier]
unified_identity_enabled = true
```

**rust-keylime Agent** (environment variable):
```bash
export UNIFIED_IDENTITY_ENABLED=true
```

### CAMARA API Configuration

For testing, you can bypass CAMARA API calls to avoid rate limiting:

```bash
export CAMARA_BYPASS=true
./test_phase3_complete.sh
```

## Key References

### Architecture & Design

- **`README-arch-sovereign-unified-identity.md`** - Complete architecture document with all component interfaces, data flows, and protocols
- **`docs-additional/README-spire-setup.md`** - SPIRE setup and configuration guide
- **`docs-additional/README-keylime-setup.md`** - Keylime setup and configuration guide

### Component Documentation

- **`spire/README.md`** - SPIRE project documentation
- **`keylime/README.md`** - Keylime project documentation
- **`rust-keylime/README.md`** - rust-keylime agent documentation
- **`tpm-plugin/`** - TPM plugin implementation and tests
- **`mobile-sensor-microservice/README.md`** - Mobile location verification service
- **`python-app-demo/README.md`** - Python workload demo
- **`workflow-ui/WORKFLOW_UI_README.md`** - Workflow visualization UI

### Scripts & Tools

**Main Test Script:**
- **`test_complete.sh`** - Main end-to-end integration test
  - `--test-spire-agent-svid-renewal` - Test SPIRE agent SVID renewal (monitors for 5 minutes by default)
  - `--cleanup-only` - Stop services and reset state
  - `--skip-cleanup` - Reuse existing environment (skip initial cleanup)
  - `--no-pause` - Run non-interactively (for automation)
  - `--help` - Show usage information

**Utility Scripts:**
- **`scripts/cleanup.sh`** - Stop all services and clean up state
- **`scripts/demo.sh`** - Generate Sovereign SVID demo
- **`scripts/dump-svid-attested-claims.sh`** - Inspect SVID and AttestedClaims

**Python App Demo Scripts:**
- **`python-app-demo/setup-spire.sh`** - Set up SPIRE server and agent
- **`python-app-demo/run-demo.sh`** - Run Python workload demo
- **`python-app-demo/create-registration-entry.sh`** - Create workload registration entries
- **`python-app-demo/cleanup.sh`** - Clean up Python app demo resources
- **`python-app-demo/generate-proto-stubs.sh`** - Generate Python protobuf stubs

### Configuration Files

- **`keylime/verifier.conf.minimal`** - Minimal Keylime Verifier configuration
- **`spire/conf/server/server.conf`** - SPIRE Server configuration template
- **`spire/conf/agent/agent.conf`** - SPIRE Agent configuration template

## Testing

### Full Integration Test

```bash
./test_complete.sh --no-pause
```

### Unit Tests

```bash
# TPM Plugin tests
cd tpm-plugin
python3 -m pytest test/ -v

# Mobile sensor service tests
cd ../mobile-sensor-microservice
python3 -m pytest tests/ -v
```

### Manual Component Testing

See individual component READMEs for component-specific testing instructions.

### SPIRE Agent SVID Renewal Testing

The system supports automatic SPIRE agent SVID renewal with configurable intervals. This is useful for testing renewal behavior and ensuring continuous operation.

#### Quick Test (5 minutes)

Run a 5-minute renewal test with all components running persistently:

```bash
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30  # 30 seconds (minimum)
export UNIFIED_IDENTITY_ENABLED=true
./test_complete.sh --test-spire-agent-svid-renewal --no-pause
```

This will:
- Start all components (SPIRE Server/Agent, Keylime Verifier/Registrar, rust-keylime Agent, TPM Plugin)
- Configure agent SVID renewal interval to 30 seconds
- Monitor agent SVID renewals for 5 minutes (default)
- Keep all components running after the test completes

**Note:** All components continue running after the script exits. Use `./scripts/cleanup.sh` to stop them.

#### Extended Monitoring (15+ minutes)

For longer observation periods, run the test and then monitor logs manually:

```bash
# Start the test
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30
export UNIFIED_IDENTITY_ENABLED=true
./test_complete.sh --skip-cleanup --test-spire-agent-svid-renewal --no-pause

# In another terminal, monitor renewals
tail -f /tmp/spire-agent.log | grep "Agent Unified SVID renewed"
```

#### Configuration

The renewal interval is controlled by the `SPIRE_AGENT_SVID_RENEWAL_INTERVAL` environment variable:

- **Default:** 86400 seconds (24 hours) - SPIRE default
- **Minimum:** 30 seconds (when `Unified-Identity` feature flag is enabled)
- **Format:** Duration in seconds

The agent's `availability_target` configuration is automatically updated based on this environment variable. The server's `agent_ttl` is also configured to 60 seconds when Unified-Identity is enabled to ensure effective renewal testing.

#### Monitoring Logs

Monitor renewal activity in real-time:

```bash
# SPIRE Agent renewals
tail -f /tmp/spire-agent.log | grep "Agent Unified SVID renewed"

# SPIRE Server activity
tail -f /tmp/spire-server.log

# Count total renewals
grep -c "Agent Unified SVID renewed" /tmp/spire-agent.log
```

## Troubleshooting

### CAMARA API Rate Limiting

If you encounter rate limiting errors (429), you have two options:

1. **Wait and retry** - The CAMARA sandbox has rate limits
2. **Use bypass mode** - Set `CAMARA_BYPASS=true` for testing

```bash
export CAMARA_BYPASS=true
./test_phase3_complete.sh
```

### TPM Issues

If TPM operations fail:
- Ensure TPM is accessible: `ls -l /dev/tpm*`
- Check tpm2-abrmd is running: `systemctl status tpm2-abrmd`
- Clear TPM state: `tpm2_clear` (requires appropriate permissions)

### Service Startup Issues

Check service logs:
- SPIRE Server: `tail -f /tmp/spire-server.log`
- SPIRE Agent: `tail -f /tmp/spire-agent.log`
- Keylime Verifier: `tail -f /tmp/keylime-verifier.log`
- rust-keylime Agent: `tail -f /tmp/rust-keylime-agent.log`

## Project Structure

```
.
├── README.md                          # This file
├── test_complete.sh                   # Main end-to-end test
├── scripts/                           # Utility scripts
│   ├── cleanup.sh                    # Cleanup script
│   ├── demo.sh                        # Demo script
│   └── dump-svid-attested-claims.sh  # SVID inspection tool
│
├── spire/                             # SPIRE Server and Agent
├── keylime/                           # Keylime Verifier and Registrar
├── rust-keylime/                      # rust-keylime Agent
├── tpm-plugin/                        # TPM Plugin (Python)
├── mobile-sensor-microservice/        # Mobile location verification
├── python-app-demo/                   # Python workload demo
├── workflow-ui/                       # Workflow visualization tools
│
├── go-spiffe/                         # SPIFFE Go SDK
├── spire-api-sdk/                     # SPIRE API SDK
│
└── README-arch-sovereign-unified-identity.md  # Architecture documentation
```

## License

See individual component directories for their respective licenses.
