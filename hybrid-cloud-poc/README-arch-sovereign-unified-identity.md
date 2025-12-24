# Sovereign Unified Identity Architecture - End-to-End Flow

## 🚀 Open Source Upstreaming-Ready Design

**Architecture Philosophy**: This implementation uses **plugin-based extension** rather than core modifications:

- **SPIRE**: All functionality via plugins (NodeAttestor, CredentialComposer, etc.)
- **Keylime**: New optional APIs added to verifier and agent (no core changes). **Note**: Geolocation APIs have standalone value for host location attestation independent of Unified Identity.
- **Clean Interfaces**: Plugin boundaries enable independent upstream contribution
- **Zero Core Dependencies**: Can be merged upstream without breaking existing deployments

**Feature Flag Gating**: `unified_identity_enabled`
- Single boolean flag controls entire Unified Identity feature set
- **Default: `false`** - System behaves exactly like upstream SPIRE/Keylime
- **When enabled**: Activates TPM App Key mTLS, geolocation attestation, delegated certification
- **Backward Compatible**: Existing deployments unaffected when flag is disabled

**Result**: Each component can be contributed to its respective open source project independently with zero breaking changes.

---

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
                                              └──────────────┘                              │  (PCR 15)    │                                                             │ Return       │
                                                                                             └──────────────┘                                                             │ BroaderClaims│
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
**[11]** Geolocation Detection: Agent detects mobile sensor, binds to PCR 15 with nonce  
**[12]** Geolocation Extraction: Verifier fetches geolocation via mTLS, validates nonce and PCR index*  
**[13]** Quote Response: Agent returns TPM quote and nonce-bound geolocation data  
**[14]** Verification Result: Verifier returns BroaderClaims (geolocation, TPM attestation) → SPIRE Server  
**[15]** Agent SVID: Server issues agent SVID with BroaderClaims embedded → SPIRE Agent  
**[16]** Workload Request: Workload connects to Agent Workload API  
**[17]** Workload API: Workload requests SVID via Agent Workload API  
**[18]** Forward Request: Agent forwards workload SVID request to Server  
**[19]** Spire Server Issues Workload SVID: Server issues workload SVID (inherits agent claims, no Keylime call) to spire agent
**[20]** Spire Agent Returns SVID: Agent returns workload SVID to workload  
**[21]** Workload Receives SVID: Workload receives workload SVID from SPIRE Agent  

### Key Components:

**SPIRE Ecosystem (Plugin-Based Extensions):**
- **SPIRE Server**: SVID issuance, policy enforcement
  - Plugin: `unified_identity` NodeAttestor (processes SovereignAttestation)
  - Plugin: `credential_composer` (composes SVIDs with AttestedClaims)
  - Clean plugin interfaces - no core modifications
- **SPIRE Agent**: Workload API, attestation orchestration
  - External plugin: TPM Plugin Server (out-of-process)
  - Plugin integration via standard gRPC/HTTP interfaces
- **TPM Plugin Server**: External process for App Key generation, TPM signing
  - Mediates all TPM operations for SPIRE Agent
  - Independent lifecycle from SPIRE Agent

**Keylime Ecosystem (Optional API Extensions):**
- **rust-keylime Agent**: High-privilege TPM operations (EK, AK, Quotes, Certify)
  - New API: `/v2.2/agent/certify_appkey` (delegated certification)
  - New API: `/v2.2/agent/attested_geolocation` (nonce-bound geolocation)
    - **Standalone Value**: Geolocation API provides TPM-bound host location **independent of Unified Identity**
    - Can be used by any verifier for location-aware attestation
    - Backward compatible - existing functionality unaffected
- **Keylime Verifier**: TPM attestation verification, geolocation verification
  - New API: `/v2.2/verify/sovereignattestation` (unified verification)
  - Optional feature - gated by `unified_identity_enabled` flag
  - **Geolocation verification works standalone**: Verifier can fetch and validate geolocation independently
- **Keylime Registrar**: Agent registration database (no changes)

**Integration Layer:**
- **Mobile Sensor Microservice**: Location verification via CAMARA APIs
  - Used by Envoy WASM filter for runtime authorization
  - Not called during attestation (direct agent → verifier)

**Upstreaming Strategy:**
- SPIRE plugins can be contributed as standalone packages
- Keylime APIs are optional extensions (feature-flagged)
- No breaking changes to either upstream project
- Each component independently mergeable

*The verifier fetches geolocation data via a secure mTLS connection from the agent, validating it against a fresh challenge nonce and PCR 15. No microservice call is made during attestation. When no TPM-reported Mobile/GNSS sensor is present, Sovereign SVIDs omit `grc.geolocation` in that case.*

---

## 🔐 Key Architecture Highlights

### TPM Hardware Binding for All Operations

**Critical Design Decision**: After initial attestation, ALL subsequent SPIRE Agent ↔ SPIRE Server communications use the **TPM App Key as the mTLS private key**.

#### Why External TPM Plugin Server Exists

The TPM Plugin Server is an **external gRPC/HTTP process** (out-of-process), NOT an inline plugin:

```
SPIRE Agent (Go) → mTLS to SPIRE Server
      ↓ (crypto.Signer interface)
TPMSigner.Sign() called for TLS handshake
      ↓ (gRPC/HTTP call)
TPM Plugin Server (Python) 
      ↓ (tpm2_sign)
TPM Hardware
```

**Every workload SVID request requires:**
1. SPIRE Agent initiates mTLS connection to SPIRE Server
2. TLS handshake needs signature
3. `TPMSigner.Sign()` invoked ([tpm_signer.go:122](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/spire/pkg/agent/tpmplugin/tpm_signer.go#L122))
4. **Real-time gRPC/HTTP call to TPM Plugin Server**
5. TPM Plugin calls `tpm2_sign` on physical TPM
6. Signature returned and used in TLS handshake

#### Security Implications

**Certificate Theft Becomes Useless:**
- An attacker who steals the SPIRE agent SVID certificate cannot use it
- Each TLS handshake has unique random data requiring a fresh TPM signature
- No signature caching or replay possible
- **Physical TPM access required for every connection**

**Two-Phase TLS Design:**

| Phase | TLS Private Key | Purpose |
|-------|----------------|---------|
| **Initial Attestation** | Ephemeral SPIRE key | Standard agent enrollment |
| **After Attestation** ([client.go:597](file:///home/mw/AegisSovereignAI/hybrid-cloud-poc/spire/pkg/agent/client/client.go#L597)) | **TPM App Key** | All workload SVID operations |

**Code Reference:**
```go
// Line 614 in client.go - The critical switch
agentCert.PrivateKey = tpmSigner  // Replace with TPM signer
c.c.Log.Info("Unified-Identity - Verification: Using TPM App Key for mTLS signing")
```

#### Why External Plugin is Necessary

1. **Delegated Certification**: TPM Plugin must call rust-keylime agent HTTP API (`/v2.2/agent/certify_appkey`) for App Key certificate
2. **Real-time TPM Access**: Every TLS handshake requires fresh `tpm2_sign` operation
3. **Language/Library**: Python `tpm2-pytss` provides robust TPM access
4. **Process Isolation**: TPM operations isolated from SPIRE Agent crashes

**Result**: Complete hardware-rooted trust chain where software compromise cannot bypass TPM protection.

---

## 🏴 Feature Flag: `unified_identity_enabled`

**Purpose**: Single boolean flag controls entire Unified Identity feature set, ensuring backward compatibility.

### System Behavior

| Component | Flag = `false` (Default) | Flag = `true` (Unified Identity) |
|-----------|-------------------------|----------------------------------|
| **SPIRE Agent** | Standard attestation, ephemeral keys | TPM App Key for mTLS after attestation |
| **SPIRE Server** | Standard SVID issuance | SVIDs include AttestedClaims extension |
| **Keylime Agent** | Standard TPM attestation<br>**+ Geolocation API available*** | + Delegated certification API<br>+ Geolocation API (same)*** |
| **Keylime Verifier** | Standard quote verification<br>**+ Geolocation fetch available*** | + Unified verification API<br>+ Geolocation fetch (same)*** |

**Note**: The geolocation APIs (`/v2.2/agent/attested_geolocation` and verifier geolocation fetch) provide standalone value for **host location attestation** regardless of Unified Identity integration. Any verifier can use these APIs to obtain TPM-bound geolocation claims.

### Configuration

**SPIRE (`server.conf` / `agent.conf`):**
```hcl
# Feature flag controls plugin loading
unified_identity_enabled = true  # Default: false
```

**Keylime (`verifier.conf` / `agent.conf`):**
```ini
[cloud_verifier]
unified_identity_enabled = true  # Default: false
```

### Backward Compatibility Guarantee

- **Default off**: Systems behave identically to upstream SPIRE/Keylime
- **No code paths executed**: Unified Identity code never runs when disabled
- **Safe deployment**: Can merge to upstream without affecting existing users
- **Gradual rollout**: Operators enable per-environment as needed

---

## End-to-End Flow: SPIRE Agent Sovereign SVID Attestation

### Setup: Initial Setup (Before Attestation)

1. **rust-keylime Agent Registration**
   - The rust-keylime agent starts and registers with the Keylime Registrar
   - The agent generates its TPM Endorsement Key (EK) and Attestation Key (AK)
   - The registrar stores the agent's UUID, IP address, port, TPM keys, and mTLS certificate
   - The agent is now registered and ready to serve attestation requests

2. **TPM Plugin Server (External Process) Startup**
   - The TPM Plugin Server is an **external gRPC/HTTP process** (out-of-process plugin)
   - It starts independently and generates an App Key in the TPM
   - The App Key is a workload-specific key used for identity attestation and mTLS signing
   - The App Key context (handle) is stored for later use
   - **Note**: This is an external Python process that SPIRE Agent connects to via Unix socket, NOT an inline plugin compiled into SPIRE Agent

### Attestation: SPIRE Agent Attestation Request

3. **SPIRE Agent Initiates Attestation**
   - The SPIRE Agent initiates attestation by opening a gRPC stream to the SPIRE Server over **standard TLS** (TLS 1.2/1.3)
   - The gRPC connection uses standard TLS for transport security (server authentication only)
   - The SPIRE Server sends a challenge nonce to the agent
   - The agent must prove its identity using TPM-based attestation (SovereignAttestation message)
   - **Note**: The initial gRPC connection uses standard TLS, not mTLS - the TPM App Key is used for attestation proof, not TLS client authentication

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

13. **Verifier Fetches Geolocation with Nonce**
    - The verifier connects to the rust-keylime agent (over HTTPS/mTLS)
    - It requests the current geolocation using the challenge nonce from SPIRE Server
    - The agent generates a geolocation response where the hash of (geolocation + nonce) is extended into **PCR 15**
    - The verifier validates that the returned nonce matches the request, providing a freshness guarantee (TOCTOU protection)
    - Geolocation data includes: sensor type (mobile/gnss), sensor_id, sensor_imei, sensor_imsi, and optional value (for GNSS)
    - **Note**: The verifier validates geolocation data as part of the hardware-backed attestation process. No additional microservice verification is performed during attestation.

14. **Verifier Retrieves Attested Claims**
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
    - If verification succeeded (including certificate signature verification and TPM quote verification), the server proceeds to issue the agent SVID
    - If certificate signature verification failed, the server rejects the attestation and does not issue an SVID
    - If TPM quote verification failed, the server rejects the attestation and does not issue an SVID

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
- **Nonce-Based Geolocation Freshness**: Geolocation is cryptographically bound to a challenge nonce and extended into PCR 15, preventing Time-of-Check-Time-Of-Use (TOCTOU) attacks.
- **Mobile Location Verification**: The verifier fetches geolocation data (sensor_type, sensor_id, sensor_imei, sensor_imsi) directly from the agent via mTLS. The data is validated using the nonce and PCR index and included in attested claims.
  - **Note**: Runtime verification at the enterprise gateway (Envoy WASM Filter) still uses the mobile location verification microservice for CAMARA API verification when processing incoming requests.
- **TPM Plugin Server Communication**: SPIRE Agent communicates with TPM Plugin Server via JSON over UDS (Unix Domain Socket) for security and performance
- **Delegated Certification Transport**: TPM Plugin Server uses HTTPS/mTLS (port 9002) to communicate with rust-keylime agent (UDS support deferred)
- **SPIRE Agent Attestation Transport**: SPIRE Agent uses standard TLS (not mTLS) for gRPC communication with SPIRE Server
- **TPM App Key Usage**: TPM App Key is used for attestation proof (in SovereignAttestation message), not for TLS client certificate authentication
- **SPIRE Agent Attestation Transport**: SPIRE Agent uses standard TLS (not mTLS) for gRPC communication with SPIRE Server
- **Token Caching** (Runtime Verification): Mobile location verification microservice (used by Envoy WASM Filter) caches CAMARA auth_req_id (persisted to file) and access_token (with expiration) to reduce API calls and improve performance
- **Location Verification Caching** (Runtime Verification): The `verify_location` API result is cached with configurable TTL (default: 15 minutes). The actual CAMARA API is called at most once per TTL period; subsequent calls within the TTL return the cached result. This significantly reduces CAMARA API calls and improves performance. Note: This caching is for runtime verification at the enterprise gateway, not during attestation.
- **GPS/GNSS Sensor Bypass** (Runtime Verification): GPS/GNSS sensors (trusted hardware) bypass mobile location service entirely at the enterprise gateway, allowing requests directly without CAMARA API calls

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
   - **Important**: After attestation, SPIRE Agent uses **non-standard mTLS** with TPM App Key for workload SVID requests
   - **mTLS Flow**:
     1. SPIRE Agent initiates gRPC connection to SPIRE Server
     2. During TLS handshake, SPIRE Agent needs to sign TLS CertificateVerify message
     3. SPIRE Agent calls TPM Plugin Server `/sign-data` endpoint via UDS:
        - Request: `{"data": "<base64_hash_of_tls_handshake>", "hash_alg": "sha256", "is_digest": true, "scheme": "rsapss"}`
        - TPM Plugin Server uses `tpm2_sign` to sign the hash with TPM App Key (private key stays in TPM)
        - Response: `{"status": "success", "signature": "<base64_signature>"}`
     4. SPIRE Agent uses the signature in TLS CertificateVerify message
     5. SPIRE Server verifies the signature using App Key public key (from agent SVID)
   - The request includes:
     - The workload's SPIFFE ID (from the matched registration entry)
     - The agent's own SVID (for authentication, contains App Key public key)
     - Workload selector information
   - **Transport**: gRPC over mTLS (non-standard, using TPM App Key for client authentication)

### Verification: SPIRE Server Issues Workload SVID

5. **SPIRE Server Validates Request**
   - The SPIRE Server authenticates the agent using **non-standard mTLS** with TPM App Key
   - The server verifies the TLS client signature (signed by TPM App Key private key)
   - The server verifies the agent SVID's certificate chain and signature
   - The server validates that the agent is authorized to request SVIDs for the specified workload
   - **Note**: Workload SVID requests skip Keylime verification - workloads inherit attested claims from the agent SVID
   - **mTLS Authentication**: The TPM App Key signature proves the agent controls the TPM App Key (hardware-backed authentication)

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

## End-to-End Flow: Enterprise On-Prem Runtime Access (Envoy WASM Filter)

After workloads receive their SPIRE SVIDs, they can use these certificates to access enterprise on-prem services. The Envoy proxy with WASM filter verifies the sensor identity at runtime.

### Setup: Enterprise On-Prem Gateway

1. **Envoy Proxy Setup**
   - Envoy proxy runs on enterprise on-prem gateway (e.g., 10.1.0.10:8080)
   - Configured to terminate mTLS from SPIRE clients
   - Verifies SPIRE certificate signatures using SPIRE CA bundle
   - Uses WASM filter to extract sensor information from certificate chain

2. **Mobile Location Service Setup**
   - Mobile location service runs on enterprise on-prem gateway (localhost:9050)
   - Handles CAMARA API calls with caching (15-minute TTL, configurable)
   - No caching in WASM filter - all caching centralized in mobile location service

### Runtime: Workload Access Request

3. **Workload Initiates Request**
   - Workload (on 10.1.0.11) makes HTTPS request to enterprise gateway (10.1.0.10:8080)
   - Uses SPIRE workload SVID certificate chain for mTLS client authentication
   - Certificate chain includes: [Workload SVID, Agent SVID] (Agent SVID contains Unified Identity extension)

4. **Envoy Terminates mTLS**
   - Envoy terminates the mTLS connection
   - Verifies SPIRE certificate chain using SPIRE CA bundle
   - Extracts certificate chain for WASM filter processing

5. **WASM Filter Extracts Sensor Information**
   - WASM filter parses the certificate chain
   - Extracts Unified Identity extension (OID `1.3.6.1.4.1.99999.2`) from Agent SVID (intermediate certificate)
   - Parses JSON to extract: `sensor_id`, `sensor_type`, `sensor_imei`, `sensor_imsi`
   - **No Caching**: WASM filter does NOT implement any caching. All caching is handled by the mobile location service.

6. **WASM Filter Sensor Type Handling**
   - **GPS/GNSS sensors** (`sensor_type == "gnss"`):
     - Trusted hardware, bypass mobile location service entirely
     - Logs bypass message and allows request directly
     - Adds `X-Sensor-ID` header and forwards to backend
   - **Mobile sensors** (`sensor_type == "mobile"`):
     - Calls mobile location service at `localhost:9050/verify` (blocking call)
     - Request: `POST /verify` with `{"sensor_id": "...", "sensor_imei": "...", "sensor_imsi": "..."}`
     - Mobile location service:
       - Looks up sensor in database
       - Checks `verify_location` cache (TTL: 15 minutes, configurable)
       - If cache hit: Returns cached result (no CAMARA API call)
       - If cache miss/expired: Calls CAMARA APIs and caches result
     - If verification succeeds: Adds `X-Sensor-ID` header and forwards to backend
     - If verification fails: Returns 403 Forbidden

7. **Request Forwarding**
   - If verification succeeds (or GPS sensor bypassed), Envoy forwards request to backend mTLS server (10.1.0.10:9443)
   - Request includes `X-Sensor-ID` header for audit trail
   - Backend server logs sensor ID for compliance

### Key Design Points

- **No Caching in WASM Filter**: The WASM filter does NOT implement any caching. All caching (CAMARA API result caching with 15-minute TTL) is handled by the mobile location service. This simplifies the filter logic and ensures a single source of truth for caching behavior.
- **GPS Sensor Bypass**: GPS/GNSS sensors (trusted hardware) bypass mobile location service entirely, allowing requests directly without verification
- **Mobile Sensor Verification**: Mobile sensors require CAMARA API verification via mobile location service (with caching)
- **Blocking Verification**: For mobile sensors, requests pause until mobile location service responds
- **Certificate Chain**: WASM filter extracts sensor information from Agent SVID (intermediate certificate) in the certificate chain
- **Centralized Caching**: All caching logic centralized in mobile location service, making it easier to maintain and debug

### Flow Diagram

```
Workload (10.1.0.11)
    │
    │ mTLS (SPIRE cert chain: [Workload SVID, Agent SVID])
    v
Envoy Proxy (10.1.0.10:8080)
    │
    ├─> 1. Terminate mTLS
    ├─> 2. Verify SPIRE cert chain (using SPIRE CA bundle)
    ├─> 3. WASM filter extracts sensor info from Agent SVID (Unified Identity extension)
    │
    ├─> 4. Check sensor_type:
    │   ├─> If "gnss": Bypass mobile location service, allow directly
    │   └─> If "mobile":
    │       │
    │       └─> POST /verify → Mobile Location Service (localhost:9050)
    │           │
    │           ├─> Check verify_location cache (TTL: 15 min)
    │           │   ├─> Cache hit: Return cached result
    │           │   └─> Cache miss: Call CAMARA APIs, cache result
    │           │
    │           └─> Return verification result
    │
    ├─> 5. If verified/bypassed: Add X-Sensor-ID header, forward to backend
    └─>    If not verified: Return 403 Forbidden
    │
    v
Backend mTLS Server (10.1.0.10:9443)
    │
    └─> Receives request with X-Sensor-ID header
        └─> Logs sensor ID for audit trail
```

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
    └─> Initiate gRPC stream: AttestAgent() over TLS (standard TLS, not mTLS)
        │   Transport: gRPC over TLS 1.2/1.3 (server authentication only)
        │   Protocol: AttestAgent() gRPC method
        │
        └─> SPIRE Server (Port 8081)
            │
            ├─> Receives attestation request over TLS
            └─> Send challenge nonce
                │
                <─ SPIRE Agent
                    │
                    └─> Receives challenge nonce
                        │
                        └─> Note: Connection uses standard TLS (not mTLS with TPM App Key)
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
    ├─> Build SovereignAttestation message:
    │   ├─> app_key_public: App Key public key (PEM format)
    │   ├─> app_key_certificate: App Key certificate (AK-signed, base64-encoded bytes)
    │   ├─> challenge_nonce: Challenge nonce from SPIRE Server
    │   ├─> keylime_agent_uuid: Agent UUID
    │   └─> tpm_signed_attestation: empty string (verifier fetches quote directly)
    │
    └─> Send SovereignAttestation via gRPC: AttestAgent() over TLS
        │   Transport: Standard TLS (not mTLS)
        │   Protocol: gRPC AttestAgent() method
        │   Note: TPM App Key is used for attestation proof, NOT for TLS client cert
        │
        └─> SPIRE Server (Port 8081)
            │
            └─> Receives SovereignAttestation over TLS
                │
                └─> Extracts: App Key public key, certificate, nonce, agent UUID
```
### VERIFICATION: SPIRE SERVER VERIFICATION

**Step 7: SPIRE Server Receives Attestation and sends to Keylime Verifier**
```
SPIRE Server (Port 8081)
    │
    ├─> Extract: App Key public key, certificate, nonce, agent UUID
    │
    └─> POST /v2.4/verify/evidence
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

**Step 11: Verifier Fetches Geolocation with Nonce On-Demand**
```
Keylime Verifier (Port 8881)
    │
    └─> GET /v2.2/agent/attested_geolocation?nonce={nonce} (HTTPS/mTLS)
        │
        └─> rust-keylime Agent (High Privilege, Port 9002)
            │
            ├─> Extend PCR 15: SHA256(geolocation_json + nonce)
            └─> Return: { sensor_type, sensor_id, sensor_imei, sensor_imsi, tpm_pcr_index: 15, nonce: "{nonce}" }
                │
                <─ Keylime Verifier
                    │
                    └─> Validate nonce and map to SPIRE claims
```

**Note**: The Keylime Verifier no longer calls the mobile location verification microservice during attestation. The geolocation data from the TPM quote is used directly. Runtime verification at the enterprise gateway (Envoy WASM filter) still uses the mobile location microservice for CAMARA API verification.

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
    │   └─> Geolocation extracted from TPM quote
    │
    └─> POST /v2.4/verify/evidence (response)
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
    ├─> Verify TPM quote valid
    └─> Extract attested claims (including geolocation from TPM quote)
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

6. **Nonce-Based Freshness (TOCTOU Prevention)**
   - Geolocation sensor identifiers (sensor_type, sensor_id, sensor_imei, sensor_imsi) are bound to a fresh challenge nonce.
   - The hash of (geolocation + nonce) is extended into **PCR 15** on the TPM.
   - The verifier fetches this data via mTLS and validates the nonce, ensuring the location is current at the time of SVID issuance.
   - No microservice call is made during attestation - geolocation data is validated cryptographically.
   - **Note**: Runtime verification at the enterprise gateway (Envoy WASM Filter) still uses the mobile location verification microservice for CAMARA API verification:
     - Microservice looks up sensor in database (priority: sensor_id > sensor_imei > sensor_imsi)
     - Microservice verifies device location via CAMARA APIs:
       - Token caching: auth_req_id (persisted) and access_token (with expiration) are cached
       - Location verification caching: `verify_location` results are cached with configurable TTL (default: 15 minutes). The actual CAMARA API is called at most once per TTL period; subsequent calls within the TTL return the cached result.
     - Attestation fails if location verification fails
   - Enables geofencing and location-based policy enforcement

---

## SPIRE Agent Attestation: TLS vs mTLS Communication

### Standard TLS for Attestation Transport

**SPIRE Agent → SPIRE Server Communication:**
- **Transport Protocol**: Standard TLS (TLS 1.2/1.3) over gRPC
- **Connection Type**: Server-authenticated TLS (not mTLS)
- **Port**: 8081 (default SPIRE Server port)
- **Protocol**: gRPC `AttestAgent()` method
- **Authentication**: SPIRE Server presents its TLS certificate; SPIRE Agent verifies server identity
- **Client Authentication**: None (standard TLS, not mTLS)

### TPM App Key Usage: Two-Phase Approach

**Phase 1: Initial Attestation (Standard TLS)**
- The TPM App Key is **NOT** used for TLS client certificate authentication during initial attestation
- The TPM App Key is used for **attestation proof** within the `SovereignAttestation` message
- The App Key private key remains in the TPM and is never exported
- The App Key public key and AK-signed certificate are sent in the `SovereignAttestation` message
- **Transport**: Standard TLS (server authentication only)

**TPM App Key in Initial Attestation:**
1. **App Key Public Key**: Sent in `SovereignAttestation.app_key_public` field (PEM format)
2. **App Key Certificate**: Sent in `SovereignAttestation.app_key_certificate` field (base64-encoded bytes)
   - This certificate is signed by the TPM's Attestation Key (AK) via TPM2_Certify
   - Proves the App Key exists in the TPM and is bound to the challenge nonce
3. **Attestation Proof**: The App Key certificate serves as cryptographic proof of TPM-based identity

**Phase 2: Post-Attestation mTLS (Non-Standard mTLS with TPM App Key)**
- **After successful attestation**, SPIRE Agent uses **non-standard mTLS** with TPM App Key for workload SVID requests
- The TPM App Key private key (stays in TPM) is used to sign TLS handshake messages
- SPIRE Agent calls TPM Plugin Server `/sign-data` endpoint to sign TLS CertificateVerify message or client certificate
- This provides hardware-backed client authentication for subsequent gRPC calls to SPIRE Server
- **Transport**: Non-standard mTLS (TPM App Key for client authentication)

**How Non-Standard mTLS Works:**
1. SPIRE Agent requests TPM Plugin Server to sign TLS handshake data using TPM App Key
2. TPM Plugin Server uses `tpm2_sign` to sign the data (hash of TLS handshake messages) with TPM App Key
3. SPIRE Agent uses the signature in TLS CertificateVerify message or client certificate
4. SPIRE Server verifies the signature using the App Key public key (from agent SVID or attestation)
5. This proves the agent controls the TPM App Key (hardware-backed authentication)

**Why Non-Standard mTLS?**
- TPM App Key private key cannot be exported (stays in TPM)
- Standard TLS libraries expect private keys to be accessible for TLS handshake
- Non-standard approach: SPIRE Agent uses TPM Plugin Server to sign TLS handshake messages on-demand
- This provides hardware-backed client authentication without exporting the private key

**Security Model:**
- **Initial Attestation**: Standard TLS (server authentication) + TPM App Key attestation proof
- **Post-Attestation**: Non-standard mTLS (TPM App Key for client authentication)
- **Identity Proof**: TPM App Key certificate (hardware-backed attestation)
- **Verification**: Keylime Verifier validates the App Key certificate signature and TPM quote
- **Result**: Hardware-rooted identity proof with hardware-backed mTLS client authentication

**Comparison: Standard mTLS vs Non-Standard TPM App Key mTLS**

| Aspect | Standard mTLS | TPM App Key (Initial Attestation) | TPM App Key (Post-Attestation) |
|--------|---------------|-----------------------------------|--------------------------------|
| **Phase** | N/A | Initial attestation | Workload SVID requests |
| **Transport** | TLS with client certificate | Standard TLS (no client cert) | Non-standard mTLS (TPM App Key) |
| **Client Auth** | TLS client certificate | Attestation message (SovereignAttestation) | TLS CertificateVerify (TPM-signed) |
| **Private Key** | Exported from TPM (if TPM-backed) | Stays in TPM (never exported) | Stays in TPM (sign via TPM Plugin Server) |
| **Proof Mechanism** | TLS handshake with client cert | App Key certificate in gRPC message | TPM App Key signature in TLS handshake |
| **Verification** | TLS certificate chain validation | Keylime Verifier validates TPM evidence | SPIRE Server verifies TPM App Key signature |
| **Hardware Binding** | Optional (if using TPM-backed cert) | Required (App Key in TPM) | Required (App Key in TPM) |

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
- **Location Verification Caching**: The `verify_location` API result is cached with configurable TTL (default: 15 minutes). The actual CAMARA API is called at most once per TTL period; subsequent calls within the TTL return the cached result. This significantly reduces CAMARA API calls and improves performance.
- **Attestation Flow**: The Keylime Verifier extracts geolocation data from the TPM quote and includes it in attested claims. No microservice call is made during attestation. The geolocation data is validated as part of the TPM quote verification process.
- **Runtime Verification**: The mobile location verification microservice is still used by the Enterprise On-Prem Envoy WASM Filter for runtime verification at the gateway (see "Enterprise On-Prem Envoy WASM Filter" section below).
- **Configuration** (for Envoy WASM Filter runtime verification): 
  - `CAMARA_BYPASS` environment variable (default: false, set to true to skip CAMARA APIs for testing)
  - `CAMARA_BASIC_AUTH` environment variable (required for CAMARA API authentication)
  - `CAMARA_AUTH_REQ_ID` environment variable (optional, pre-obtained auth_req_id)
  - `CAMARA_VERIFY_CACHE_TTL_SECONDS` environment variable (default: 900 seconds = 15 minutes). Controls how long `verify_location` results are cached. Set to 0 to disable caching.
  - `MOBILE_SENSOR_DB` environment variable (default: `sensor_mapping.db`)
  - `MOBILE_SENSOR_LATITUDE`, `MOBILE_SENSOR_LONGITUDE`, `MOBILE_SENSOR_ACCURACY` environment variables for coordinate overrides
  - `MOBILE_SENSOR_IMEI`, `MOBILE_SENSOR_IMSI` environment variables for sensor identifiers

**Location:**
- `mobile-sensor-microservice/service.py` - Flask microservice implementation (used by Envoy WASM Filter)
- `keylime/keylime/cloud_verifier_tornado.py` - Verifier extracts geolocation from TPM quote (no microservice call)
- `keylime/verifier.conf.minimal` - Configuration (`[verifier]` section)
- `tpm-plugin/tpm_plugin_server.py` - SPIRE Agent TPM Plugin Server (sidecar) implementation
- `tpm-plugin/delegated_certification.py` - Delegated certification client implementation

---

## Enterprise On-Prem Envoy WASM Filter

**Status:** ✅ Implemented and integrated

**Implementation Details:**
- **Purpose**: Envoy proxy filter that verifies sensor identity from SPIRE certificates at the enterprise on-prem gateway
- **Location**: `enterprise-private-cloud/wasm-plugin/src/lib.rs`
- **Certificate Extraction**: Extracts sensor_id, sensor_type, sensor_imei, and sensor_imsi from SPIRE certificate Unified Identity extension (OID `1.3.6.1.4.1.99999.2`)
- **Sensor Type Handling**:
  - **GPS/GNSS sensors**: Trusted hardware, bypass mobile location service entirely (allow request directly without verification)
  - **Mobile sensors**: Calls mobile location service at `localhost:9050/verify` for CAMARA API verification
- **No Caching in WASM Filter**: The WASM filter does NOT implement any caching. All caching (CAMARA API result caching with 15-minute TTL) is handled by the mobile location service. This simplifies the filter logic and ensures a single source of truth for caching behavior.
- **Blocking Verification**: For mobile sensors, requests pause until mobile location service responds
- **Header Injection**: If verification succeeds, adds `X-Sensor-ID` header and forwards to backend mTLS server
- **Error Handling**: Returns 403 Forbidden if verification fails or sensor information is missing

**Architecture Benefits:**
- **Simplified Filter Logic**: No cache state management, expiration logic, or synchronization in the WASM filter
- **Single Source of Truth**: All caching logic centralized in the mobile location service
- **Performance**: GPS sensors bypass verification entirely (trusted hardware)
- **Maintainability**: Easier to debug and maintain without distributed caching logic

**Location:**
- `enterprise-private-cloud/wasm-plugin/src/lib.rs` - WASM filter implementation
- `enterprise-private-cloud/envoy/envoy.yaml` - Envoy configuration

---

## Production Readiness & Implementation Status

### Current Implementation State

**Status**: ✅ Functional PoC on Real Hardware (TPM 2.0)

The "Unified Identity" feature is **fully functional** and has been verified on real TPM hardware (10.1.0.11). The system successfully:
- Generates TPM App Keys for SPIRE workloads
- Performs delegated certification (AK signs App Key)
- Verifies TPM quotes with geolocation data
- Issues Sovereign SVIDs with attested claims
- Enforces runtime geolocation verification at enterprise gateways

### Recent Enhancements

#### Task 1: Delegated Certification Security (✅ Complete)

**Implemented**: December 2025

The delegated certification endpoint (`/certify_app_key`) now includes production-grade security controls:

**Features:**
- **IP Allowlist**: Configurable list of allowed IPs (default: localhost only)
- **Rate Limiting**: Per-IP request limiting (default: 10 requests/minute, 60s sliding windows)
- **Secure Defaults**: Disabled by default, requires explicit configuration

**Configuration** (`rust-keylime/keylime-agent.conf`):
```toml
[delegated_certification]
enabled = false # Gated by unified_identity_enabled
allowed_ips = ["127.0.0.1"] # Localhost only
rate_limit_per_minute = 10 # Conservative limit
```

**Implementation Files:**
- `rust-keylime/keylime/src/config/base.rs` - Configuration parsing
- `rust-keylime/keylime-agent/src/delegated_certification_handler.rs` - Security enforcement
- `rust-keylime/keylime-agent/src/main.rs` - QuoteData integration

**Verification**: Tested on real TPM hardware with full integration test suite (`ci_test_runner.py`).

### Upstreaming Roadmap

**Comprehensive Status**: See [`PILLAR2_STATUS.md`](PILLAR2_STATUS.md)

The Pillar 2 document provides detailed analysis of all 6 upstreaming tasks required for submission to Keylime and SPIRE upstream projects:

| Task | Component | Status | Est. Effort |
|------|-----------|--------|-------------|
| **Task 1** | Keylime Agent - Delegated Certifier | ✅ Production-ready | 3 days |
| **Task 2** | Keylime Agent - Geolocation API | ⚠️ Needs refactoring | 5 days |
| **Task 3** | Keylime Verifier - Cleanup | ⚠️ Has dead code | 2 days |
| **Task 4** | SPIRE Server - Validator Plugin | ❌ Major refactoring | 9 days |
| **Task 5** | SPIRE Agent - Collector Plugin | ❌ Major refactoring | 12 days |
| **Task 6** | SPIRE - CredentialComposer | ✅ Config change | 2 days |

**Total Upstream Effort**: ~6 weeks

**Phased Approach**:
1. **Quick Wins** (5 days): Tasks 1, 3, 6 - immediate upstream value
2. **Moderate Refactoring** (10 days): Task 2 - separate geolocation endpoint
3. **Major Refactoring** (20 days): Tasks 4 & 5 - SPIRE plugin extraction

### Test Infrastructure

**CI/CD Ready**: ✅ Complete

- **Test Runner**: `ci_test_runner.py` - Automated integration testing
  - Real-time output streaming
  - Structured logging with timestamps
  - Error detection and reporting
  - Automatic `--no-pause` for CI environments
- **Test Scripts**: Hardened with fail-fast (`set -euo pipefail`)
- **Cleanup**: Comprehensive state reset between test runs
- **Hardware**: Verified on TPM 2.0 (10.1.0.11)

**Test Coverage:**
- TPM operations (EK, AK, App Key generation)
- Delegated certification flow
- SPIRE Agent attestation
- Geolocation data extraction
- SVID issuance and renewal
- Enterprise gateway verification

### Security Considerations

**Current Security Features**:
- ✅ Feature flag gating (`unified_identity_enabled`)
- ✅ Hardware-rooted trust (TPM 2.0)
- ✅ IP allowlist and rate limiting (Task 1)
- ✅ mTLS between components
- ✅ Geolocation attestation with TPM binding
- ✅ **Full TLS certificate validation** (Task 7 Complete - No `InsecureSkipVerify`)

**Production Gaps** (See [`PILLAR2_STATUS.md`](PILLAR2_STATUS.md) for details):
- ⚠️ CAMARA API keys in environment variables (needs secret management)
- ⚠️ Some code paths modify core SPIRE/Keylime files (needs plugin extraction)

**TLS Certificate Validation (Task 7 - COMPLETE)**:
1. ✅ rust-keylime agent uses CA-signed certificates
2. ✅ Certificate generation includes comprehensive SANs:
   - Always: CN name + DNS:localhost + IP:127.0.0.1
   - Multi-machine: IPs from CONTROL_PLANE_HOST and AGENTS_HOST
3. ✅ Keylime Verifier enforces certificate validation
4. ✅ Supports single-machine tests and multi-machine deployments

**Recommended for Production**:
1. Complete Task 1 enhancements (✅ Done)
2. Implement proper secret management for CAMARA keys
3. Extract SPIRE modifications to standalone plugins (Tasks 4 & 5)

### Next Steps

**For Upstream Contribution:**

1. **SPIRE Plugins (Independent Contribution)**
   - Submit `unified_identity` NodeAttestor plugin
   - Submit `credential_composer` plugin
   - Submit TPM Plugin Server as external plugin reference implementation
   - All gated by `unified_identity_enabled` feature flag
   - Zero impact on existing SPIRE deployments

2. **Keylime API Extensions (Independent Contribution)**
   - Submit delegated certification API (`/v2.2/agent/certify_appkey`)
   - Submit attested geolocation API (`/v2.2/agent/attested_geolocation`)
   - Submit unified verification API (`/v2.2/verify/sovereignattestation`)
   - All optional - gated by `unified_identity_enabled` config flag
   - Backward compatible with existing Keylime deployments

3. **Feature Flag Implementation**
   - **SPIRE**: Feature flag in agent/server config enables plugin loading
   - **Keylime**: Config flag (`unified_identity_enabled = false` by default)
   - **Guarantee**: When disabled, systems behave identically to upstream
   - **Safe Rollout**: Operators can enable per-environment

4. **Documentation & Examples**
   - Integration guide for enabling Unified Identity
   - Performance benchmarks (TPM signing overhead)
   - Security considerations for production
   - Example deployments (single-machine, multi-machine, Kubernetes)

**Upstreaming Benefits:**
- ✅ No breaking changes to either project
- ✅ Clean plugin boundaries
- ✅ Feature-flagged for safe adoption
- ✅ Each component independently testable
- ✅ Backward compatible with all existing deployments

**For Production Deployment:**
1. ✅ Test infrastructure ready
2. ✅ Delegated certification hardened
3. 🔄 Address security gaps (Secret management for CAMARA keys)
4. 🔄 Monitor performance at scale

**For Continued Development:**
- Implement additional sensor types (GNSS, industrial IoT)
- Add policy enforcement for geolocation claims
- Enhance mobile sensor verification with additional CAMARA APIs

---

