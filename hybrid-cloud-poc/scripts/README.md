# Unified-Identity - Phase 1: Scripts

This directory contains utility scripts for working with sovereign SVIDs.

## Scripts

### start-unified-identity.sh / stop-unified-identity.sh

Shared scripts used by the Python demo (and other automation) to start and stop the SPIRE Server, SPIRE Agent, and Keylime stub with the Unified-Identity feature flag enabled.

**Start stack:**
```bash
./start-unified-identity.sh
```

Environment variables:
- `SERVER_CONFIG` – path to `spire-server.conf` (defaults to `python-app-demo/spire-server.conf`)
- `AGENT_CONFIG` – path to `spire-agent.conf` (defaults to `python-app-demo/spire-agent.conf`)
- `AGENT_SPIFFE_ID` – host SPIFFE ID for the agent (defaults to `spiffe://example.org/host/python-demo-agent`)

**Stop stack:**
```bash
./stop-unified-identity.sh
```

The stop script also removes sockets, PID files, registration entries, and cleans up `/tmp/svid-dump` artifacts.

### test-python-demo.sh

Automated regression test that exercises the entire Phase 1 flow (agent bootstrap SVID, Python workload SVID, and log verification).

```bash
./test-python-demo.sh
```

The script:
1. Stops any existing setup
2. Ensures Python dependencies and protobuf stubs are present
3. Starts the SPIRE/Keylime stack
4. Verifies agent bootstrap AttestedClaims via server, agent, and Keylime logs
5. Creates the Python app registration entry and fetches the sovereign SVID via gRPC
6. Validates `svid.pem` and `attested_claims.json`
7. Checks component logs for Unified-Identity messages
8. Dumps the SVID for inspection and tears everything down

### generate-sovereign-svid.go

Generates an X509-SVID with `SovereignAttestation` using the SPIRE API.

**Build:**
```bash
go build -o generate-sovereign-svid generate-sovereign-svid.go
```

**Usage:**
```bash
./generate-sovereign-svid \
    -entryID "entry-id-123" \
    -spiffeID "spiffe://example.org/workload/test" \
    -serverSocketPath "unix:///tmp/spire-server/private/api.sock" \
    -verbose
```

**Output:**
- `svid.crt` - X.509 certificate
- `svid.key` - Private key
- `svid_attested_claims.json` - AttestedClaims (if Phase 1 enabled)

### dump-svid.go

Dumps SVID information and highlights Phase 1 additions (AttestedClaims).

**Build:**
```bash
go build -o dump-svid dump-svid.go
```

**Usage:**
```bash
# Pretty format with color highlighting (default)
./dump-svid -cert svid.crt -attested svid_attested_claims.json

# JSON format
./dump-svid -cert svid.crt -attested svid_attested_claims.json -format json

# Detailed format (includes certificate extensions)
./dump-svid -cert svid.crt -attested svid_attested_claims.json -format detailed

# Without color
./dump-svid -cert svid.crt -color false
```

**Features:**
- Displays standard SVID fields (Subject, Issuer, SPIFFE ID, etc.)
- Highlights Phase 1 additions with ➕ symbol and green color:
  - Geolocation
  - Host Integrity Status
  - GPU Metrics Health
- Multiple output formats (pretty, json, detailed)

### test-sovereign-svid.sh

Test script to verify the generate-sovereign-svid script works correctly.

**Usage:**
```bash
./test-sovereign-svid.sh
```

### dump-svid-example.sh

Example script demonstrating dump-svid usage.

**Usage:**
```bash
./dump-svid-example.sh
```

## Quick Start Workflow

1. **Generate SVID with SovereignAttestation:**
   ```bash
   ./generate-sovereign-svid -entryID <ENTRY_ID> -spiffeID <SPIFFE_ID> -verbose
   ```

2. **View SVID and highlight Phase 1 additions:**
   ```bash
   ./dump-svid -cert svid.crt -attested svid_attested_claims.json
   ```

3. **Export to JSON for processing:**
   ```bash
   ./dump-svid -cert svid.crt -attested svid_attested_claims.json -format json > svid.json
   ```

## Example Output

```
╔════════════════════════════════════════════════════════════════╗
║              SPIFFE Verifiable Identity Document (SVID)        ║
╚════════════════════════════════════════════════════════════════╝

📋 Standard SVID Information:
──────────────────────────────────────────────────────────────────────
  Subject: CN=sovereign-workload
  Issuer: CN=SPIRE
  Serial Number: 1234567890
  Valid From: 2024-11-06T10:00:00Z
  Valid Until: 2024-11-06T11:00:00Z
  SPIFFE ID: spiffe://example.org/workload/test

🆕 Phase 1 Additions (Unified-Identity):
═══════════════════════════════════════════════════════════════════════

  ➕ 📍 Geolocation: Spain: N40.4168, W3.7038
  ➕ 🔒 Host Integrity Status: PASSED_ALL_CHECKS
  ➕ 🎮 GPU Metrics Health:
    ➕ Status: healthy
    ➕ Utilization: 15.00%
    ➕ Memory: 10240 MB

──────────────────────────────────────────────────────────────────────
✓ This SVID includes Phase 1 AttestedClaims (Unified-Identity)
```

