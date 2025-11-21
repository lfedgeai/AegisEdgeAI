# Sovereign Unified Identity Architecture - End-to-End Flow

## End-to-End Flow: SPIRE Agent Sovereign SVID Attestation

### Phase 1: Initial Setup (Before Attestation)

1. **rust-keylime Agent Registration**
   - The rust-keylime agent starts and registers with the Keylime Registrar
   - The agent generates its TPM Endorsement Key (EK) and Attestation Key (AK)
   - The registrar stores the agent's UUID, IP address, port, TPM keys, and mTLS certificate
   - The agent is now registered and ready to serve attestation requests

2. **TPM Plugin Server Startup**
   - The TPM Plugin Server starts and generates an App Key in the TPM
   - The App Key is a workload-specific key used for identity attestation
   - The App Key context (handle) is stored for later use

### Phase 2: SPIRE Agent Attestation Request

3. **SPIRE Agent Initiates Attestation**
   - The SPIRE Agent needs to attest to the SPIRE Server to get its agent SVID
   - The SPIRE Server sends a challenge nonce to the agent
   - The agent must prove its identity using TPM-based attestation

4. **SPIRE Agent Requests App Key Information**
   - The SPIRE Agent calls its TPM Plugin Gateway to build a SovereignAttestation
   - The TPM Plugin Gateway requests the App Key public key and context from the TPM Plugin Server
   - The TPM Plugin Server returns the App Key public key (PEM format) and context file path

5. **Delegated Certification Request**
   - The TPM Plugin Gateway requests an App Key certificate from the TPM Plugin Server
   - The TPM Plugin Server forwards this request to the rust-keylime agent's delegated certification endpoint
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

### Phase 3: SPIRE Server Verification

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

10. **Verifier Fetches TPM Quote On-Demand**
    - The verifier connects to the rust-keylime agent (over HTTP for localhost agents)
    - It requests a fresh TPM quote using the challenge nonce from SPIRE Server
    - The agent generates a TPM quote containing:
      - Platform Configuration Register (PCR) values showing system state
      - The challenge nonce
      - Signed by the TPM's Attestation Key (AK)
    - The quote is returned to the verifier

11. **Verifier Verifies the Quote**
    - The verifier uses the AK public key (from registrar) to verify the quote signature
    - It verifies the nonce matches the one from SPIRE Server (freshness check)
    - It validates the hash algorithm and quote structure
    - This proves the TPM is genuine and the platform state is authentic

12. **Verifier Retrieves Attested Claims**
    - The verifier calls the fact provider to get optional metadata (geolocation, GPU metrics, etc.)
    - In Phase 3, this typically returns empty since agents aren't registered with the verifier
    - The verifier prepares the verification response

13. **Verifier Returns Verification Result**
    - The verifier returns a verification response to SPIRE Server containing:
      - Verification status (success/failure)
      - Attested claims (if any)
      - Verification details (quote signature valid, nonce valid, etc.)

### Phase 5: SPIRE Server Issues SVID

14. **SPIRE Server Validates Verification Result**
    - The SPIRE Server receives the verification result from Keylime Verifier
    - If verification succeeded, the server proceeds to issue the agent SVID

15. **SPIRE Server Issues Sovereign SVID**
    - The SPIRE Server creates an X.509 certificate (SVID) for the SPIRE Agent
    - The SVID includes the attested claims from Keylime Verifier (if any)
    - The SVID is embedded with metadata proving the agent's TPM-based identity
    - The SVID is returned to the SPIRE Agent

16. **SPIRE Agent Receives SVID**
    - The SPIRE Agent receives its agent SVID from SPIRE Server
    - The agent can now use this SVID to authenticate and request workload SVIDs
    - The attestation process is complete

### Key Design Points

- **On-Demand Quote Fetching**: The verifier fetches quotes directly from the agent when needed, ensuring freshness with the challenge nonce
- **Delegated Certification**: The App Key is certified by the TPM's AK, proving it exists in the TPM
- **Separation of Concerns**: Quote generation (platform attestation) is separate from App Key certification (workload identity)
- **No Periodic Polling**: Unlike traditional Keylime, agents aren't continuously monitored; verification happens on-demand per attestation request
- **Agent Registration Model**: Agents register with the Keylime Registrar (persistent storage) but are not registered with the Keylime Verifier (on-demand lookup only)

This flow provides hardware-backed identity attestation where the SPIRE Agent proves its identity using the TPM, and the SPIRE Server verifies this proof through the Keylime Verifier before issuing credentials.

---

## End-to-End Flow: Workload SVID Issuance

The workload SVID flow follows the standard SPIRE pattern, with the key difference being the certificate chain that includes the agent SVID (which contains TPM attestation claims). This allows workloads to inherit the TPM-backed identity of their hosting agent.

### Phase 1: Workload Registration

1. **Registration Entry Creation**
   - An administrator creates a registration entry for the workload in the SPIRE Server
   - The entry defines the workload's SPIFFE ID (e.g., `spiffe://example.org/python-app`)
   - The entry specifies the selector criteria (e.g., Unix UID, process name, etc.)
   - The registration entry is stored in the SPIRE Server's database

### Phase 2: Workload Requests SVID

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

### Phase 3: SPIRE Server Issues Workload SVID

5. **SPIRE Server Validates Request**
   - The SPIRE Server authenticates the agent using the agent's SVID
   - The server verifies the agent SVID's certificate chain and signature
   - The server validates that the agent is authorized to request SVIDs for the specified workload

6. **SPIRE Server Extracts Agent Attestation Claims**
   - The SPIRE Server extracts the AttestedClaims from the agent SVID
   - These claims include TPM attestation data (geolocation, TPM quote, etc.)
   - The server prepares to issue a workload SVID with workload-specific claims only

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

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                          PHASE 1: INITIAL SETUP (Before Attestation)                        │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────┐                    ┌──────────────────────┐
│  rust-keylime Agent   │                    │  Keylime Registrar  │
│  (High Privilege)     │                    │  (Port 8890)         │
│  Port 9002           │                    │                      │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 1. Register Agent                        │
            │    - Generate EK (Endorsement Key)      │
            │    - Generate AK (Attestation Key)       │
            │    - Send UUID, IP, port, TPM keys       │
            └──────────────────────────────────────────>│
            │                                           │
            │ 2. Store Registration                    │
            │    - UUID, IP:port, TPM AK, mTLS cert   │
            │<──────────────────────────────────────────┘
            │
            │
┌───────────┴──────────┐
│  TPM Plugin Server    │
│  (Python)             │
│  UDS Socket           │
└───────────┬───────────┘
            │
            │ 3. Generate App Key
            │    - Create App Key in TPM
            │    - Store context/handle
            │    - Ready for certification


┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                    PHASE 2: SPIRE AGENT ATTESTATION REQUEST                                  │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────┐                    ┌──────────────────────┐
│   SPIRE Server       │                    │   SPIRE Agent        │
│   (Port 8081)        │                    │   (Low Privilege)    │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 4. Challenge Nonce                        │
            │    POST /agent/attest-agent               │
            │    { nonce: <challenge> }                 │
            │<───────────────────────────────────────────┘
            │
            │
┌───────────┴──────────┐                    ┌───────────┴──────────┐
│  TPM Plugin Gateway  │                    │  TPM Plugin Server   │
│  (Go)                │                    │  (Python)            │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 5. Request App Key Info                  │
            │    - Get App Key public key (PEM)        │
            │    - Get App Key context                │
            └──────────────────────────────────────────>│
            │                                           │
            │ 6. Return App Key                        │
            │    - App Key public key (PEM)            │
            │    - App Key context path                │
            │<──────────────────────────────────────────┘
            │
            │
┌───────────┴──────────┐                    ┌───────────┴──────────┐
│  TPM Plugin Server   │                    │  rust-keylime Agent   │
│  (Python)            │                    │  (High Privilege)    │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 7. Request App Key Certificate           │
            │    POST /v2.2/delegated_certification/  │
            │         certify_app_key                  │
            │    { app_key_public_pem,                 │
            │      app_key_context_path }              │
            └──────────────────────────────────────────>│
            │                                           │
            │ 8. Perform TPM2_Certify                  │
            │    - Load App Key from context           │
            │    - Use AK to sign App Key public key   │
            │    - Generate certificate (attest + sig) │
            │                                           │
            │ 9. Return Certificate                    │
            │    { certificate: {                      │
            │        certify_data: <base64>,           │
            │        signature: <base64> },            │
            │      agent_uuid: <uuid> }                │
            │<──────────────────────────────────────────┘
            │
            │
┌───────────┴──────────┐                    ┌───────────┴──────────┐
│  TPM Plugin Gateway  │                    │   SPIRE Server       │
│  (Go)                │                    │   (Port 8081)        │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 10. Build SovereignAttestation           │
            │     - App Key public key                 │
            │     - App Key certificate (AK-signed)   │
            │     - Challenge nonce                    │
            │     - Agent UUID                         │
            │     - TPM quote: empty (verifier fetches)│
            │                                           │
            │ 11. Send SovereignAttestation            │
            │     POST /agent/attest-agent             │
            └──────────────────────────────────────────>│


┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                        PHASE 3: SPIRE SERVER VERIFICATION                                   │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────┐                    ┌──────────────────────┐
│   SPIRE Server       │                    │  Keylime Verifier    │
│   (Port 8081)        │                    │  (Port 8881)         │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 12. Verification Request                  │
            │     POST /v2.2/unified_identity/verify   │
            │     { app_key_public_pem,                 │
            │       certificate: { certify_data, sig }, │
            │       nonce,                              │
            │       agent_uuid }                        │
            └──────────────────────────────────────────>│


┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                  PHASE 4: KEYLIME VERIFIER ON-DEMAND VERIFICATION                           │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────┐                    ┌──────────────────────┐
│  Keylime Verifier    │                    │  Keylime Registrar  │
│  (Port 8881)         │                    │  (Port 8890)         │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 13. Lookup Agent Info                     │
            │     GET /agents/{agent_uuid}              │
            └──────────────────────────────────────────>│
            │                                           │
            │ 14. Return Agent Info                    │
            │     { ip, port, tpm_ak, mtls_cert }       │
            │<───────────────────────────────────────────┘
            │
            │
┌───────────┴──────────┐                    ┌───────────┴──────────┐
│  Keylime Verifier    │                    │  rust-keylime Agent │
│  (Port 8881)         │                    │  (High Privilege)    │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 15. Request TPM Quote                    │
            │     POST /v2.2/quote                    │
            │     { nonce: <challenge> }                │
            └──────────────────────────────────────────>│
            │                                           │
            │ 16. Generate TPM Quote                   │
            │     - PCR values (platform state)        │
            │     - Challenge nonce                    │
            │     - Signed by AK                       │
            │                                           │
            │ 17. Return TPM Quote                    │
            │     { quote: <base64>,                    │
            │       signature: <base64> }               │
            │<──────────────────────────────────────────┘
            │
            │
┌───────────┴──────────┐                    ┌───────────┴──────────┐
│  Keylime Verifier    │                    │  Fact Provider       │
│  (Port 8881)         │                    │  (Internal)          │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 18. Get Attested Claims                   │
            │     - Geolocation (if available)          │
            │     - GPU metrics (if available)          │
            │     - Host integrity (if available)       │
            └──────────────────────────────────────────>│
            │                                           │
            │ 19. Return Claims                        │
            │     { geolocation: {...}, ... }           │
            │     (or empty if not available)           │
            │<───────────────────────────────────────────┘
            │
            │
┌───────────┴──────────┐                    ┌───────────┴──────────┐
│  Keylime Verifier    │                    │   SPIRE Server       │
│  (Port 8881)         │                    │   (Port 8081)        │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 20. Verify Evidence                       │
            │     - Verify quote signature (AK)         │
            │     - Verify nonce matches                │
            │     - Validate quote structure            │
            │     - Check certificate structure         │
            │                                           │
            │ 21. Return Verification Result           │
            │     { status: "success",                  │
            │       attested_claims: {                   │
            │         grc.geolocation: {...},           │
            │         grc.tpm-attestation: {...} },     │
            │       verification_details: {...} }        │
            └──────────────────────────────────────────>│


┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                        PHASE 5: SPIRE SERVER ISSUES SVID                                     │
└─────────────────────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────┐                    ┌──────────────────────┐
│   SPIRE Server       │                    │   SPIRE Agent        │
│   (Port 8081)        │                    │   (Low Privilege)    │
└───────────┬──────────┘                    └──────────┬───────────┘
            │                                           │
            │ 22. Validate Verification                 │
            │     - Check verification status           │
            │     - Extract attested claims             │
            │                                           │
            │ 23. Issue Sovereign SVID                  │
            │     - Create X.509 certificate            │
            │     - Embed attested claims               │
            │     - Sign with SPIRE Server CA           │
            │                                           │
            │ 24. Return Agent SVID                     │
            │     { svid: <certificate>,                │
            │       private_key: <key>,                  │
            │       bundle: <trust_bundle> }              │
            └──────────────────────────────────────────>│
            │                                           │
            │ 25. Agent SVID Received                   │
            │     - Agent can now authenticate          │
            │     - Ready to request workload SVIDs     │
            │                                           │
            │ ✓ Attestation Complete                    │


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
   - Included in TPM quote
   - Prevents replay attacks
```

---

## Gaps to be Addressed

### 1. Keylime Verifier — Verify App Key Certificate with Agent TPM AK

**Current State:** Certificate signature is not verified; only structure is checked

**Issue:** No cryptographic proof that the AK actually signed the App Key certification

**Required:**
- Parse `certify_data` and `signature` from the certificate
- Verify the signature using the AK public key (fetched from registrar)
- Ensure `certify_data` contains the correct App Key public key

**Location:** `code-rollout-phase-2/keylime/keylime/cloud_verifier_tornado.py` lines 2005-2020

---

### 2. Keylime Verifier — Fetch Geolocation Sensor Info During Quote Retrieval -- gap fixed
**Current State:** Quote is fetched, but geolocation sensor ID (mobile/gnss) and geolocation details (gnss) are not extracted

**Issue:** Missing sensor metadata for geolocation attestation

**Required:** When fetching the quote from the agent, also request/parse:
- Geolocation sensor ID (mobile/gnss)
- Geolocation details (GNSS coordinates, accuracy, etc.)

**Location:** `code-rollout-phase-2/keylime/keylime/cloud_verifier_tornado.py` lines 1886-1990 (`_fetch_quote_from_agent`)

---

### 3. SPIRE Agent — Delegated Certificate Request Improvements -- gap fixed

#### 3.1. TPM App Key Context Should Not Be Sent Back to SPIRE Agent

**Current State:** `app_key_context_path` is sent from SPIRE Agent to TPM Plugin Server, then forwarded to rust-keylime agent

**Issue:** Context path is exposed beyond the TPM Plugin boundary

**Required:** Keep the context path internal to the TPM Plugin; SPIRE Agent should only send the App Key public key

**Location:**
- `code-rollout-phase-1/spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go` line 193
- `code-rollout-phase-3/tpm-plugin/tpm_plugin_server.py` line 109

#### 3.2. Add SPIRE Agent Nonce as Part of Certificate

**Current State:** Certificate qualifying data is only the hash of the App Key public key; SPIRE Server's challenge nonce is not included

**Issue:** Certificate lacks freshness proof; cannot verify it was generated for the specific attestation request

**Required:** Include the SPIRE Server's challenge nonce in the `qualifying_data` when performing TPM2_Certify

**Location:** `code-rollout-phase-2/rust-keylime/keylime-agent/src/delegated_certification_handler.rs` lines 131-142

---

### 4. SPIRE Agent TPM Plugin → Keylime Agent: Use UDS for Security

**Current State:** Communication is hardcoded to HTTP over localhost (`http://127.0.0.1:9002`)

**Issue:** HTTP over TCP is less secure than UDS; traffic could be intercepted or spoofed

**Required:**
- Implement UDS socket support in rust-keylime agent for the delegated certification endpoint
- Update TPM Plugin client to use UDS instead of HTTP
- Protocol can be HTTP/JSON or pure JSON over UDS
- Default UDS path: `/tmp/keylime-agent.sock` or similar

**Location:**
- `code-rollout-phase-3/tpm-plugin/delegated_certification.py` lines 68-100 (currently hardcoded to HTTP)
- `code-rollout-phase-2/rust-keylime/keylime-agent/src/main.rs` (needs UDS socket binding support)

---

### 5. Keylime Verifier → Keylime Agent: Use mTLS for Security

**Current State:** Communication is forced to HTTP for localhost agents (bypassing mTLS)

**Issue:** HTTP is unencrypted and unauthenticated; vulnerable to MITM attacks

**Required:**
- Enable mTLS between verifier and agent (remove localhost HTTP bypass)
- Verifier should use agent's mTLS certificate from registrar
- Agent should require mTLS for all verifier connections
- Both verifier and agent should authenticate each other using certificates

**Location:**
- `code-rollout-phase-2/keylime/keylime/cloud_verifier_tornado.py` lines 1867-1880 (currently forcing HTTP for localhost)
- `code-rollout-phase-2/rust-keylime/keylime-agent/src/main.rs` (needs mTLS enabled, not hardcoded to HTTP)

---

### Additional Considerations

- **Certificate Verification Error Handling**: If certificate verification fails, the verifier should reject the attestation
- **Nonce Validation in Certificate**: When verifying the certificate, validate that the nonce matches the one from SPIRE Server
- **Geolocation Data Format**: Define the format for sensor ID and GNSS data in the quote response
- **UDS Socket Permissions**: Ensure proper file permissions and ownership for UDS sockets
- **mTLS Certificate Management**: Ensure verifier and agent have proper certificate chains and trust anchors

### Mobile location verification microservice
- prestep: configure the mobile location verification microservice to use a simple sqlite database to convert the sensor id into a phone number **and** the default latitude/longitude/accuracy (seed with `12d1:1433 → tel:%2B34696810912, 40.33, -3.7707, 7`); keylime verifier connects to the mobile location verification microservice via a REST API (JSON) over UDS socket
- keylime verifier extracts the geolocation sensor id from the TPM quote response and passes it unchanged to the mobile location verification microservice (no hardcoded defaults)
- the mobile location verification microservice converts the sensor id into a phone number by looking a simple sqlite database
- the mobile location verification microservice connects to the camara APIs and returns the verification result true/false to the keylime verifier; if the verification result is false—or if the verifier cannot reach the microservice—the Keylime Verifier fails the attestation and the SPIRE Server will not issue the SVID to the SPIRE Agent

---

## Gap Priority

**Critical for Production Security:**
- Gap 4: UDS for SPIRE Agent TPM Plugin → Keylime Agent communication
- Gap 5: mTLS for Keylime Verifier → Keylime Agent communication

**Security Enhancements:**
- Gap 1: Certificate signature verification
- Gap 3.2: Nonce in certificate for freshness

**Functionality Enhancements:**
- Gap 2: Geolocation sensor metadata
- Gap 3.1: Context path security

These gaps address:
- **Security**: Certificate verification, UDS for local communication, mTLS for network communication, context exposure, nonce freshness
- **Functionality**: Geolocation sensor metadata

