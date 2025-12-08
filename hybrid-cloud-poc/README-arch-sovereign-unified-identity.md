# Sovereign Unified Identity Architecture - End-to-End Flow

## End-to-End Flow Visualization

### Detailed Flow Diagram (Full View)

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                      SOVEREIGN UNIFIED IDENTITY - END-TO-END FLOW                                                   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

SETUP PHASE:
┌──────────────┐  [1]  ┌──────────────┐                    ┌──────────────┐  [2]
│ rust-keylime │──────>│   Keylime    │                    │  TPM Plugin  │
│    Agent     │       │  Registrar   │                    │   Server     │
│ Generate EK  │       │ Store: UUID, │                    │ Generate App │
│ Generate AK  │       │ IP, Port, AK │                    │     Key      │
└──────────────┘       └──────────────┘                    └──────────────┘

SPIRE AGENT ATTESTATION PHASE:
┌──────────────┐  [3]  ┌──────────────┐  [4]  ┌──────────────┐  [5]  ┌──────────────┐  [6]  ┌──────────────┐  [7]  ┌──────────────┐
│  SPIRE Agent │──────>│  TPM Plugin  │──────>│ rust-keylime │──────>│  TPM Plugin  │──────>│  SPIRE Agent │──────>│ SPIRE Server │
│ Request App  │       │   Server     │       │    Agent     │       │   Server     │       │ Build        │       │ Receive      │
│ Key & Cert   │       │ Forward      │       │ TPM2_Certify │       │ Return Cert  │       │ Attestation  │       │ Attestation  │
│              │       │              │       │ (AK signs    │       │              │       │              │       │ Extract      │
└──────────────┘       └──────────────┘       │  App Key)    │       └──────────────┘       └──────────────┘       └──────────────┘
                                              └──────────────┘

SPIRE SERVER and KEYLIME VERIFIER VERIFICATION PHASE:
┌──────────────┐  [8]  ┌──────────────┐  [9]  ┌──────────────┐  [10] ┌──────────────┐  [11] ┌──────────────┐  [12] ┌──────────────┐  [13] ┌──────────────┐  [14] ┌──────────────┐  [15] ┌──────────────┐
│ SPIRE Server │──────>│ Keylime      │──────>│   Keylime    │──────>│ Keylime      │──────>│ rust-keylime │──────>│ Mobile Sensor│──────>│ rust-keylime │──────>│ Keylime      │──────>│ SPIRE Server │
│ Extract: App │       │ Verifier     │       │  Registrar   │       │ Verifier     │       │    Agent     │       │ Microservice │       │    Agent     │       │ Verifier     │       │ Issue Agent  │
│ Key, Cert,   │       │ Verify App   │       │ Return: IP,  │       │ Request TPM  │       │ Generate     │       │ Verify       │       │ Return Quote │       │ Verify Quote │       │ SVID with    │
│ Nonce, UUID  │       │ Key Cert     │       │ Port, AK,    │       │ Quote        │       │ TPM Quote    │       │ Location     │       │ + Geolocation│       │ Verify Cert  │       │ BroaderClaims│
└──────────────┘       └──────────────┘       │ mTLS Cert    │       └──────────────┘       │ (with geo)   │       │ (Optional)   │       └──────────────┘       │ Verify Geo   │       └──────────────┘
                                              └──────────────┘                              └──────────────┘       └──────────────┘                              │ Return       │
                                                                                                                                                                 │ BroaderClaims│
                                                                                                                                                                 └──────────────┘

SPIRE AGENT SVID ISSUANCE & WORKLOAD SVID ISSUANCE:
┌──────────────┐  [16] ┌──────────────┐  [17] ┌──────────────┐  [18] ┌──────────────┐  [19] ┌──────────────┐  [20] ┌──────────────┐  [21] ┌──────────────┐
│ SPIRE Server │──────>│  SPIRE Agent │──────>│   Workload   │──────>│  SPIRE Agent │──────>│ SPIRE Server │──────>│ SPIRE Agent  │──────>│   Workload   │
│ Issue Agent  │       │ Receive      │       │ (Application)│       │ Match Entry  │       │ Issue        │       │ Forward      │       │ Receive      │
│ SVID with    │       │ Agent SVID   │       │ Request SVID │       │ Forward      │       │ Workload SVID│       │ Request      │       │ Workload SVID│
│ BroaderClaims│       └──────────────┘       └──────────────┘       └──────────────┘       │ (inherit     │       └──────────────┘       └──────────────┘
└──────────────┘                                                                            │ agent claims)│
                                                                                            └──────────────┘
```

### Legend:

**[1]** Agent Registration: EK, AK, UUID, IP, Port, mTLS Cert  
**[2]** App Key Generation: TPM App Key created and persisted  
**[3]** App Key Request: Agent requests App Key public key and context  
**[4]** Delegated Certification Request: TPM Plugin forwards to rust-keylime agent  
**[5]** Certificate Response: TPM2_Certify result (AK-signed App Key certificate)  
**[6]** Build Attestation: Assemble SovereignAttestation (App Key, Cert, Nonce, UUID)  
**[7]** Send Attestation: SPIRE Agent sends SovereignAttestation to SPIRE Server (Server receives and extracts)  
**[8]** Lookup Agent: Verifier queries Registrar for agent info (IP, Port, AK, mTLS Cert)  
**[9]** Agent Info: Registrar returns agent details  
**[10]** Quote Request: Verifier requests fresh TPM quote with challenge nonce  
**[11]** Geolocation Detection: Agent detects mobile sensor, includes in quote  
**[12]** Location Verification: Verifier calls mobile sensor microservice (CAMARA APIs)*  
**[13]** Quote Response: Agent returns TPM quote with geolocation data  
**[14]** Verification Result: Verifier returns BroaderClaims (geolocation, TPM attestation) → SPIRE Server  
**[15]** Agent SVID: Server issues agent SVID with BroaderClaims embedded → SPIRE Agent  
**[16]** Workload Request: Workload connects to Agent Workload API  
**[17]** Workload API: Workload requests SVID via Agent Workload API  
**[18]** Forward Request: Agent forwards workload SVID request to Server  
**[19]** Spire Server Issues Workload SVID: Server issues workload SVID (inherits agent claims, no Keylime call) to spire agent
**[20]** Spire Agent Returns SVID: Agent returns workload SVID to workload  
**[21]** Workload Receives SVID: Workload receives workload SVID from SPIRE Agent  

### Key Components:

- **rust-keylime Agent**: High-privilege TPM operations (EK, AK, Quotes, Certify)
- **TPM Plugin Server**: App Key generation, delegated certification client
- **SPIRE Agent**: Low-privilege, Workload API, attestation orchestration
- **SPIRE Server**: SVID issuance, policy enforcement, Keylime integration
- **Keylime Verifier**: TPM attestation verification, geolocation verification
- **Keylime Registrar**: Agent registration database
- **Mobile Sensor Microservice**: Location verification via CAMARA APIs (invoked only when the TPM quote reports a physical mobile sensor, e.g., USB `lsusb` detection)

*The verifier skips this step entirely when no TPM-reported Mobile/GNSS sensor is present, so Sovereign SVIDs omit `grc.geolocation` in that case.*

---

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
   - The SPIRE Agent sends a POST request to `/get-app-key` endpoint on the SPIRE Agent TPM Plugin Server (sidecar) via UDS
   - The SPIRE Agent TPM Plugin Server (sidecar) returns the App Key public key (PEM format) in JSON response

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
    - If a mobile sensor is detected (sensor_id, sensor_imei, or sensor_imsi present), the verifier proceeds to location verification
    - Geolocation data includes: sensor type (mobile/gnss), sensor_id, sensor_imei, sensor_imsi, and optional value (for GNSS)

14. **Verifier Calls Mobile Location Verification Microservice** (if mobile geolocation detected)
    - The verifier extracts the sensor_id, sensor_imei, and/or sensor_imsi from the geolocation data
    - The verifier calls the mobile location verification microservice via REST API (HTTP)
    - Request: `POST /verify` with `{"sensor_id": "<sensor_id>", "sensor_imei": "<imei>", "sensor_imsi": "<imsi>"}` (all fields optional)
    - The microservice:
      - Looks up the sensor in SQLite database (priority: sensor_id > sensor_imei > sensor_imsi) to get phone number (MSISDN) and default coordinates
      - Calls CAMARA APIs in sequence (if CAMARA_BYPASS=false):
        1. `POST /bc-authorize` with login_hint (phone number) and scope (reuses cached auth_req_id if available)
        2. `POST /token` with grant_type and auth_req_id (reuses cached access_token if still valid)
        3. `POST /location/v0/verify` with access_token, ueId, latitude, longitude, accuracy
      - Returns verification result: `{"verification_result": true/false, "sensor_id": "...", "sensor_imei": "...", "sensor_imsi": "...", "latitude": ..., "longitude": ..., "accuracy": ...}`
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
- **Mobile Location Verification**: When mobile geolocation is detected in the TPM quote (sensor_id, sensor_imei, or sensor_imsi present), the verifier calls the mobile location verification microservice to verify the device location via CAMARA APIs; attestation fails if location verification fails
- **TPM Plugin Server Communication**: SPIRE Agent communicates with TPM Plugin Server via JSON over UDS (Unix Domain Socket) for security and performance
- **Delegated Certification Transport**: TPM Plugin Server uses HTTPS/mTLS (port 9002) to communicate with rust-keylime agent (UDS support deferred)
- **Token Caching**: Mobile location verification microservice caches CAMARA auth_req_id (persisted to file) and access_token (with expiration) to reduce API calls and improve performance

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
SPIRE Agent TPM Plugin Server (Python Sidecar, UDS Socket: /tmp/spire-data/tpm-plugin/tpm-plugin.sock)
    │
    ├─> Generate App Key in TPM on startup
    ├─> Store App Key context/handle
    ├─> Start HTTP/UDS server
    └─> Ready for certification requests
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
    └─> POST /get-app-key (JSON over UDS)
        │
        └─> SPIRE Agent TPM Plugin Server (Sidecar, UDS: /tmp/spire-data/tpm-plugin/tpm-plugin.sock)
            │
            └─> Return: { "status": "success", "app_key_public": "<PEM>" }
                │
                <─ SPIRE Agent
                    │
                    └─> Receives: App Key public key (PEM format)
```

**Step 5: Delegated Certification Request**
```
SPIRE Agent TPM Plugin Server (Sidecar)
    │
    └─> POST /request-certificate (JSON over UDS)
        │   Request: { "app_key_public": "<PEM>", "challenge_nonce": "<nonce>", "endpoint": "https://127.0.0.1:9002" }
        │
        └─> DelegatedCertificationClient
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
                            │
                            └─> Return: { "status": "success", "app_key_certificate": "<base64>", "agent_uuid": "<uuid>" }
                                │
                                <─ SPIRE Agent
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
    ├─> Extract sensor_id, sensor_imei, sensor_imsi if mobile type
    │
    └─> POST /verify (HTTP/JSON)
        │   Request: { "sensor_id": "12d1:1433", "sensor_imei": "...", "sensor_imsi": "..." }
        │
        └─> Mobile Location Verification Microservice (Port 9050, configurable via mobile_sensor_endpoint)
            │
            ├─> Lookup sensor in SQLite database (priority: sensor_id > sensor_imei > sensor_imsi)
            │   └─> Get MSISDN, lat, lon, accuracy
            │
            ├─> Call CAMARA APIs (if CAMARA_BYPASS=false):
            │   ├─> POST /bc-authorize (reuse cached auth_req_id if available)
            │   ├─> POST /token (reuse cached access_token if valid)
            │   └─> POST /location/v0/verify
            │
            └─> Return: { "verification_result": true/false, "sensor_id": "...", "sensor_imei": "...", "sensor_imsi": "...", "latitude": ..., "longitude": ..., "accuracy": ... }
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
   - Geolocation sensor identifiers (sensor_id, sensor_imei, sensor_imsi) extracted from TPM quote
   - Verifier calls mobile location verification microservice with sensor identifiers
   - Microservice looks up sensor in database (priority: sensor_id > sensor_imei > sensor_imsi)
   - Microservice verifies device location via CAMARA APIs (with token caching for performance)
   - Attestation fails if location verification fails
   - Enables geofencing and location-based policy enforcement

---

## Mobile Location Verification Microservice

**Status:** ✅ Implemented and integrated

**Implementation Details:**
- **Database**: SQLite database (`sensor_mapping.db`) stores sensor_id, sensor_imei, sensor_imsi → MSISDN, latitude, longitude, accuracy mappings
  - Schema: `sensor_map(sensor_id TEXT, sensor_imei TEXT, sensor_imsi TEXT, msisdn TEXT, latitude REAL, longitude REAL, accuracy REAL, PRIMARY KEY (sensor_id, sensor_imei, sensor_imsi))`
  - Lookup priority: sensor_id > sensor_imei > sensor_imsi
- **Default Seed**: `12d1:1433 → tel:%2B34696810912, 40.33, -3.7707, 7.0` (with optional sensor_imei and sensor_imsi)
- **Communication**: Keylime Verifier connects to microservice via REST API (HTTP/JSON) over TCP (port 9050 by default, configurable via `mobile_sensor_endpoint`)
  - Note: UDS support was deferred (similar to SPIRE Agent TPM Plugin Server (Sidecar) → Keylime Agent communication)
- **Sensor ID Extraction**: Verifier extracts `sensor_id`, `sensor_imei`, and/or `sensor_imsi` from TPM quote response geolocation data (no hardcoded defaults)
- **CAMARA API Flow**: Microservice implements three-step CAMARA API sequence:
  1. `POST /bc-authorize` with `login_hint` (phone number) and `scope` (auth_req_id is cached and reused)
  2. `POST /token` with `grant_type=urn:openid:params:grant-type:ciba` and `auth_req_id` (access token is cached with expiration)
  3. `POST /location/v0/verify` with `access_token`, `ueId` (phone number), `latitude`, `longitude`, `accuracy`
- **Token Caching**: The microservice caches `auth_req_id` (persisted to file) and `access_token` (with expiration) to reduce API calls
- **Verification Result**: Microservice returns `{"verification_result": true/false, "sensor_id": "...", "sensor_imei": "...", "sensor_imsi": "...", "latitude": ..., "longitude": ..., "accuracy": ...}` to verifier
- **Attestation Gating**: If `verification_result` is `false`, or if the verifier cannot reach the microservice, the Keylime Verifier fails the attestation with error "mobile sensor location verification failed" and the SPIRE Server does not issue the SVID to the SPIRE Agent
- **Configuration**: 
  - `mobile_sensor_enabled` in verifier config (default: false, set to true to enable)
  - `mobile_sensor_endpoint` in verifier config (default: `http://127.0.0.1:9050`)
  - `CAMARA_BYPASS` environment variable (default: false, set to true to skip CAMARA APIs for testing)
  - `CAMARA_BASIC_AUTH` environment variable (required for CAMARA API authentication)
  - `CAMARA_AUTH_REQ_ID` environment variable (optional, pre-obtained auth_req_id)
  - `MOBILE_SENSOR_DB` environment variable (default: `sensor_mapping.db`)
  - `MOBILE_SENSOR_LATITUDE`, `MOBILE_SENSOR_LONGITUDE`, `MOBILE_SENSOR_ACCURACY` environment variables for coordinate overrides
  - `MOBILE_SENSOR_IMEI`, `MOBILE_SENSOR_IMSI` environment variables for sensor identifiers

**Location:**
- `mobile-sensor-microservice/service.py` - Flask microservice implementation
- `keylime/keylime/cloud_verifier_tornado.py` - Verifier integration (`_verify_mobile_sensor_geolocation`)
- `keylime/verifier.conf.minimal` - Configuration (`[verifier]` section)
- `tpm-plugin/tpm_plugin_server.py` - SPIRE Agent TPM Plugin Server (sidecar) implementation
- `tpm-plugin/delegated_certification.py` - Delegated certification client implementation
