# Sovereign Unified Identity Architecture - End-to-End Flow

## End-to-End Flow: SPIRE Agent Sovereign SVID Attestation

### Setup: Initial Setup (Before Attestation)

1. **rust-keylime Agent Registration**
   - The rust-keylime agent starts and registers with the Keylime Registrar
   - The agent generates its TPM Endorsement Key (EK) and Attestation Key (AK)
   - The registrar stores the agent's UUID, IP address, port, TPM keys, and mTLS certificate
   - The agent is now registered and ready to serve attestation requests

2. **SPIRE Agent TPM Plugin Server (Sidecar) Startup**
   - The SPIRE Agent TPM Plugin Server (sidecar process) starts and generates an App Key in the TPM
   - The App Key is a workload-specific key used for identity attestation
   - The App Key context (handle) is stored for later use
   - **Note**: SPIRE Agent TPM Plugin Server is a separate Python process (sidecar) that runs alongside SPIRE Agent

### Attestation: SPIRE Agent Attestation Request

3. **SPIRE Agent Initiates Attestation**
   - The SPIRE Agent initiates attestation by opening a gRPC stream to the SPIRE Server
   - The SPIRE Server sends a challenge nonce to the agent
   - The agent must prove its identity using TPM-based attestation

4. **SPIRE Agent Requests App Key Information**
   - The SPIRE Agent requests the App Key public key and context from the SPIRE Agent TPM Plugin Server (sidecar)
   - The SPIRE Agent TPM Plugin Server (sidecar) returns the App Key public key (PEM format) and context file path

5. **Delegated Certification Request**
   - The SPIRE Agent requests an App Key certificate from the SPIRE Agent TPM Plugin Server (sidecar)
   - The SPIRE Agent TPM Plugin Server (sidecar) forwards this request to the rust-keylime agent's delegated certification endpoint
   - The rust-keylime agent performs TPM2_Certify: it uses the TPM's Attestation Key (AK) to sign the App Key's public key
   - This creates a certificate proving the App Key exists in the TPM and was certified by the AK
   - The certificate (containing attestation data and signature) is returned along with the agent's UUID

6. **SPIRE Agent Builds SovereignAttestation**
   - The SPIRE Agent assembles the SovereignAttestation message containing:
     - App Key public key
     - App Key certificate (signed by AK)
     - Challenge nonce from SPIRE Server
     - Agent UUID
     - TPM quote field is left empty (the verifier will fetch it directly)
   - The SPIRE Agent sends this SovereignAttestation to the SPIRE Server

### Verification: SPIRE Server Verification

7. **SPIRE Server Receives Attestation**
   - The SPIRE Server receives the SovereignAttestation from the agent
   - It extracts the App Key public key, certificate, nonce, and agent UUID
   - The SPIRE Server needs to verify this attestation before issuing an SVID

8. **SPIRE Server Calls Keylime Verifier**
   - The SPIRE Server sends a verification request to the Keylime Verifier
   - The request includes the App Key public key, certificate, nonce, and agent UUID
   - The verifier is responsible for validating the TPM evidence

### Phase 4: Keylime Verifier On-Demand Verification

9. **Verifier Looks Up Agent Information**
   - The verifier uses the agent UUID to query the Keylime Registrar
   - The registrar returns the agent's IP address, port, TPM AK, and mTLS certificate
   - This allows the verifier to contact the agent directly

10. **Verifier Verifies App Key Certificate Signature**
    - The verifier parses the App Key certificate (JSON structure with `certify_data` and `signature`)
    - It extracts the `certify_data` (TPMS_ATTEST structure) and `signature` (TPMT_SIGNATURE)
    - The verifier uses the AK public key (from registrar) to verify the signature over `certify_data`
    - It verifies the qualifying data in `certify_data` matches the hash of (App Key public key + challenge nonce)
    - If signature verification fails, attestation is rejected with error "app key certificate signature verification failed"
    - This proves the App Key certificate was actually signed by the TPM's AK and is bound to the specific App Key and nonce

11. **Verifier Fetches TPM Quote On-Demand**
    - The verifier connects to the rust-keylime agent (over HTTPS/mTLS)
    - It requests a fresh TPM quote using the challenge nonce from SPIRE Server
    - The agent generates a TPM quote containing:
      - Platform Configuration Register (PCR) values showing system state
      - The challenge nonce
      - Signed by the TPM's Attestation Key (AK)
    - The quote is returned to the verifier

12. **Verifier Verifies the Quote**
    - The verifier uses the AK public key (from registrar) to verify the quote signature
    - It verifies the nonce matches the one from SPIRE Server (freshness check)
    - It validates the hash algorithm and quote structure
    - This proves the TPM is genuine and the platform state is authentic

13. **Verifier Extracts Geolocation from Quote**
    - The verifier extracts geolocation sensor information from the TPM quote response
    - If a mobile sensor is detected (sensor_id present), the verifier proceeds to location verification
    - Geolocation data includes: sensor type (mobile/gnss), sensor_id, and optional value (for GNSS)

14. **Verifier Calls Mobile Location Verification Microservice** (if mobile geolocation detected)
    - The verifier extracts the sensor_id from the geolocation data
    - The verifier calls the mobile location verification microservice via REST API (HTTP)
    - Request: `POST /verify` with `{"sensor_id": "<sensor_id>"}`
    - The microservice:
      - Looks up the sensor_id in SQLite database to get phone number (MSISDN) and default coordinates
      - Calls CAMARA APIs in sequence:
        1. `POST /bc-authorize` with login_hint (phone number) and scope
        2. `POST /token` with grant_type and auth_req_id
        3. `POST /location/v0/verify` with access_token, ueId, latitude, longitude, accuracy
      - Returns verification result: `{"verification_result": true/false, ...}`
    - If verification_result is false, or if the microservice is unreachable, the verifier fails the attestation

15. **Verifier Retrieves Attested Claims**
   - The verifier calls the fact provider to get optional metadata (if available)
   - **In Verification, geolocation comes from the TPM quote response** (not from fact provider)
   - The verifier overrides any fact provider geolocation with the TPM quote geolocation
   - The verifier prepares the verification response with attested claims (geolocation, TPM attestation, etc.)

16. **Verifier Returns Verification Result**
    - The verifier returns a verification response to SPIRE Server containing:
      - Verification status (success/failure)
      - Attested claims (geolocation with sensor_id, type, etc.)
      - Verification details (certificate signature valid, quote signature valid, nonce valid, mobile location verified, etc.)

### Phase 5: SPIRE Server Issues SVID

17. **SPIRE Server Validates Verification Result**
    - The SPIRE Server receives the verification result from Keylime Verifier
    - If verification succeeded (including certificate signature verification and mobile location verification if applicable), the server proceeds to issue the agent SVID
    - If certificate signature verification failed, the server rejects the attestation and does not issue an SVID
    - If mobile location verification failed, the server rejects the attestation and does not issue an SVID

18. **SPIRE Server Issues Sovereign SVID**
    - The SPIRE Server creates an X.509 certificate (SVID) for the SPIRE Agent
    - The SVID includes the attested claims from Keylime Verifier (geolocation with sensor_id, TPM attestation, etc.)
    - The SVID is embedded with metadata proving the agent's TPM-based identity and verified location
    - The SVID is returned to the SPIRE Agent

19. **SPIRE Agent Receives SVID**
    - The SPIRE Agent receives its agent SVID from SPIRE Server
    - The agent can now use this SVID to authenticate and request workload SVIDs
    - The attestation process is complete

### Key Design Points

- **On-Demand Quote Fetching**: The verifier fetches quotes directly from the agent when needed, ensuring freshness with the challenge nonce
- **Delegated Certification**: The App Key is certified by the TPM's AK, proving it exists in the TPM
- **Separation of Concerns**: Quote generation (platform attestation) is separate from App Key certification (workload identity)
- **No Periodic Polling**: Unlike traditional Keylime, agents aren't continuously monitored; verification happens on-demand per attestation request
- **Agent Registration Model**: Agents register with the Keylime Registrar (persistent storage) but are not registered with the Keylime Verifier (on-demand lookup only)
- **Mobile Location Verification**: When mobile geolocation is detected in the TPM quote, the verifier calls the mobile location verification microservice to verify the device location via CAMARA APIs; attestation fails if location verification fails

This flow provides hardware-backed identity attestation where the SPIRE Agent proves its identity using the TPM, and the SPIRE Server verifies this proof through the Keylime Verifier before issuing credentials.

---

## End-to-End Flow: Workload SVID Issuance

The workload SVID flow follows the standard SPIRE pattern, with the key difference being the certificate chain that includes the agent SVID (which contains TPM attestation claims). This allows workloads to inherit the TPM-backed identity of their hosting agent.

### Setup: Workload Registration

1. **Registration Entry Creation**
   - An administrator creates a registration entry for the workload in the SPIRE Server
   - The entry defines the workload's SPIFFE ID (e.g., `spiffe://example.org/python-app`)
   - The entry specifies the selector criteria (e.g., Unix UID, process name, etc.)
   - The registration entry is stored in the SPIRE Server's database

### Attestation: Workload Requests SVID

2. **Workload Connects to SPIRE Agent**
   - A workload process starts and needs an identity
   - The workload connects to the SPIRE Agent's Workload API (typically via Unix Domain Socket)
   - The workload provides its process context (PID, UID, etc.) for authentication

3. **SPIRE Agent Validates Workload**
   - The SPIRE Agent validates the workload's process context against registration entries
   - The agent matches the workload's selectors (PID, UID, etc.) to find the appropriate registration entry
   - If validated, the agent proceeds to request an SVID from the SPIRE Server

4. **SPIRE Agent Requests Workload SVID**
   - The SPIRE Agent sends a request to the SPIRE Server for the workload SVID
   - The request includes:
     - The workload's SPIFFE ID (from the matched registration entry)
     - The agent's own SVID (for authentication)
     - Workload selector information

### Verification: SPIRE Server Issues Workload SVID

5. **SPIRE Server Validates Request**
   - The SPIRE Server authenticates the agent using the agent's SVID
   - The server verifies the agent SVID's certificate chain and signature
   - The server validates that the agent is authorized to request SVIDs for the specified workload
   - **Note**: Workload SVID requests skip Keylime verification - workloads inherit attested claims from the agent SVID

6. **SPIRE Server Extracts Agent Attestation Claims**
   - The SPIRE Server extracts the AttestedClaims from the agent SVID
   - These claims include TPM attestation data (geolocation, TPM quote, etc.)
   - The server prepares to issue a workload SVID with workload-specific claims only
   - **No Keylime Verification**: Workload SVID generation does not call Keylime Verifier; it uses the agent SVID's attested claims directly

7. **SPIRE Server Issues Workload SVID**
   - The SPIRE Server creates an X.509 certificate (SVID) for the workload
   - The workload SVID contains:
     - The workload's SPIFFE ID
     - Workload-specific claims (e.g., `grc.workload` namespace)
     - **No TPM attestation claims** (these remain in the agent SVID)
   - The workload SVID is signed by the SPIRE Server's CA
   - The certificate chain includes: [Workload SVID, Agent SVID]

8. **SPIRE Server Returns Workload SVID**
   - The SPIRE Server returns the workload SVID and certificate chain to the SPIRE Agent
   - The agent caches the SVID for the workload

### Phase 4: Workload Receives SVID

9. **SPIRE Agent Returns SVID to Workload**
   - The SPIRE Agent returns the workload SVID and certificate chain to the workload
   - The workload receives:
     - The workload SVID (leaf certificate)
     - The agent SVID (intermediate certificate in chain)
     - Both certificates are signed by the SPIRE Server CA

10. **Workload Uses SVID**
    - The workload can now use its SVID for:
      - Authenticating to other services (mTLS)
      - Proving its identity in service-to-service communication
      - Accessing resources based on SPIFFE identity
    - The certificate chain allows verifiers to:
      - Validate the workload's identity
      - Trace back to the agent's TPM attestation (via agent SVID)
      - Enforce policies based on both workload and agent identity

### Key Design Points

- **Certificate Chain**: The workload SVID certificate chain includes the agent SVID, allowing policy enforcement based on both workload and agent identity
- **Claim Separation**: Workload SVID contains only workload-specific claims; TPM attestation claims remain in the agent SVID
- **Inherited Trust**: Workloads inherit the TPM-backed trust of their hosting agent through the certificate chain
- **Standard SPIRE Pattern**: The workload SVID flow follows standard SPIRE patterns, with the addition of the agent SVID in the certificate chain

### Certificate Chain Structure

```
Workload SVID (Leaf)
├── Subject: spiffe://example.org/python-app
├── Claims: grc.workload.* (workload-specific only)
└── Issuer: SPIRE Server CA
    │
    └── Agent SVID (Intermediate)
        ├── Subject: spiffe://example.org/spire/agent/join_token/...
        ├── Claims: grc.geolocation.*, grc.tpm-attestation.*, grc.workload.*
        └── Issuer: SPIRE Server CA
            │
            └── SPIRE Server CA (Root)
```

This structure allows verifiers to:
- Validate the workload's identity directly
- Trace back to the agent's TPM attestation for policy enforcement
- Enforce geofencing and platform policies based on agent attestation

---

## Complete Security Flow: SPIRE Agent Sovereign SVID Attestation

The following diagram illustrates the complete end-to-end flow for SPIRE Agent Sovereign SVID attestation, showing all components, interactions, and data transformations.

### SETUP: INITIAL SETUP (Before Attestation)

**Step 1: rust-keylime Agent Registration**
```
rust-keylime Agent (High Privilege, Port 9002)
    │
    ├─> Generate EK (Endorsement Key)
    ├─> Generate AK (Attestation Key)
    └─> Register with Keylime Registrar (Port 8890)
        │
        └─> Send: UUID, IP, port, TPM keys, mTLS certificate
            │
            <─ Keylime Registrar stores registration
```

**Step 2: SPIRE Agent TPM Plugin Server (Sidecar) Startup**
```
SPIRE Agent TPM Plugin Server (Python Sidecar, UDS Socket)
    │
    ├─> Generate App Key in TPM
    ├─> Store App Key context/handle
    └─> Ready for certification
```
### ATTESTATION: SPIRE AGENT ATTESTATION REQUEST

**Step 3: SPIRE Agent Initiates Attestation**
```
SPIRE Agent (Low Privilege)
    │
    └─> Initiate gRPC stream: AttestAgent()
        │
        └─> SPIRE Server (Port 8081)
            │
            ├─> Receives attestation request
            └─> Send challenge nonce
                │
                <─ SPIRE Agent
                    │
                    └─> Receives challenge nonce
```

**Step 4: SPIRE Agent Requests App Key Information**
```
SPIRE Agent
    │
    └─> Request App Key from SPIRE Agent TPM Plugin Server (Sidecar)
        │
        └─> GET App Key public key (PEM)
        └─> GET App Key context path
            │
            <─ SPIRE Agent TPM Plugin Server (Sidecar)
                │
                └─> Return: App Key public key (PEM), App Key context path
```

**Step 5: Delegated Certification Request**
```
SPIRE Agent TPM Plugin Server (Sidecar)
    │
    └─> POST /v2.2/delegated_certification/certify_app_key (HTTPS/mTLS)
        │
        └─> rust-keylime Agent (High Privilege, Port 9002)
            │
            ├─> Perform TPM2_Certify
            │   ├─> Load App Key from context
            │   ├─> Use AK to sign App Key public key
            │   └─> Generate certificate (attest + sig)
            │
            └─> Return: { certificate: { certify_data, signature }, agent_uuid }
                │
                <─ SPIRE Agent TPM Plugin Server (Sidecar)
```

**Step 6: SPIRE Agent Builds and Sends SovereignAttestation**
```
SPIRE Agent
    │
    ├─> Build SovereignAttestation:
    │   ├─> App Key public key
    │   ├─> App Key certificate (AK-signed)
    │   ├─> Challenge nonce
    │   ├─> Agent UUID
    │   └─> TPM quote: empty (verifier fetches)
    │
    └─> POST /agent/attest-agent
        │
        └─> SPIRE Server (Port 8081)
            │
            └─> Receives SovereignAttestation
```
### VERIFICATION: SPIRE SERVER VERIFICATION

**Step 7: SPIRE Server Receives Attestation and sends to Keylime Verifier**
```
SPIRE Server (Port 8081)
    │
    ├─> Extract: App Key public key, certificate, nonce, agent UUID
    │
    └─> POST /v2.2/unified_identity/verify
        │
        └─> Keylime Verifier (Port 8881)
            │
            └─> Receives verification request
```

### PHASE 4: KEYLIME VERIFIER ON-DEMAND VERIFICATION

**Step 8: Verifier Looks Up Agent Information**
```
Keylime Verifier (Port 8881)
    │
    └─> GET /agents/{agent_uuid}
        │
        └─> Keylime Registrar (Port 8890)
            │
            └─> Return: { ip, port, tpm_ak, mtls_cert }
                │
                <─ Keylime Verifier
```

**Step 9: Verifier Verifies App Key Certificate Signature**
```
Keylime Verifier (Port 8881)
    │
    ├─> Parse certificate JSON
    ├─> Extract certify_data & signature
    ├─> Verify signature with AK (from registrar)
    └─> Verify qualifying data (hash of App Key + nonce)
```

**Step 10: Verifier Fetches TPM Quote On-Demand**
```
Keylime Verifier (Port 8881)
    │
    └─> POST /v2.2/quote (HTTPS/mTLS)
        │
        └─> rust-keylime Agent (High Privilege, Port 9002)
            │
            ├─> Generate TPM Quote:
            │   ├─> PCR values (platform state)
            │   ├─> Challenge nonce
            │   └─> Signed by AK
            │
            └─> Return: { quote, signature, geolocation: { type: "mobile", sensor_id: "12d1:1433" } }
                │
                <─ Keylime Verifier
```

**Step 11: Mobile Location Verification**
```
Keylime Verifier (Port 8881)
    │
    ├─> Extract geolocation from quote
    ├─> Extract sensor_id if mobile type
    │
    └─> POST /verify
        │
        └─> Mobile Location Verification Microservice (Port 9050)
            │
            ├─> Lookup sensor_id in SQLite database
            │   └─> Get MSISDN, lat, lon, accuracy
            │
            ├─> Call CAMARA APIs:
            │   ├─> POST /bc-authorize
            │   ├─> POST /token
            │   └─> POST /location/v0/verify
            │
            └─> Return: { verification_result: true/false, latitude, longitude, accuracy }
                │
                <─ Keylime Verifier
```

**Step 12: Verifier Retrieves Attested Claims**
```
Keylime Verifier (Port 8881)
    │
    └─> Get Attested Claims
        │
        ├─> Call fact provider (optional)
        ├─> Override with geolocation from TPM quote
        └─> Prepare attested claims structure
            │
            └─> Return: { geolocation: {...} } (from TPM quote)
```

**Step 13: Verifier Returns Verification Result**
```
Keylime Verifier (Port 8881)
    │
    ├─> Verify Evidence:
    │   ├─> Certificate signature verified
    │   ├─> Quote signature verified (AK)
    │   ├─> Nonce matches
    │   ├─> Quote structure validated
    │   └─> Mobile location verified (if mobile)
    │
    └─> POST /v2.2/unified_identity/verify (response)
        │
        └─> SPIRE Server (Port 8081)
            │
            └─> Receives: { status: "success", attested_claims: { grc.geolocation, grc.tpm-attestation }, ... }
```
### PHASE 5: SPIRE SERVER ISSUES SVID

**Step 14: SPIRE Server Validates Verification Result**
```
SPIRE Server (Port 8081)
    │
    ├─> Check verification status
    ├─> Verify certificate signature valid
    ├─> Verify mobile location (if mobile)
    └─> Extract attested claims
```

**Step 15: SPIRE Server Issues Sovereign SVID**
```
SPIRE Server (Port 8081)
    │
    ├─> Create X.509 certificate
    ├─> Embed attested claims (geolocation, TPM attestation)
    ├─> Sign with SPIRE Server CA
    │
    └─> POST /agent/attest-agent (response)
        │
        └─> SPIRE Agent (Low Privilege)
            │
            ├─> Receives Agent SVID
            ├─> Agent can now authenticate
            └─> Ready to request workload SVIDs
                │
                └─> ✓ Attestation Complete
```


┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              KEY SECURITY MECHANISMS                                         │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

1. **TPM Hardware Security**
   - EK (Endorsement Key): Permanent TPM identity
   - AK (Attestation Key): Ephemeral attestation identity
   - App Key: Workload-specific key in TPM
   - TPM2_Certify: AK certifies App Key exists in TPM

2. **On-Demand Quote Fetching**
   - Verifier fetches fresh quote with challenge nonce
   - Prevents replay attacks
   - Ensures quote freshness

3. **Delegated Certification**
   - App Key certified by TPM AK
   - Proves App Key exists in TPM
   - Cryptographic binding to hardware

4. **Certificate Chain**
   - Agent SVID contains TPM attestation claims
   - Workload SVID chain includes agent SVID
   - Policy enforcement at multiple levels

5. **Nonce-Based Freshness**
   - SPIRE Server provides challenge nonce
   - Included in TPM quote and App Key certificate
   - Prevents replay attacks

6. **Mobile Location Verification**
   - Geolocation sensor ID extracted from TPM quote
   - Verifier calls mobile location verification microservice
   - Microservice verifies device location via CAMARA APIs
   - Attestation fails if location verification fails
   - Enables geofencing and location-based policy enforcement
```

---

## Mobile Location Verification Microservice

**Status:** ✅ Implemented and integrated

**Implementation Details:**
- **Database**: SQLite database (`sensor_mapping.db`) stores sensor_id → MSISDN, latitude, longitude, accuracy mappings
- **Default Seed**: `12d1:1433 → tel:%2B34696810912, 40.33, -3.7707, 7.0`
- **Communication**: Keylime Verifier connects to microservice via REST API (HTTP/JSON) over TCP (port 9050)
  - Note: UDS support was deferred (similar to SPIRE Agent TPM Plugin Server (Sidecar) → Keylime Agent communication)
- **Sensor ID Extraction**: Verifier extracts `sensor_id` from TPM quote response geolocation data (no hardcoded defaults)
- **CAMARA API Flow**: Microservice implements three-step CAMARA API sequence:
  1. `POST /bc-authorize` with `login_hint` (phone number) and `scope`
  2. `POST /token` with `grant_type=urn:openid:params:grant-type:ciba` and `auth_req_id`
  3. `POST /location/v0/verify` with `access_token`, `ueId` (phone number), `latitude`, `longitude`, `accuracy`
- **Verification Result**: Microservice returns `{"verification_result": true/false, ...}` to verifier
- **Attestation Gating**: If `verification_result` is `false`, or if the verifier cannot reach the microservice, the Keylime Verifier fails the attestation with error "mobile sensor location verification failed" and the SPIRE Server does not issue the SVID to the SPIRE Agent
- **Configuration**: 
  - `mobile_sensor_enabled` in verifier config (default: false, set to true to enable)
  - `mobile_sensor_endpoint` in verifier config (default: `http://127.0.0.1:9050`)
  - `CAMARA_BYPASS` environment variable (default: false, set to true to skip CAMARA APIs for testing)
  - `MOBILE_SENSOR_LATITUDE`, `MOBILE_SENSOR_LONGITUDE`, `MOBILE_SENSOR_ACCURACY` environment variables for coordinate overrides

**Location:**
- `code-rollout-phase-3/mobile-sensor-microservice/service.py` - Flask microservice implementation
- `code-rollout-phase-2/keylime/keylime/cloud_verifier_tornado.py` - Verifier integration (`_verify_mobile_sensor_geolocation`)
- `keylime/verifier.conf.minimal` - Configuration (`[verifier]` section)

## Gaps to be Addressed

### 1. SPIRE Agent TPM Plugin Server (Sidecar) → Keylime Agent: Use UDS for Security

**Current State:** Communication uses HTTPS/mTLS over localhost (`https://127.0.0.1:9002`)

**Status:** ✅ mTLS implemented (Gap #2 fix)
- SPIRE Agent TPM Plugin Server (Sidecar) now uses HTTPS with client certificate authentication (mTLS)
- SPIRE Agent TPM Plugin Server (Sidecar) uses verifier's client certificate (signed by verifier's CA, which agent trusts)
- Agent requires and verifies client certificate from SPIRE Agent TPM Plugin Server (Sidecar)
- Communication is encrypted and authenticated

**Remaining Gap:** UDS support (preferred over TCP for localhost communication)

**Required for UDS:**
- Implement UDS socket support in rust-keylime agent for the delegated certification endpoint
- Update SPIRE Agent TPM Plugin Server (Sidecar) client to use UDS instead of HTTPS
- Protocol can be HTTP/JSON or pure JSON over UDS
- Default UDS path: `/tmp/keylime-agent.sock` or similar

**Location:**
- `code-rollout-phase-3/tpm-plugin/delegated_certification.py` - Now uses HTTPS/mTLS (client certificate from verifier's CA)
- `code-rollout-phase-2/rust-keylime/keylime-agent/src/main.rs` - Needs UDS socket binding support

---

### 2. Keylime Verifier to Mobile Location Verification Microservice: Use UDS for Security

**Current State:** Communication is hardcoded to HTTP over localhost (`http://127.0.0.1:9050`)

**Issue:** HTTP over TCP is less secure than UDS; traffic could be intercepted or spoofed

**Required:**
- Implement UDS socket support in mobile location verification microservice
- Update verifier to use UDS instead of HTTP
- Protocol can be HTTP/JSON or pure JSON over UDS
- Default UDS path: `/tmp/mobile-sensor.sock` or similar

**Location:**
- `keylime/keylime/cloud_verifier_tornado.py` - Verifier integration (`_verify_mobile_sensor_geolocation`)
- `mobile-sensor-microservice/service.py` (needs UDS socket binding support)

---

### 3. Keylime Testing Mode: EK Certificate Verification Disabled

**Current State:** Keylime is running in testing mode (`KEYLIME_TEST=on`), which disables EK certificate verification for TPM emulators.

**Issue:** 
- EK (Endorsement Key) certificate verification is disabled when `KEYLIME_TEST=on` is set
- This is a security gap as it bypasses verification of the TPM's endorsement key certificate
- The warning message indicates: "WARNING: running keylime in testing mode. Keylime will: - Not check the ekcert for the TPM emulator"
- While hardware TPM is being used, the testing mode still disables EK cert checks

**Required:**
- Remove `KEYLIME_TEST=on` environment variable from test scripts and production deployments
- Enable EK certificate verification by default for production use
- Ensure EK certificate store is properly configured (`tpm_cert_store` in Keylime config)
- For testing with hardware TPM, EK certificates should still be verified (testing mode is only needed for TPM emulators)

**Location:**
- `test_complete.sh` - Sets `export KEYLIME_TEST=on` (lines 972, 1003, 1113, 1166, 1685)
- `keylime/keylime/config.py` - Testing mode detection and EK cert check disabling (lines 62-70)
- `keylime/verifier.conf.minimal` - May need `tpm_cert_store` configuration for EK verification

---

### 4. rust-keylime Agent: Using /dev/tpm0 Instead of /dev/tpmrm0 and Persistent Handles

**Current State:** 
- rust-keylime agent is using `/dev/tpm0` (direct TPM device) instead of `/dev/tpmrm0` (TPM resource manager)
- Agent uses persistent handles for TPM keys (e.g., App Key at `0x8101000B`)

**Issues:**
1. **Direct TPM Device Access (`/dev/tpm0`):**
   - Using `/dev/tpm0` directly bypasses the TPM resource manager (`tpm2-abrmd`)
   - Resource manager provides better session management, handle management, and concurrent access control
   - Direct access can lead to handle conflicts and resource contention
   - The test script sets `TCTI="device:/dev/tpmrm0"` but rust-keylime agent logs show it's using `/dev/tpm0`

2. **Persistent Handles:**
   - App Key is persisted at handle `0x8101000B` in the TPM
   - Persistent handles survive reboots but can cause issues:
     - Handle conflicts if multiple processes access the same handle
     - Resource exhaustion if handles are not properly managed
     - Security concerns if handles are not properly protected

**Required:**
1. **Force rust-keylime agent to use `/dev/tpmrm0`:**
   - Ensure `TCTI` environment variable is set to `device:/dev/tpmrm0` when starting rust-keylime agent
   - Verify `tpm2-abrmd` resource manager is running before starting the agent
   - Update rust-keylime default TCTI detection to prefer `/dev/tpmrm0` over `/dev/tpm0`

2. **Persistent Handle Management:**
   - Document persistent handle usage and lifecycle
   - Ensure proper cleanup of persistent handles when needed
   - Consider using transient handles with context files for better isolation
   - Add handle conflict detection and resolution

**Location:**
- `test_complete.sh` - TCTI configuration for rust-keylime agent (lines 1238-1246, 1418, 1432)
- `rust-keylime/keylime/src/tpm.rs` - TCTI detection defaults to `/dev/tpmrm0` but may fall back to `/dev/tpm0` (lines 578-586)
- `rust-keylime/keylime-agent/src/main.rs` - Agent startup and TCTI usage (lines 365, 615, 790)
- `tpm-plugin/tpm_plugin.py` - App Key persistent handle `0x8101000B` (line 59)

---

### 5. SPIRE TPM Plugin: Uses TSS Subprocess Calls Instead of TSS Library

**Current State:** 
- SPIRE TPM Plugin uses `subprocess.run()` to call tpm2-tools commands instead of using the TSS library (tss_esapi) directly
- Commands executed via subprocess: `tpm2_createprimary`, `tpm2_create`, `tpm2_load`, `tpm2_evictcontrol`, `tpm2_readpublic`

**Issues:**
1. **Performance Overhead:**
   - Subprocess calls have significant overhead (process creation, IPC, parsing output)
   - Each TPM operation requires spawning a new process
   - Slower than direct TSS library calls

2. **Error Handling:**
   - Subprocess calls require parsing stdout/stderr for error information
   - Less granular error handling compared to TSS library error codes
   - Harder to debug TPM operation failures

3. **Security:**
   - Subprocess calls rely on external tpm2-tools binaries
   - Potential for command injection if inputs are not properly sanitized
   - Less control over TPM session management

4. **Dependency Management:**
   - Requires tpm2-tools to be installed and in PATH
   - Version compatibility issues between tpm2-tools and TPM firmware
   - Additional dependency to maintain

**Required:**
- Migrate TPM operations to use TSS library (tss_esapi for Python or equivalent)
- Replace subprocess calls with direct TSS API calls:
  - `tpm2_createprimary` → TSS `CreatePrimary`
  - `tpm2_create` → TSS `Create`
  - `tpm2_load` → TSS `Load`
  - `tpm2_evictcontrol` → TSS `EvictControl`
  - `tpm2_readpublic` → TSS `ReadPublic`
- Implement proper TSS context management and session handling
- Maintain backward compatibility during migration

**Location:**
- `tpm-plugin/tpm_plugin.py` - All TPM operations use `_run_tpm_command()` which calls subprocess (lines 110-141, 188-272)
- `tpm-plugin/tpm_plugin.py` - Commands: `tpm2_createprimary` (line 218), `tpm2_create` (line 229), `tpm2_load` (line 242), `tpm2_evictcontrol` (line 252), `tpm2_readpublic` (lines 188, 263, 269)

---

### 6. rust-keylime Agent: Uses TSS Subprocess Calls Instead of TSS Library

**Current State:**
- rust-keylime agent uses `USE_TPM2_QUOTE_DIRECT=1` environment variable to call `tpm2_quote` as a subprocess instead of using TSS library
- Also uses `tpm2 createek` and `tpm2 createak` subprocess calls when `USE_TPM2_QUOTE_DIRECT` is set
- This is a workaround for deadlock issues with TSS library when using hardware TPM

**Issues:**
1. **Deadlock Workaround:**
   - The subprocess approach is used to avoid deadlocks with TSS library context locks
   - When using TSS library directly, quote operations can deadlock with hardware TPM
   - The workaround switches from `/dev/tpmrm0` to `/dev/tpm0` to avoid resource manager deadlocks

2. **Performance Overhead:**
   - Subprocess calls have overhead (process creation, IPC, file I/O for context files)
   - Quote operations take ~10 seconds with subprocess approach
   - Direct TSS library calls would be faster if deadlock issue is resolved

3. **Inconsistency:**
   - Agent uses TSS library (`tss_esapi`) for most operations but subprocess for quotes
   - Mixed approach makes codebase harder to maintain
   - Different error handling paths for TSS vs subprocess operations

4. **Resource Manager Bypass:**
   - Subprocess approach switches from `/dev/tpmrm0` to `/dev/tpm0` to avoid deadlocks
   - This bypasses the TPM resource manager, which provides better session management
   - Can lead to handle conflicts and resource contention (see Gap #4)

**Required:**
1. **Fix TSS Library Deadlock:**
   - Investigate and fix root cause of deadlocks with TSS library and hardware TPM
   - May be related to context lock management or resource manager interaction
   - Consider TSS library version updates or patches

2. **Migrate to Pure TSS Library:**
   - Remove `USE_TPM2_QUOTE_DIRECT` workaround once deadlock is fixed
   - Use TSS library `Quote` operation directly instead of subprocess
   - Replace `tpm2 createek` and `tpm2 createak` with TSS library calls

3. **Maintain Resource Manager:**
   - Ensure TSS library operations work with `/dev/tpmrm0` (resource manager)
   - Avoid switching to `/dev/tpm0` as workaround
   - Proper session and context management with resource manager

**Location:**
- `rust-keylime/keylime/src/tpm.rs` - `perform_quote_with_tpm2_command()` and `perform_quote_with_tpm2_command_using_context()` functions (lines 2582-2814, 2816-3040)
- `rust-keylime/keylime/src/tpm.rs` - Uses `Command::new("tpm2_quote")` for subprocess calls (lines 2682, 2939)
- `rust-keylime/keylime-agent/src/main.rs` - `USE_TPM2_QUOTE_DIRECT` flag usage and `tpm2 createek`/`tpm2 createak` subprocess calls (lines 331, 368, 582-583)
- `test_complete.sh` - Sets `USE_TPM2_QUOTE_DIRECT=1` environment variable (lines 1401-1404, 1418, 1420, 1432, 1434, 1447)

---

### Additional Considerations

- **Certificate Verification Error Handling**: If certificate verification fails, the verifier should reject the attestation
- **Nonce Validation in Certificate**: When verifying the certificate, validate that the nonce matches the one from SPIRE Server
- **Geolocation Data Format**: Geolocation is structured as `{"type": "mobile"|"gnss", "sensor_id": "<id>", "value": "<optional>"}` in the quote response
- **Mobile Location Verification**: When mobile geolocation is detected, location verification is mandatory; attestation fails if CAMARA verification fails
- **UDS Socket Permissions**: Ensure proper file permissions and ownership for UDS sockets (when UDS support is added)
- **mTLS Certificate Management**: Ensure verifier and agent have proper certificate chains and trust anchors
