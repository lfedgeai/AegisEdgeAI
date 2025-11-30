# Hybrid Cloud POC

This directory contains a proof-of-concept implementation demonstrating hybrid cloud unified identity with SPIRE, Keylime, and Envoy.

## Overview

This POC demonstrates:
- **SPIRE** for workload identity and certificate management
- **Keylime** for TPM-based attestation
- **Envoy Proxy** for mTLS termination and request routing
- **WASM Filters** for custom request processing
- **Mobile Location Service** for sensor verification

## Quick Start

### Unified Identity using Spire and Keylime

**Step 1: Setup spire and keylime (10.1.0.11)**:

```bash
./test_complete.sh --no-pause
```

This will:
- Set up SPIRE Server and Agent
- Set up Keylime Verifier and Agent
- Create registration entries
- Test workload SVID renewal
- Verify the complete flow

**Monitor logs (optional):**
```bash
# In separate terminals, watch logs:
tail -f /tmp/spire-server.log
tail -f /tmp/spire-agent.log
tail -f /tmp/mobile-sensor-microservice.log
```

### Enterprise On-Prem Setup

**Step 2: Setup on-prem server (10.1.0.10)**

```bash
cd enterprise-onprem
./test_onprem.sh
```

This sets up:
- Envoy proxy (port 8080)
    - Envoy WASM filter for sensor verification which calls mobile location sensor service
    - Mobile location service (port 5000)
- mTLS server (port 9443)

**Monitor logs (optional):**
```bash
cd enterprise-onprem

# Option 1: Individual terminal windows
./watch-envoy-logs.sh          # Terminal 1
./watch-mtls-server-logs.sh    # Terminal 2
./watch-mobile-sensor-logs.sh   # Terminal 3

# Option 2: All logs in one tmux session
./watch-all-logs.sh
```

**Step 3: Start mTLS client (10.1.0.11)**

```bash
cd ~/AegisEdgeAI/hybrid-cloud-poc/python-app-demo
export CLIENT_USE_SPIRE="true"
export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
export SERVER_HOST="10.1.0.10"  # Envoy on on-prem
export SERVER_PORT="8080"
export CA_CERT_PATH="~/.mtls-demo/envoy-cert.pem"
python3 mtls-client-app.py
```

**Monitor client logs (optional):**
```bash
# Watch client output in the same terminal, or in a separate terminal:
tail -f /tmp/mtls-client-app.log
```

See [enterprise-onprem/README.md](enterprise-onprem/README.md) for detailed documentation.

## Components

### SPIRE
- **Server**: Issues SVIDs with attested claims
- **Agent**: Provides Workload API to applications
- Location: `spire/`

### Keylime
- **Verifier**: Validates TPM attestation
- **Agent**: Provides TPM attestation to SPIRE
- Location: `keylime/` and `rust-keylime/`

### Python Applications
- **Client**: mTLS client using SPIRE SVIDs
- **Server**: mTLS server for testing
- Location: `python-app-demo/`

### Enterprise On-Prem
- **Envoy Proxy**: mTLS termination and routing
- **WASM Filter**: Sensor ID extraction and verification
- **Mobile Location Service**: CAMARA API integration
- Location: `enterprise-onprem/`

## Documentation

- [Enterprise On-Prem README](enterprise-onprem/README.md) - Detailed setup and architecture
- [Python App Demo README](python-app-demo/README.md) - Client/server usage
- [test_complete.sh](test_complete.sh) - Complete integration test script

## Logs

### Log File Locations

- SPIRE Server: `/tmp/spire-server.log`
- SPIRE Agent: `/tmp/spire-agent.log`
- Envoy: `/opt/envoy/logs/envoy.log`
- mTLS Server: `/tmp/mtls-server.log`
- Mobile Location Service: `/tmp/mobile-sensor.log`

### Watch Logs During Demo

For monitoring logs during a demo, use the watch scripts:

**Option 1: Individual terminal windows**
```bash
cd enterprise-onprem

# Terminal 1 - Envoy logs
./watch-envoy-logs.sh

# Terminal 2 - mTLS server logs
./watch-mtls-server-logs.sh

# Terminal 3 - Mobile sensor service logs
./watch-mobile-sensor-logs.sh
```

**Option 2: Single tmux session (all logs in one window)**
```bash
cd enterprise-onprem
./watch-all-logs.sh
```

This creates a tmux session with 3 panes showing all logs simultaneously.
