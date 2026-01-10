# Proposal: Hardware-Verified "Premium Tier" for CAMARA Location APIs

**Status:** Strategic Proposal (Submitted to Deutsche Telekom T-Challenge)
**Target Group:** CAMARA Project (Device Location VR) / GSMA Open Gateway
**Project Lead:** Ramki Krishnan (Vishanti Systems)

## 1\. Executive Summary

This proposal outlines an architectural extension to the **CAMARA Device Location Verification API**.

We propose introducing a **"Premium Tier"** for location services that moves beyond standard Network Assurance (Cell Tower Triangulation) to **Hardware Assurance** (TPM + GNSS Attestation). This extension enables Telcos to offer unforgeable "Proof of Residency" to regulated industries (Banking, Defense, Healthcare) that require audit-proof compliance with data sovereignty laws (e.g., GDPR, EUDR).

## 2\. The Problem: The "Trust Gap" in Location APIs

Current CAMARA location APIs rely on network-side triangulation or user-provided GPS coordinates. While effective for consumer apps, these methods have critical gaps for high-security use cases:

  * **SIM Swapping Risks:** Location is often tied to the SIM (IMSI), not the device hardware. If a SIM is moved to an unauthorized device, the API still validates the location.
  * **GPS Spoofing:** Standard "User Plane" GPS data can be easily mocked by malicious apps or VPNs.
  * **Lack of Audit Trail:** Regulators often require cryptographic proof of *exactly which hardware* processed the data, not just a "Yes/No" from the network.

## 3\. The Solution: Hardware-Rooted Verification

We propose extending the `verify_location` API schema to include an optional **Hardware Integrity Proof**.

**AegisSovereignAI** acts as the "Trust Middleware" that generates and validates this proof, cryptographically binding the **Physical Location** (GNSS) to the **Device Identity** (TPM).

### Proposed Workflow:

1.  **Client App with Device:** Generates a "Unified SVID" containing a TPM Quote which binds:
      * Mobile Sensor Manufacturer ID / IMEI / IMSI
      * GPS-Sensor Manufacturer ID / Device Serial Number
      * Precise Location Data (GPS-based)
2.  **Server-side API Gateway:** Calls the CAMARA API, embedding this SVID in the request header (e.g., `X-Device-Attestation`).
3.  **CAMARA API Gateway:** Forwards the token to the **AegisSovereignAI Verifier**.
4.  **Verification:**
      * *Check 1:* Is the TPM signature valid? (Anti-Cloning)
      * *Check 2:* Is the Mobile Sensor Manufacturer ID/IMEI/IMSI valid? (Anti-Spoofing / Anti-SIM-Swap)
      * *Check 3:* Is the GPS data signed by the trusted sensor? (Anti-Spoofing)
      * *Check 4:* Is the device physically within the cell tower's range? (Cross-Verification)
5.  **Response:** Returns `true` only if **ALL** the checks pass.

## 4\. Business Value for Telcos

This extension transforms the Location API from a commodity utility into a high-margin security product.

| Feature | Standard API (Current) | Premium API (Proposed) |
| :--- | :--- | :--- |
| **Verification Source** | Network Signal | Network + Silicon (TPM) |
| **Target Customer** | Ride-sharing, Logistics | Banks, Gov/Defense, Hospitals |
| **Value Prop** | "Approximate Location" | **"Legal Proof of Residency"** |
| **Use Case** | Routing, Fraud Check | **Sovereign Cloud, EUDR Compliance** |

## 5\. Alignment with Open Standards

This proposal leverages existing standards to ensure interoperability:

  * **IETF RATS:** For the structure of the Attestation Token.
  * **CNCF SPIFFE:** For the device identity format.
  * **CAMARA:** As the standard interface for consumption.

## 6\. Proof of Concept

A reference implementation of this architecture is currently available in the **[AegisSovereignAI Sovereign Hybrid Cloud PoC](https://github.com/lfedgeai/AegisSovereignAI/tree/main/hybrid-cloud-poc)**.

  * It demonstrates a **Mobile Location Service** that acts as a mock CAMARA gateway.
  * It enforces access control based on real-time TPM attestation of a USB-tethered mobile sensor.

## 7\. Signed MNO Endorsement (Gen 4 Requirement)

> [!IMPORTANT]
> For **true zero-trust** in Gen 4 (ZK-Proof), the MNO must provide a **cryptographically signed** verification response, not just a pass/fail boolean.

### 7.1 Why Signing is Required

Without a signed response, the verification result must be trusted:
- An attacker who compromises the Verifier ↔ CAMARA channel could inject fake location data
- The ZK-Proof proves *computation correctness*, but not *input authenticity*

| Current API | Proposed Extension |
|-------------|-------------------|
| `{ "verified": true }` | `{ "verified": true, "endorsement": { ... }, "signature": "..." }` |
| Trust API response | Verify MNO signature |

### 7.2 Signed Endorsement Format

The response should include a signed `endorsement` object:

```json
{
  "verified": true,
  "endorsement": {
    "tower_id": "49201-12345",
    "device_id_hash": "H(IMEI || IMSI)",
    "imei_imsi_binding_valid": true,
    "coarse_location": {
      "latitude": 52.52,
      "longitude": 13.405,
      "accuracy_meters": 500
    },
    "timestamp": "2026-01-10T09:00:00Z",
    "nonce": "<challenge_nonce_from_verifier>"
  },
  "signature": "<EdDSA signature over endorsement>",
  "key_id": "mno-signing-key-2026-01"
}
```

**Fields:**
| Field | Purpose |
|-------|---------|
| `tower_id` | Cell tower identifier for cross-verification |
| `device_id_hash` | H(IMEI \|\| IMSI) — binds endorsement to specific device |
| `imei_imsi_binding_valid` | **Carrier verification** — IMEI-IMSI pair matches HLR/HSS registration |
| `coarse_location` | MNO-derived location (network triangulation) |
| `timestamp` | Prevents replay attacks |
| `nonce` | Challenge-response freshness (from Keylime Verifier) |
| `signature` | EdDSA signature over endorsement blob |
| `key_id` | Reference to MNO public key for verification |

### 7.2.1 IMEI-IMSI Binding Verification (Anti-SIM-Swap)

The carrier is uniquely positioned to verify **IMEI-IMSI binding**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   CARRIER IMEI-IMSI BINDING VERIFICATION                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Device Registration (SIM Activation):                                  │
│    → Carrier records IMEI-IMSI association in HLR/HSS                   │
│                                                                         │
│  Runtime Verification (CAMARA API Call):                                │
│    → Carrier checks: Does requesting IMEI match registered IMSI?        │
│    → If YES: imei_imsi_binding_valid = true                             │
│    → If NO:  imei_imsi_binding_valid = false (SIM swap detected!)       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Security Benefit:**
| Attack | Without Binding Check | With Binding Check |
|--------|----------------------|-------------------|
| **Physical SIM Swap** | Attacker moves SIM to new device → passes | ❌ Detected: IMEI changed |
| **eSIM Profile Transfer** | Attacker transfers eSIM to new device → passes | ❌ Detected: IMEI changed |
| **eSIM Remote Provisioning** | Attacker provisions profile to their device → passes | ❌ Detected: IMEI changed |
| **Device Clone** | Attacker clones IMEI → may pass | ❌ Detected: IMSI mismatch |

> [!NOTE]
> **eSIM makes IMEI-IMSI binding verification MORE important:** Profile transfer can be done remotely without physical SIM access. The carrier detection mechanism works identically — the IMEI changes when the profile moves to a new device.

> [!TIP]
> **MNO is involved in eSIM transfers — this strengthens security:**
>
> | Transfer Method | MNO Involvement |
> |-----------------|-----------------|
> | Apple/Samsung Quick Transfer | ✅ Goes through carrier's SM-DP+ server |
> | QR Code Provisioning | ✅ Carrier generates activation QR |
> | Carrier App Transfer | ✅ Carrier authorizes via their app |
>
> **Defense-in-depth:** Even if an attacker social-engineers the carrier into transferring a profile:
> 1. The **TPM on the original device** still attests the original IMEI
> 2. The stolen profile on attacker's device → attacker's TPM attests attacker's IMEI
> 3. **Mismatch detected:** TPM-attested IMEI ≠ carrier's original binding


**Gen 4 Trust Chain:**
1. **TPM** attests IMEI/IMSI from hardware (device-side proof)
2. **Carrier** verifies IMEI-IMSI binding from HLR/HSS (network-side proof)
3. **ZKP** proves: TPM-attested values == Carrier-verified values
4. **Result:** Closed loop — both device and network confirm identity

### 7.3 Key Distribution

MNO public verification keys should be distributed via a well-known endpoint:

```
GET https://api.telco.example/.well-known/mno-signing-keys.json
```

Response:
```json
{
  "keys": [
    {
      "key_id": "mno-signing-key-2026-01",
      "algorithm": "EdDSA",
      "public_key": "<base64-encoded Ed25519 public key>",
      "valid_from": "2026-01-01T00:00:00Z",
      "valid_until": "2027-01-01T00:00:00Z"
    }
  ]
}
```

Key rotation follows standard JWKS patterns with overlap periods.

### 7.4 Integration with Gen 4 ZKP

The signed endorsement becomes a **private input** to the ZK circuit:

```
┌─────────────────────────────────────────────────────────────────┐
│                     ZKP CIRCUIT INPUTS                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Private Witnesses:                                             │
│    • TPM-signed GPS coordinates                                 │
│    • TPM-signed IMEI/IMSI                                       │
│    • MNO signed endorsement (tower_id, device_id_hash)    ← NEW │
│                                                                 │
│  Public Inputs:                                                 │
│    • Policy zone (bounding box)                                 │
│    • Challenge nonce                                            │
│    • MNO public key (for signature verification)                │
│                                                                 │
│  Output:                                                        │
│    • 1KB SNARK (Sovereignty Receipt)                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

The ZKP circuit verifies:
1. MNO signature is valid (authentic carrier endorsement)
2. `device_id_hash` matches H(TPM-attested IMEI || IMSI)
3. GPS location falls within policy zone

**Result:** True zero-trust — all inputs cryptographically verified before ZKP generation.