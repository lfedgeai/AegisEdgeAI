# ✨ High-Assurance Federated Authorization Models

The challenge is to securely convey new claims **HW-rooted TPM attestation** and **Attested Geographic location** from the Enterprise workload to the Service Provider's (SP) policy engine in a robust **Federated Identity** architecture.

## 🏛️ Model 1: Single Identity JWT with old and new claims 

This model embeds *all* claims—identity, role, and hardware assurance—into a single, comprehensive, and fully **signed JWT**.

### 🔑 Security Claims and Sourcing

| Claim Type              | Location       | Assurance Level         | Source & Signing Authority              |
|--------------------------|----------------|-------------------------|-----------------------------------------|
| **Identity & Role**      | JWT Payload    | High                    | Enterprise IDP                          |
| **TPM Attestation**      | **JWT Payload**| **Highest (HW-Rooted)** | Enterprise-Trusted Attestation Service  |
| **Attested Geolocation** | **JWT Payload**| **Highest (HW-Rooted)** | Enterprise-Trusted Attestation Service  |

### Flow and Trade-Offs
1. **Flow:** The Enterprise IDP gathers all claims and issues a single, signed JWT. The SP performs **one signature verification** (using the IDP’s public key) and trusts everything inside the token.  
2. **PRO:** **Unquestionable Integrity.** The single signature guarantees authenticity and non-tampering of *all* authorization data, simplifying SP validation.  
3. **CON:** **Low Agility.** The token’s TTL must be extremely short (e.g., minutes) to ensure TPM/Geo data is current, leading to **high-overhead, frequent token re-issuance**.  

## 🛡️ Model 2: New Claims in a signed JWT within a HTTP header

This model separates stable identity claims from dynamic assurance claims, placing the latter in a dynamically generated, **signed JWT** within a HTTP header.

### 🛡️ Security Claims and Sourcing

| Claim Type              | Location                     | Assurance Level | Source & Integrity Mechanism     |
|--------------------------|------------------------------|-----------------|----------------------------------|
| **Identity & Role**      | **JWT Payload**              | High            | Enterprise IDP (Signed)          |
| **TPM/Geo Claims**       | **Nested JWT** in HTTP Header| **Highest**     | Enterprise/Device-Signed Token   |

### Flow and Trade-Offs
1. **Flow:** The Enterprise client generates and signs the Nested JWT for the latest TPM/Geo data. The SP verifies **two signatures** – one for the Identity JWT (IDP key) and one for the HTTP header JWT (device key).  
2. **PRO:** **Highest Flexibility.** Claims can be updated instantly by the device (per request) without refreshing the Identity JWT.  
3. **CON:** **Maximum Complexity.** Requires sophisticated client logic and SP infrastructure to manage and verify many ephemeral device signing keys.  

## Model 3: New Claims with a short-lived X.509 Certificate (e.g., SPIFFE/SPIRE SVID)

This model replaces the JWT for primary identity and role claims with a short-lived **X.509 Certificate (SVID)** issued to the workload. The assurance claims (TPM/Geo) are then anchored to the certificate.

## 🎯 Strategic Conclusion: The Ownership Factor

The optimal authorization model depends on the **ownership and trust relationship** between the Enterprise workload and the Service Provider (SP) application.

| Deployment Context         | Key Challenge                                                                 | Recommended Model | Rationale |
|-----------------------------|-------------------------------------------------------------------------------|-------------------|-----------|
| **B2B (federation)**   | Trust & Complexity: Difficulty in establishing shared PKI for device-specific keys across orgs. | **Model 1**       | Simplest trust anchor (Enterprise IDP signature), easiest for external SPs. |
| **Internal (no federation)** | Performance & Agility: Overcoming high-overhead, low-agility bottleneck of Model 1. | **Model 2 (Transitional)** | Delegates dynamic claims to device without full Workload Identity System. |
| **Internal (no federation) or External (federation, e.g., SPIFFE/SPIRE)** | Highest Security & Scalability: Achieving HW-rooted identity, automated renewal, and mutual authentication. | **Model 3 (Gold Standard)** | Workload identity identity standard (e.g. SPIFFE/SPIRE) across organizations. |

## JSON Schema for Geographic Result Claims

Based on [draft-richardson-rats-geographic-results](https://datatracker.ietf.org/doc/draft-richardson-rats-geographic-results/), the following JSON Schema represents the CDDL definition for geographic attestation results:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://example.com/schemas/geographic-result-claims.json",
  "title": "Geographic Result Claims",
  "description": "JSON Schema for geographic attestation results as defined in draft-richardson-rats-geographic-results",
  "type": "object",
  "minProperties": 1,
  "properties": {
    "grc.jurisdiction-country": {
      "type": "string",
      "description": "ISO 3166-1 alpha-2 country code",
      "pattern": "^[A-Z]{2}$",
      "examples": ["US", "CA", "GB"]
    },
    "grc.jurisdiction-country-exclave": {
      "type": "boolean",
      "description": "Indicates if the jurisdiction country is an exclave"
    },
    "grc.jurisdiction-state": {
      "type": "string",
      "description": "Country-specific state or province identifier",
      "minLength": 2,
      "maxLength": 16,
      "examples": ["California", "TX", "Ontario"]
    },
    "grc.jurisdiction-state-exclave": {
      "type": "boolean",
      "description": "Indicates if the jurisdiction state is an exclave"
    },
    "grc.jurisdiction-city": {
      "type": "string",
      "description": "State-specific city identifier",
      "minLength": 2,
      "maxLength": 16,
      "examples": ["San Francisco", "Toronto", "London"]
    },
    "grc.jurisdiction-city-exclave": {
      "type": "boolean",
      "description": "Indicates if the jurisdiction city is an exclave"
    },
    "grc.physical-country": {
      "type": "string",
      "description": "ISO 3166-1 alpha-2 country code where the entity is physically located (as opposed to jurisdiction)",
      "pattern": "^[A-Z]{2}$",
      "examples": ["US", "CA", "GB"]
    },
    "grc.physical-state": {
      "type": "string",
      "description": "Physical state or province where the entity is actually located (as opposed to jurisdiction)",
      "minLength": 2,
      "maxLength": 16,
      "examples": ["California", "TX", "Ontario"]
    },
    "grc.physical-city": {
      "type": "string",
      "description": "Physical city where the entity is actually located (as opposed to jurisdiction)",
      "minLength": 2,
      "maxLength": 16,
      "examples": ["Los Angeles", "Toronto", "London"]
    },
    "grc.datacenter": {
      "type": "object",
      "description": "Data center physical infrastructure location details",
      "properties": {
        "near-to": {
          "type": "string",
          "description": "UUID of another entity that this target environment is near to",
          "format": "uuid",
          "examples": ["550e8400-e29b-41d4-a716-446655440000"]
        },
        "rack-U-number": {
          "type": "integer",
          "description": "Rack unit number, numbered from bottom RU as 1",
          "minimum": 1,
          "examples": [1, 42]
        },
        "cabinet-number": {
          "type": "integer",
          "description": "Data center specific cabinet ordering number",
          "minimum": 1,
          "examples": [1, 15]
        },
        "hallway-number": {
          "type": "integer",
          "description": "Hallway number identifier",
          "minimum": 0,
          "examples": [0, 5]
        },
        "room-number": {
          "type": "string",
          "description": "Room number or identifier",
          "minLength": 2,
          "maxLength": 64,
          "examples": ["101", "Server Room A", "DC-1-Room-42"]
        },
        "floor-number": {
          "type": "integer",
          "description": "Floor number, usually representing an integer",
          "examples": [1, 0, -1, 42]
        }
      },
      "additionalProperties": false
    },
    "grc.workload": {
      "type": "object",
      "description": "Workload identity and identification details",
      "properties": {
        "workload-id": {
          "type": "string",
          "description": "Workload identifier, typically a SPIFFE ID",
          "examples": ["spiffe://example.org/python-app", "spiffe://example.org/frontend-service"]
        },
        "key-source": {
          "type": "string",
          "enum": ["workload-key", "tpm-app-key"],
          "description": "Indicates which key is used for signing and mTLS. When set to 'tpm-app-key', the workload uses grc.tpm-attestation.app-key-public for both operations, and the public-key field should be omitted. When set to 'workload-key', the public-key field must be present.",
          "examples": ["tpm-app-key", "workload-key"]
        },
        "public-key": {
          "type": "string",
          "description": "Workload public key in PEM format or base64-encoded key material. Required when key-source is 'workload-key', omitted when key-source is 'tpm-app-key' (in which case use grc.tpm-attestation.app-key-public). Used for both signing and mTLS operations.",
          "examples": [
            "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE..."
          ]
        }
      },
      "additionalProperties": false
    },
    "grc.tpm-attestation": {
      "type": "object",
      "description": "TPM (Trusted Platform Module) attestation evidence and keys",
      "properties": {
        "tpm-quote": {
          "type": "string",
          "description": "Base64-encoded TPM Quote (portable string). Must be non-empty, valid base64, and size <= 64kB",
          "minLength": 1,
          "maxLength": 65536,
          "examples": ["AQAAAAAAAADwAAAAAAA..."]
        },
        "app-key-public": {
          "type": "string",
          "description": "The App Key public key in PEM format (preferred) or base64-encoded. Must parse as valid public key when present",
          "examples": [
            "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE..."
          ]
        },
        "app-key-certificate": {
          "type": "string",
          "description": "Base64-encoded DER or PEM certificate proving the App Key was issued/signed by the host Attestation Key (AK). MUST be Base64-encoded when transmitted over JSON/REST. Must parse to valid X.509 certificate when present",
          "examples": [
            "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...",
            "MIIBkTCB+wIJAK..."
          ]
        },
        "ak-public": {
          "type": "string",
          "description": "Attestation Key (AK) public key in PEM format (preferred) or base64-encoded",
          "examples": [
            "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE..."
          ]
        },
        "ek-public": { // optional for peer verification
          "type": "string",
          "description": "Endorsement Key (EK) public key in PEM format (preferred) or base64-encoded",
          "examples": [
            "-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...\n-----END PUBLIC KEY-----",
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE..."
          ]
        }
      },
      "additionalProperties": false
    }
  },
  "additionalProperties": false
}
```

> **Note:** This JSON Schema is converted from the CDDL definition in [draft-richardson-rats-geographic-results](https://datatracker.ietf.org/doc/draft-richardson-rats-geographic-results/). All properties are optional, with `minProperties: 1` ensuring at least one claim is present (matching CDDL's `non-empty<{...}>` constraint). The data center infrastructure fields (near-to, rack-U-number, cabinet-number, hallway-number, room-number, floor-number) have been nested under `grc.datacenter` for better organization, deviating from the flat structure in the original CDDL. Additional fields for workload identity (`grc.workload`) and TPM attestation (`grc.tpm-attestation`) have been added to support hardware-rooted attestation and workload identity verification.

### Workload Key Source Usage

The `grc.workload.key-source` field indicates which key is used for both signing and mTLS operations:

**When `key-source: "tpm-app-key"`** (e.g., SPIRE agent using TPM):
```json
{
  "grc.workload": {
    "workload-id": "spiffe://example.org/spire-agent",
    "key-source": "tpm-app-key"
    // public-key omitted - use grc.tpm-attestation.app-key-public
  },
  "grc.tpm-attestation": {
    "app-key-public": "-----BEGIN PUBLIC KEY-----\n..."
  }
}
```

**When `key-source: "workload-key"`** (traditional workload key):
```json
{
  "grc.workload": {
    "workload-id": "spiffe://example.org/python-app",
    "key-source": "workload-key",
    "public-key": "-----BEGIN PUBLIC KEY-----\n..."
  }
}
```

The validator should use `grc.tpm-attestation.app-key-public` for both signing and mTLS when `key-source` is `"tpm-app-key"`, eliminating the need for a separate workload public key.

## Appendix: Understanding Jurisdiction vs. Physical Location

### Key Concepts

**Jurisdiction** refers to the **legal/sovereign territory** you're subject to—determines which country's laws, regulations, and courts apply. This may differ from your physical location.

**Physical Location** refers to the **actual geographic location** where the entity/hardware is physically located—the country that physically contains the infrastructure.

### Use Case Examples

#### 1. Embassy/Consulate Scenario
```json
{
  "grc.jurisdiction-country": "KR",
  "grc.jurisdiction-country-exclave": true,
  "grc.physical-country": "US",
  "grc.physical-state": "California",
  "grc.physical-city": "Los Angeles"
}
```
**Context**: Korean consulate in Los Angeles
- **Jurisdiction**: Legally Korean territory (subject to Korean law)
- **Physical**: Actually located in the United States
- **Why it matters**: Data processed here may be subject to Korean data protection laws, not US laws

#### 2. Data Center in Special Economic Zone
```json
{
  "grc.jurisdiction-country": "HK",
  "grc.physical-country": "CN",
  "grc.physical-state": "Guangdong",
  "grc.physical-city": "Shenzhen"
}
```
**Context**: Hong Kong-registered data center physically located in mainland China
- **Jurisdiction**: Subject to Hong Kong legal framework
- **Physical**: Located in mainland China
- **Why it matters**: Different regulatory requirements despite geographic proximity

#### 3. Normal Case (No Exclave)
```json
{
  "grc.jurisdiction-country": "US",
  "grc.jurisdiction-state": "California",
  "grc.jurisdiction-city": "San Francisco",
  "grc.physical-country": "US",
  "grc.physical-state": "California",
  "grc.physical-city": "San Francisco"
}
```
**Context**: Standard deployment where jurisdiction matches physical location
- **Both match**: No exclave situation
- **Why it matters**: When they match, you may only need jurisdiction fields; physical fields are optional

### Why This Distinction Matters

For **federated JWT authorization**, this distinction enables:

- **Data Residency Compliance**: Verify where data must legally be stored vs. where it physically resides
- **Regulatory Requirements**: Determine which country's regulations apply to the workload
- **Policy Enforcement**: Service Provider can verify both legal jurisdiction and physical location independently
- **Exclave Handling**: Properly handle embassies, consulates, and special territories where legal and physical locations differ

The exclave boolean flags (`grc.jurisdiction-*-exclave`) indicate when jurisdiction ≠ physical location due to exclave situations.

## Appendix: Standard JWT Format

### JWT Structure

A JSON Web Token (JWT) consists of three parts separated by dots (`.`):

```
header.payload.signature
```

Each part is **Base64URL-encoded** JSON.

### 1. Header

The header typically contains the token type and the signing algorithm:

```json
{
  "alg": "RS256",
  "typ": "JWT"
}
```

**Common algorithms:**
- `HS256` - HMAC with SHA-256
- `RS256` - RSA Signature with SHA-256
- `ES256` - ECDSA using P-256 and SHA-256
- `PS256` - RSASSA-PSS with SHA-256

### 2. Payload (Claims)

The payload contains the **claims** - statements about an entity and additional data. There are three types of claims:

#### Registered Claims (Standard JWT Claims)

These are predefined claims recommended by [RFC 7519](https://datatracker.ietf.org/doc/html/rfc7519):

```json
{
  "iss": "https://idp.example.com",           // Issuer
  "sub": "user@example.com",                  // Subject
  "aud": "https://api.example.com",           // Audience
  "exp": 1735689600,                          // Expiration time (Unix timestamp)
  "nbf": 1735686000,                          // Not before (Unix timestamp)
  "iat": 1735686000,                          // Issued at (Unix timestamp)
  "jti": "unique-token-id"                    // JWT ID
}
```
### 3. Signature

The signature is created by:

1. Taking the encoded header and payload
2. Creating a signature using the algorithm specified in the header
3. Base64URL-encoding the signature

**Signature creation:**
```
signature = base64url(
  HMAC-SHA256(
    base64url(header) + "." + base64url(payload),
    secret
  )
)
```

For RSA/ECDSA, the private key is used to sign.

## Appendix: TPM Key and Attestation Primer

The Trusted Platform Module (TPM) is a secure crypto-processor that provides a **Hardware Root of Trust**. It protects cryptographic keys and ensures platform integrity, binding security directly to the physical device.

### 🔑 Key Hierarchy: Identity and Privacy

| Term | Full Name / Function | Purpose | Security Context |
|------|---------------------|---------|------------------|
| **TPM EK** | Endorsement Key | The TPM's unique, permanent hardware ID, burned in at the factory. Its private key never leaves the TPM. | **Device Identity**. Used to secure all other keys and prove the TPM's authenticity to a CA. |
| **TPM AK** | Attestation Key | A key generated by the TPM, unique per platform/context, and certified by a CA. | **Privacy and Attestation**. Used to sign quotes without revealing the unique EK identity, preventing tracking. |
| **TPM App Key** | Application Key | A general-purpose key pair created for application use (e.g., signing data, client mTLS). | **Application Use**. Used for real-world crypto operations; protected by the TPM and certified to be non-exportable. |

### 📄 Certification and Trust

| Term | Function | Chain of Trust | Security Context |
|------|----------|----------------|------------------|
| **TPM App Cert** | Application Key Certificate (often certified by the AK) | This certificate cryptographically proves that the App Key's private component is genuinely resident within the TPM that owns the certified AK. | **Hardware Binding**. Gives a remote party confidence that the application key is non-exportable and protected by hardware. |

### 📝 Integrity and Proof

| Term | Function | Purpose | Security Context |
|------|----------|---------|------------------|
| **TPM Quote** | A digitally signed report of the Platform Configuration Registers (PCRs). | **Platform Integrity**. The PCRs contain cryptographic hashes (measurements) of the boot-up code (BIOS, bootloader, OS kernel), representing the system's current state. The AK signs the quote. | **Remote Attestation**. A remote party can verify the quote's signature (using the AK public key) and then compare the PCR values against a known good baseline to prove the platform booted into a trusted, uncompromised state. |

### Summary

In essence:
- **The EK** proves the TPM is genuine
- **The AK** signs statements (like Quotes and App Key Certs) while protecting the EK's privacy
- **The App Key** is your application's actual credential, which is certified by the AK process
- **The Quote** is the evidence of the platform's measured boot integrity
