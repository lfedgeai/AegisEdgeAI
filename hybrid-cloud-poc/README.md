# Hybrid Cloud POC

This directory contains a proof-of-concept implementation demonstrating hybrid cloud security with SPIRE, Keylime, and Envoy.

## Overview

This POC demonstrates:
- **SPIRE** for workload identity and certificate management
- **Keylime** for TPM-based attestation
- **Envoy Proxy** for mTLS termination and request routing
- **WASM Filters** for custom request processing
- **Mobile Location Service** for sensor verification

## Quick Start

### Complete Integration Test

Run the full end-to-end test:

```bash
./test_complete.sh
```

This will:
- Set up SPIRE Server and Agent
- Set up Keylime Verifier and Agent
- Create registration entries
- Test workload SVID renewal
- Verify the complete flow

### Enterprise On-Prem Setup

For the enterprise on-prem environment (10.1.0.10):

```bash
cd enterprise-onprem
./test_onprem.sh
```

This sets up:
- Envoy proxy (port 8080)
- mTLS server (port 9443)
- Mobile location service (port 5000)
- WASM filter for sensor verification

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

## Testing

### From SPIRE Client (10.1.0.11)

```bash
cd python-app-demo
export CLIENT_USE_SPIRE="true"
export SPIRE_AGENT_SOCKET="/tmp/spire-agent/public/api.sock"
export SERVER_HOST="10.1.0.10"  # Envoy on on-prem
export SERVER_PORT="8080"
export CA_CERT_PATH="~/.mtls-demo/envoy-cert.pem"
python3 mtls-client-app.py
```

## Documentation

- [Enterprise On-Prem README](enterprise-onprem/README.md) - Detailed setup and architecture
- [Python App Demo README](python-app-demo/README.md) - Client/server usage
- [test_complete.sh](test_complete.sh) - Complete integration test script

## Logs

- SPIRE Server: `/tmp/spire-server.log`
- SPIRE Agent: `/tmp/spire-agent.log`
- Envoy: `/opt/envoy/logs/envoy.log`
- mTLS Server: `/tmp/mtls-server.log`
- Mobile Location Service: `/tmp/mobile-sensor.log`
