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
3. **CON:** **Maximum Complexity.** Requires sophisticated SP infrastructure to verify two signatures per request and manage the trust anchor for every Enterprise device's Attestation Key (AK), complicating cross-organizational PKI establishment.  

## Model 3: New Claims with a short-lived X.509 Certificate (e.g., SPIFFE/SPIRE SVID)

This model replaces the JWT for primary identity and role claims with a short-lived **X.509 Certificate (SVID)** issued to the workload. The assurance claims (TPM/Geo) are then anchored to the certificate.

## 🎯 Strategic Conclusion: The Ownership Factor

The optimal authorization model depends on the **ownership and trust relationship** between the Enterprise workload and the Service Provider (SP) application.

| Deployment Context         | Key Challenge                                                                 | Recommended Model | Rationale |
|-----------------------------|-------------------------------------------------------------------------------|-------------------|-----------|
| **B2B (federation)**   | Trust & Complexity: Difficulty in establishing shared PKI for device-specific keys across orgs. | **Model 1**       | Simplest trust anchor (Enterprise IDP signature), easiest for external SPs. |
| **Internal (no federation)** | Performance & Agility: Overcoming high-overhead, low-agility bottleneck of Model 1. | **Model 2 (Transitional)** | Delegates dynamic claims to device without full Workload Identity System. |
| **Internal (no federation) or External (federation, e.g., SPIFFE/SPIRE)** | Highest Security & Scalability: Achieving HW-rooted identity, automated renewal, and mutual authentication. | **Model 3 (Gold Standard)** | Workload identity identity standard (e.g. SPIFFE/SPIRE) across organizations. |

## The Problem: Authentication Method Reference (AMR) "geo" Claim

The current standard for indicating geolocation verification in OIDC/OAuth tokens is the **Authentication Method Reference (AMR) "geo" claim** as defined in [RFC 8176](https://datatracker.ietf.org/doc/html/rfc8176).

### Critical Gaps in Current Implementation

The existing AMR "geo" claim has significant limitations:

1. **Unverifiable String**: It's just an unverifiable string value with no cryptographic proof.
2. **No Defined Semantics**: There's no standard definition of what "geo" means—what level of verification? What location format? What assurance level?
3. **No Verifiability**: A Relying Party cannot cryptographically verify that the location claim is authentic or that it hasn't been tampered with.
4. **No Rich Data**: It provides no structured information about jurisdiction, physical location, or attestation method.

### Our Proposal: A Standard for Verifiable Claims

This document proposes a comprehensive solution that:

- **Defines a standard, interoperable JSON format** for rich location data (jurisdiction, physical location in multiple formats, location sensor hardware).
- **Provides cryptographically verified location results** via hardware attestation (TPM-based location verification).
- **Enables drop-in use** in any JSON-based token (OIDC ID Token, OAuth Access Token) or SAML assertions.
- **Supports fine-grained policy enforcement** through structured claims that can be validated and verified by Relying Parties.
- **Compatible with emerging OIDC standards**: The unified claims JSON structure can be signed and included as a value in a custom verifiable claim (e.g., `verified_claims`) as defined by standards like OpenID Connect for Identity Assurance, providing a pathway for eventual OIDC standardization.

The unified identity claims schema defined in this document addresses these gaps by providing:
- Structured, verifiable geographic claims
- Hardware-rooted attestation evidence
- Standardized format for interoperability
- Rich metadata for policy enforcement

The goal is to standardize the claims and the format of the claims through IANA so that they can be used in any JSON-based token (OIDC ID Token, OAuth Access Token) or SAML assertions or other formats. If there are any similar Oauth AMR claims (e.g. "geo"), they should be deprecated and replaced with this standard.

## JSON Schema for Unified Identity Claims

Based on [draft-richardson-rats-geographic-results](https://datatracker.ietf.org/doc/draft-richardson-rats-geographic-results/), the following JSON Schema represents unified identity claims including geographic location, workload identity, TPM attestation, and data center infrastructure:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://example.com/schemas/unified-identity-claims.json",
  "title": "Unified Identity Claims",
  "description": "JSON Schema for unified identity claims including geographic location, workload identity, TPM attestation, and data center infrastructure. Extends draft-richardson-rats-geographic-results with additional identity and attestation fields.",
  "type": "object",
  "minProperties": 1,
  "properties": {
    "grc.geolocation": {
      "type": "object",
      "description": "Geographic location information including legal jurisdiction and physical location",
      "properties": {
        "jurisdiction": {
          "type": "object",
          "description": "Legal/sovereign territory information - determines which country's laws, regulations, and courts apply",
          "properties": {
            "country": {
              "type": "string",
              "description": "ISO 3166-1 alpha-2 country code",
              "pattern": "^[A-Z]{2}$",
              "examples": ["US", "CA", "GB"]
            },
            "country-exclave": {
              "type": "boolean",
              "description": "Indicates if the jurisdiction country is an exclave"
            },
            "state": {
              "type": "string",
              "description": "Country-specific state or province identifier",
              "minLength": 2,
              "maxLength": 16,
              "examples": ["California", "TX", "Ontario"]
            },
            "state-exclave": {
              "type": "boolean",
              "description": "Indicates if the jurisdiction state is an exclave"
            },
            "city": {
              "type": "string",
              "description": "State-specific city identifier",
              "minLength": 2,
              "maxLength": 16,
              "examples": ["San Francisco", "Toronto", "London"]
            },
            "city-exclave": {
              "type": "boolean",
              "description": "Indicates if the jurisdiction city is an exclave"
            }
          },
          "additionalProperties": false
        },
        "physical-location": {
          "type": "object",
          "description": "Physical location where the entity is actually located (as opposed to jurisdiction). Supports three formats: precise coordinates, approximated region, or administrative boundaries.",
          "properties": {
            "format": {
              "type": "string",
              "enum": ["precise", "approximated", "administrative"],
              "description": "Location format type: 'precise' for exact coordinates, 'approximated' for approximate region, 'administrative' for country/state/city boundaries"
            },
            "precise": {
              "type": "object",
              "description": "Precise location using WGS84 coordinates (format: precise)",
              "properties": {
                "latitude": {
                  "type": "number",
                  "description": "Latitude in decimal degrees (WGS84)",
                  "minimum": -90,
                  "maximum": 90,
                  "examples": [37.7749, -122.4194]
                },
                "longitude": {
                  "type": "number",
                  "description": "Longitude in decimal degrees (WGS84)",
                  "minimum": -180,
                  "maximum": 180,
                  "examples": [-122.4194, 2.3522]
                },
                "altitude": {
                  "type": "number",
                  "description": "Altitude in meters above sea level (optional)",
                  "examples": [0, 100, -50]
                },
                "accuracy": {
                  "type": "number",
                  "description": "Accuracy radius in meters (optional)",
                  "minimum": 0,
                  "examples": [10, 100, 1000]
                }
              },
              "required": ["latitude", "longitude"],
              "additionalProperties": false
            },
            "approximated": {
              "type": "object",
              "description": "Approximated location using circle or polygon (format: approximated). Compatible with [CAMARA Device Location API](https://github.com/camaraproject/DeviceLocation) formats.",
              "properties": {
                "circle": {
                  "type": "object",
                  "description": "Circle defining the approximate region (center point with radius)",
                  "properties": {
                    "latitude": {
                      "type": "number",
                      "description": "Center latitude in decimal degrees (WGS84)",
                      "minimum": -90,
                      "maximum": 90,
                      "examples": [37.7749, -122.4194]
                    },
                    "longitude": {
                      "type": "number",
                      "description": "Center longitude in decimal degrees (WGS84)",
                      "minimum": -180,
                      "maximum": 180,
                      "examples": [-122.4194, 2.3522]
                    },
                    "radius": {
                      "type": "number",
                      "description": "Radius in meters defining the circular area",
                      "minimum": 0,
                      "examples": [100, 1000, 5000]
                    }
                  },
                  "required": ["latitude", "longitude", "radius"],
                  "additionalProperties": false
                },
                "polygon": {
                  "type": "object",
                  "description": "Polygon defining the approximate region (closed shape bounded by straight sides)",
                  "properties": {
                    "boundary": {
                      "type": "array",
                      "description": "List of points defining the polygon boundary. The polygon is closed (last point connects to first point). Compatible with [CAMARA Device Location Retrieval API](https://github.com/camaraproject/DeviceLocation) polygon format.",
                      "minItems": 3,
                      "maxItems": 15,
                      "items": {
                        "type": "object",
                        "description": "Point coordinates (latitude, longitude) defining a location",
                        "properties": {
                          "latitude": {
                            "type": "number",
                            "description": "Latitude in decimal degrees (WGS84)",
                            "minimum": -90,
                            "maximum": 90,
                            "examples": [45.754114, 37.7749]
                          },
                          "longitude": {
                            "type": "number",
                            "description": "Longitude in decimal degrees (WGS84)",
                            "minimum": -180,
                            "maximum": 180,
                            "examples": [4.860374, -122.4194]
                          }
                        },
                        "required": ["latitude", "longitude"],
                        "additionalProperties": false
                      }
                    }
                  },
                  "required": ["boundary"],
                  "additionalProperties": false
                }
              },
              "additionalProperties": false,
              "oneOf": [
                {
                  "required": ["circle"]
                },
                {
                  "required": ["polygon"]
                }
              ]
            },
            "administrative": {
              "type": "object",
              "description": "Administrative boundaries: country, state, city (format: administrative). Note: Reverse geocoding libraries (e.g., GeoNames, Google Geocoding API, OpenStreetMap Nominatim) can be used to convert physical latitude/longitude coordinates to administrative boundaries.",
              "properties": {
                "country": {
                  "type": "string",
                  "description": "ISO 3166-1 alpha-2 country code",
                  "pattern": "^[A-Z]{2}$",
                  "examples": ["US", "CA", "GB"]
                },
                "state": {
                  "type": "string",
                  "description": "State or province identifier",
                  "minLength": 2,
                  "maxLength": 16,
                  "examples": ["California", "TX", "Ontario"]
                },
                "city": {
                  "type": "string",
                  "description": "City identifier",
                  "minLength": 2,
                  "maxLength": 16,
                  "examples": ["Los Angeles", "Toronto", "London"]
                }
              },
              "additionalProperties": false
            }
          },
          "required": ["format"],
          "additionalProperties": false,
          "oneOf": [
            {
              "properties": {
                "format": {"const": "precise"},
                "precise": {"type": "object"}
              },
              "required": ["precise"]
            },
            {
              "properties": {
                "format": {"const": "approximated"},
                "approximated": {"type": "object"}
              },
              "required": ["approximated"]
            },
            {
              "properties": {
                "format": {"const": "administrative"},
                "administrative": {"type": "object"}
              },
              "required": ["administrative"]
            }
          ]
        }
      },
      "location-sensor-hardware": {
        "type": "object",
        "description": "Hardware sensor information used to determine location",
        "properties": {
          "sensor-type": {
            "type": "string",
            "enum": ["GNSS", "Mobile"],
            "description": "Type of location sensor: GNSS (Global Navigation Satellite System) or Mobile (cellular network-based)"
          },
          "serial-number": {
            "type": "string",
            "description": "Serial number of the location sensor hardware",
            "minLength": 1,
            "maxLength": 64,
            "examples": ["SN123456789", "GPS-2024-001"]
          },
          "imei": {
            "type": "string",
            "description": "International Mobile Equipment Identity (IMEI) - required when sensor-type is 'Mobile'",
            "pattern": "^[0-9]{14,15}$",
            "examples": ["123456789012345"]
          },
          "imsi": {
            "type": "string",
            "description": "International Mobile Subscriber Identity (IMSI) - required when sensor-type is 'Mobile'",
            "pattern": "^[0-9]{14,15}$",
            "examples": ["310150123456789"]
          }
        },
        "required": ["sensor-type", "serial-number"],
        "additionalProperties": false,
        "allOf": [
          {
            "if": {
              "properties": {
                "sensor-type": {"const": "Mobile"}
              }
            },
            "then": {
              "required": ["imei", "imsi"]
            }
          }
        ]
      }
    },
    "additionalProperties": false
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
        "tpm-pcr-mask": {
          "type": "string",
          "description": "PCR Set Mask indicating which Platform Configuration Registers (PCRs) were measured. Represented as a hexadecimal bitmask where each bit corresponds to a PCR index (e.g., 0x80000003 indicates PCRs 0, 1, 2, 16, 17). This enables fine-grained verification of which components were measured (firmware, bootloader, secure boot, etc.).",
          "pattern": "^0x[0-9a-fA-F]+$",
          "examples": ["0x80000003", "0x00000007", "0xFFFFFFFF"]
        },
        "tpm-policy-id": {
          "type": "string",
          "description": "UUID or reference ID pointing to the specific baseline of 'known good' hashes against which the PCR values should be checked. This allows Service Providers to enforce fine-grained authorization logic based on specific boot policies (e.g., 'Only allow access if attested with Policy ID X for Linux boot with PCRs 0, 1, 7'). Can be a UUID or a string identifier.",
          "minLength": 1,
          "maxLength": 128,
          "examples": ["550e8400-e29b-41d4-a716-446655440000", "linux-boot-policy-v1", "secure-boot-baseline-2024"]
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
    },
    "rat-nonce": { // optional for peer verification
      "type": "string",
      "description": "Remote Attestation Nonce (RAT nonce) for freshness verification and anti-replay protection. This nonce ensures the attestation evidence is fresh and specific to the current transaction. For TPM attestation, it should be included in the EK-Signed Proof/Credential. The verifier checks that signed proofs contain the exact, expected nonce value to prevent replay attacks. If the nonce is derived from binary challenge data (e.g., from EK-Signed Proof/Credential), it should be Base64URL-encoded to align with JWT transport standards.",
      "minLength": 16,
      "maxLength": 256,
      "examples": ["550e8400-e29b-41d4-a716-446655440000", "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6"]
    }
  },
  "additionalProperties": false
}
```

## TPM-Bound Geolocation

To provide the **highest possible assurance** for location claims, the system should adopt a binding mechanism where the **TPM Attestation Key (AK) cryptographically signs the geolocation evidence**, rather than relying solely on the Identity Provider's (IDP) signature. This approach, often called **TPM-Bound Geolocation**, involves the client's TPM hashing the raw location data (coordinates, Nonce, and time) and sealing the hash into a **Platform Configuration Register (PCR)**. The resulting **TPM Quote** is then verifiable by the Service Provider (SP), who can compare the attested PCR value against a hash of the expected location data. This process ensures **non-repudiation** and **tamper-evidence**, proving that the location data was present and attested by a genuine, uncompromised hardware root-of-trust **at the time of the integrity check**.

## Revocation Mechanisms for Identity Claims

All high-assurance identity models must explicitly address failure scenarios. When a device's TPM is compromised, when the host is compromised, when workload keys are retired, or when any identity claim becomes invalid, revocation mechanisms are critical to prevent unauthorized access.

**Revocation Handling by Authorization Model:**

#### Model 1: Single Identity JWT

- **Revocation Method**: The Enterprise IDP must revoke the entire JWT immediately when any component is compromised (TPM App Key, workload key, geographic attestation, etc.) or when identity/role claims become invalid.
- **Rationale**: Since all claims (identity, role, TPM attestation, geographic) are in a single signed JWT, revocation requires invalidating the entire token.
- **Implementation**: This justifies the short TTL (e.g., minutes) mentioned in Model 1, as compromised credentials can only be used until the token expires naturally or is explicitly revoked by the IDP.

#### Model 2: Nested JWT in HTTP Header

- **Revocation Method**: The Service Provider must query an Enterprise-operated Certificate Revocation List (CRL) or OCSP responder for the device's key certificate (App Key Certificate for TPM-based keys, or workload key certificate) before accepting the nested JWT.
- **Rationale**: Even if the Identity JWT hasn't expired, compromised hardware keys or invalid attestation claims must be unusable. The SP verifies the key certificate status independently of the Identity JWT.
- **Implementation**: The SP performs certificate status checking as part of the nested JWT verification process, ensuring the device key (whether TPM App Key or workload key) hasn't been revoked.

#### Model 3: X.509 Certificate (SPIFFE/SPIRE SVID)

- **Revocation Method**: The Service Provider must check the SVID's revocation status via CRL or OCSP before accepting the certificate.
- **Rationale**: Standard X.509 certificate revocation mechanisms apply. The SP verifies both the certificate chain and revocation status.
- **Implementation**: The SP checks revocation status as part of standard certificate validation, ensuring compromised keys (TPM App Keys or workload keys) bound to SVIDs are immediately unusable. For mTLS connections, **OCSP stapling** should be used to improve performance—the device delivers the fresh, CA-signed revocation proof during the TLS handshake, reducing the burden on the SP to query the CA directly.

**TPM-Specific Revocation Considerations:**

**TPM App Key Revocation:**
- When a TPM App Key is compromised or retired, it must be revoked through the appropriate mechanism for the authorization model (JWT revocation for Model 1, CRL/OCSP for Models 2 and 3).

**TPM Quote Status Checking:**
- Service Providers should verify that the TPM Quote itself hasn't been invalidated due to:
  - Platform integrity violations (PCR values indicating compromised boot state)
  - Policy violations (measured values don't match the expected baseline for the Policy ID)
  - Time-based revocation (quotes from compromised time periods)

**Best Practices:**

1. **Real-time Revocation Checking**: SPs should perform revocation checks on every request, not rely solely on token expiration.
2. **Revocation List Distribution**: Enterprise operators must maintain and distribute CRLs or operate OCSP responders accessible to federated SPs.
3. **Fail-Safe Default**: If revocation status cannot be determined, the SP should deny access by default (fail-secure).
4. **Revocation Propagation**: Revocation should propagate quickly across all SPs in the federation to minimize the window of vulnerability.

### TPM Attestation Verification

#### 1. TPM Quote Verification (Integrity)

This is a classic offline cryptographic check:

- **Input**: The raw `tpm-quote` (the signed data) and the `ak-public` key.
- **Process**: The verifier uses the `ak-public` key to check the digital signature on the quote.
- **Output**: A simple pass/fail on the signature. If it passes, the verifier knows two things:
  - The Quote is genuine and came from the TPM owning the AK.
  - The PCR measurements inside the Quote are authentic and untampered.

**When a device needs to prove its integrity to a remote verifier:**
1. **The Policy is Chosen**: The system determines which software/boot components must be measured, selecting the appropriate TPM Policy ID (e.g., "Standard Linux Kernel Secure Boot").
2. **The Quote is Generated**: The system uses the PCR Mask associated with that policy to ask the TPM to generate a TPM Quote. The TPM reads the specified PCRs, hashes the list, and signs the result with the AK's private key.
3. **Verification**: The remote verifier receives the TPM Quote and the TPM Policy ID:
   - The verifier first checks the Quote's signature (using the AK public key).
   - The verifier then looks up the expected PCR values associated with the TPM Policy ID.
   - Finally, the verifier compares the measured PCR values from the Quote against the expected values from the Policy ID.
   - If the signature is valid and the measured values match the policy, the platform's integrity is verified.

#### 2. TPM App Key Certificate Verification (Identity Binding)

This is also an offline verification of a standard X.509 certificate chain:

- **Input**: The `app-key-certificate` and the AK's Public Key (`ak-public`).
- **Process**: The verifier checks the signature on the `app-key-certificate` using the AK's Public Key. The verifier must also ensure the AK's Public Key is itself trusted (typically via a separate, trusted AK Certificate issued by an offline CA).
- **Output**: A pass/fail on the certificate chain. If it passes, the verifier is assured that the App Key Public Key contained within the certificate is genuinely bound to the trusted TPM/AK.

> **Note:** This JSON Schema is converted from the CDDL definition in [draft-richardson-rats-geographic-results](https://datatracker.ietf.org/doc/draft-richardson-rats-geographic-results/). All properties are optional, with `minProperties: 1` ensuring at least one claim is present (matching CDDL's `non-empty<{...}>` constraint). For better organization, fields have been grouped into nested objects: geographic location fields (jurisdiction and physical-location) under `grc.geolocation`, data center infrastructure fields (near-to, rack-U-number, cabinet-number, hallway-number, room-number, floor-number) under `grc.datacenter`, workload identity under `grc.workload`, and TPM attestation under `grc.tpm-attestation`, deviating from the flat structure in the original CDDL. Additional fields for workload identity and TPM attestation have been added to support hardware-rooted attestation and workload identity verification.

### 3. TPM Endorsement Key (EK) Verification (Optional for Peer Verification)

By receiving the complete evidence package from the Attestation Service, the peer verifier has all the cryptographic material needed to establish the hardware root of trust without a live connection to the device or the initial CA.

**Package Components and Their Role in Offline Verification:**

| Component Conveyed | Verification Purpose | Offline Check Performed |
|-------------------|---------------------|------------------------|
| **TPM EK Public Key** | Hardware Genuineness Anchor | Acts as the public key needed to verify the manufacturer's root of trust. |
| **TPM AK Public Key** | Attestation Key Identity | Acts as the public key needed to verify the TPM Quote and the App Key Certificate. |
| **EK-Signed Proof/Credential** | AK-to-EK Binding | The verifier uses the EK Public Key to verify the signature on this proof, confirming the AK was generated by the authentic TPM hardware. |
| **Nonce** | Anti-Replay Protection | The verifier checks that the EK-Signed Proof contains the exact, expected nonce value, guaranteeing the evidence is fresh and specific to the current transaction. |

**🛡️ Trust Gained Through Offline Verification**

By successfully verifying all four components, the peer verifier gains a very high level of trust:

- **Hardware Trust (via EK)**: They confirm that the AK Public Key is genuinely bound to a specific, certified piece of TPM hardware.
- **Liveness/Freshness (via Nonce)**: They confirm the proof is current and not a replay of old data.
- **Integrity Trust (via AK)**: Once the AK is trusted, they can then proceed to use it to verify the TPM Quote (integrity evidence) and the TPM App Key Certificate (workload identity).

This is why conveying this complete package is the highest standard for federated, high-assurance identity verification.

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

## References

- [CAMARA Device Location Verification API](https://github.com/camaraproject/DeviceLocation)
- [Reverse Geocode](https://pypi.org/project/reverse-geocode/)

## Appendix: Understanding Jurisdiction vs. Physical Location

### Key Concepts

**Jurisdiction** refers to the **legal/sovereign territory** you're subject to—determines which country's laws, regulations, and courts apply. This may differ from your physical location.

**Physical Location** refers to the **actual geographic location** where the entity/hardware is physically located—the country that physically contains the infrastructure.

### Use Case Examples

#### 1. Embassy/Consulate Scenario
```json
{
  "grc.geolocation": {
    "jurisdiction": {
      "country": "KR",
      "country-exclave": true
    },
    "physical-location": {
      "format": "administrative",
      "administrative": {
        "country": "US",
        "state": "California",
        "city": "Los Angeles"
      }
    }
  }
}
```
**Context**: Korean consulate in Los Angeles
- **Jurisdiction**: Legally Korean territory (subject to Korean law)
- **Physical**: Actually located in the United States
- **Why it matters**: Data processed here may be subject to Korean data protection laws, not US laws

#### 2. Data Center in Special Economic Zone
```json
{
  "grc.geolocation": {
    "jurisdiction": {
      "country": "HK"
    },
    "physical-location": {
      "format": "administrative",
      "administrative": {
        "country": "CN",
        "state": "Guangdong",
        "city": "Shenzhen"
      }
    }
  }
}
```
**Context**: Hong Kong-registered data center physically located in mainland China
- **Jurisdiction**: Subject to Hong Kong legal framework
- **Physical**: Located in mainland China
- **Why it matters**: Different regulatory requirements despite geographic proximity

#### 3. Normal Case (No Exclave)
```json
{
  "grc.geolocation": {
    "jurisdiction": {
      "country": "US",
      "state": "California",
      "city": "San Francisco"
    },
    "physical-location": {
      "format": "administrative",
      "administrative": {
        "country": "US",
        "state": "California",
        "city": "San Francisco"
      }
    }
  }
}
```
**Context**: Standard deployment where jurisdiction matches physical location
- **Both match**: No exclave situation
- **Why it matters**: When they match, you may only need jurisdiction fields; physical fields are optional

#### 4. Precise Location Example
```json
{
  "grc.geolocation": {
    "physical-location": {
      "format": "precise",
      "precise": {
        "latitude": 37.7749,
        "longitude": -122.4194,
        "accuracy": 10
      }
    }
  }
}
```
**Context**: Exact GPS coordinates with accuracy radius
- **Use case**: When precise location is required (e.g., compliance with specific building/room requirements)

#### 5. Approximated Location Example (Circle)
```json
{
  "grc.geolocation": {
    "physical-location": {
      "format": "approximated",
      "approximated": {
        "circle": {
          "latitude": 37.7749,
          "longitude": -122.4194,
          "radius": 5000
        }
      }
    }
  }
}
```
**Context**: Approximate region using circular area (center point with radius in meters)
- **Use case**: Location verification within a circular area, compatible with [CAMARA Device Location Verification API](https://github.com/camaraproject/DeviceLocation) circle format

#### 6. Approximated Location Example (Polygon - Irregular Shape)
```json
{
  "grc.geolocation": {
    "physical-location": {
      "format": "approximated",
      "approximated": {
        "polygon": {
          "boundary": [
            {
              "latitude": 45.754114,
              "longitude": 4.860374
            },
            {
              "latitude": 45.753845,
              "longitude": 4.863185
            },
            {
              "latitude": 45.752490,
              "longitude": 4.861876
            },
            {
              "latitude": 45.751224,
              "longitude": 4.861125
            },
            {
              "latitude": 45.751442,
              "longitude": 4.859827
            }
          ]
        }
      }
    }
  }
}
```
**Context**: Approximate region using polygonal area (closed shape with 3-15 boundary points). The polygon is automatically closed (last point connects to first point).
- **Use case**: Location verification within an irregular polygonal area, compatible with [CAMARA Device Location Retrieval API](https://github.com/camaraproject/DeviceLocation) polygon format. Useful for defining complex geographic boundaries that cannot be accurately represented by circles.

#### 7. Approximated Location Example (Polygon - Rectangle)
```json
{
  "grc.geolocation": {
    "physical-location": {
      "format": "approximated",
      "approximated": {
        "polygon": {
          "boundary": [
            {
              "latitude": 37.8,
              "longitude": -122.5
            },
            {
              "latitude": 37.8,
              "longitude": -122.3
            },
            {
              "latitude": 37.7,
              "longitude": -122.3
            },
            {
              "latitude": 37.7,
              "longitude": -122.5
            }
          ]
        }
      }
    }
  }
}
```
**Context**: Rectangular region represented as a 4-point polygon (northwest, northeast, southeast, southwest corners). Rectangles can be represented using polygon format instead of a separate bounding-box format.
- **Use case**: Privacy-preserving location verification for rectangular areas (e.g., confirming within a metropolitan area without exposing precise coordinates)

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

## 🛡️ Appendix: Open Policy Agent (OPA) Geo-Hardware Binding Example

This example demonstrates how OPA enforces a highly secure policy: Access is only granted if the device's **attested location** is within an approved **trusted zone** AND the device's unique **TPM Endorsement Key (EK)** is authorized to operate in that *exact same zone*.

### 1\. 📂 Policy Data (`data.json`) - The Trusted Reference

This data maps specific geographic boundaries (`bounding_box`) to the full **TPM EK Public Key strings** that are approved for operation within that region.

```json
{
  "compliance_baselines": {
    "trusted_ek_zones": [
      {
        "zone_name": "DC_NORTH_AMERICA_1",
        "bounding_box": { "north": 40.0, "south": 30.0, "east": -70.0, "west": -100.0 },
        "allowed_eks": [
          "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyYt...",  /* Full EK Public Key 1 */
          "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE7p9D..."           /* Full EK Public Key 2 */
        ]
      },
      {
        "zone_name": "DC_EUROPE_2",
        "bounding_box": { "north": 55.0, "south": 45.0, "east": 15.0, "west": -5.0 },
        "allowed_eks": [
          "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAaXv..."   /* Full EK Public Key 3 */
        ]
      }
    ],
    "trusted_tpm_policy": "secure-boot-baseline-2024"
  }
}
```

### 2\. 📜 OPA Rego Policy (`geofence_tpm_map.rego`) - The Logic

This policy uses the `some` keyword to iterate over the `trusted_ek_zones`. The rule succeeds only if a **single zone** satisfies **all 4 binding conditions** (Location latitude/longitude Check, Hardware Check, and Nonce Check).

```rego
package authz.geofence_tpm_map

default allow = false

# Rule: is_trusted_location_and_hardware
# This helper rule acts as a function, returning true if ANY trusted_zone satisfies ALL criteria.
is_trusted_location_and_hardware if {
    # 1. Extract Attested Claims from the input JWT (runtime request data)
    client_lat := input.jwt_claims.grc_geolocation["physical-location"].precise.latitude
    client_lon := input.jwt_claims.grc_geolocation["physical-location"].precise.longitude
    # MODIFICATION: We extract the full EK Public Key string for direct string comparison
    attested_ek_key := input.jwt_claims.grc_tpm_attestation["ek-public"]
    
    # 2. Outer Loop: Iterate over all trusted zones. The rule restarts for each zone until success.
    some trusted_zone in data.compliance_baselines.trusted_ek_zones

    # 3. Location Check (Implicit AND): Must be inside the CURRENT zone's bounding box
    boundary := trusted_zone.bounding_box
    
    # Latitude containment
    client_lat <= boundary.north
    client_lat >= boundary.south
    
    # Longitude containment
    client_lon <= boundary.east
    client_lon >= boundary.west
    
    # 4. Hardware Check (Implicit AND): Must be on the CURRENT zone's allowed EKs list
    # The 'some' here searches the CURRENT zone's list for a matching EK public key string.
    some allowed_ek in trusted_zone.allowed_eks
    attested_ek_key == allowed_ek
    
    # 5. Freshness Check (Implicit AND): The nonce must be present
    input.jwt_claims["rat-nonce"]
}

# --- MOCK FUNCTION DEFINITION ---
# NOTE: This function represents an external Go/Wasm plugin or custom OPA built-in.
# It takes all relevant inputs and performs the cryptographic comparison.
# This logic CANNOT be done purely in native Rego.
# Signature: verify_pcr_binding(raw_location_claim, rat_nonce, quote, expected_pcr_index)
verify_pcr_binding(raw_claims, nonce, quote, pcr_index) if {
    # In a real system, this calls out to a dedicated service:
    # 1. Service parses 'quote' and extracts PCR[pcr_index].
    # 2. Service calculates Hash(raw_claims + nonce).
    # 3. Service returns TRUE if the calculated hash matches the PCR value.
    
    # MOCK implementation: Always returns true if all inputs are present.
    raw_claims
    nonce
    quote
    pcr_index
    true
}

# --- New Helper Rule: Check if Location is Cryptographically Bound ---
is_geolocation_attested if {
    # 1. Identify which PCR index holds the location evidence from Policy Data
    location_pcr := data.compliance_baselines.geolocation_pcr_index
    
    # 2. Gather all inputs needed for the cryptographic binding check
    raw_location_data := input.jwt_claims.grc_geolocation["physical-location"]
    attestation_nonce := input.jwt_claims["rat-nonce"]
    tpm_quote_evidence := input.jwt_claims.grc_tpm_attestation["tpm-quote"]
    
    # 3. Call the external service/mock to perform the cryptographic verification
    verify_pcr_binding(raw_location_data, attestation_nonce, tpm_quote_evidence, location_pcr)
}

# Final Access Rule
allow if {
    is_trusted_location_and_hardware
    is_geolocation_attested
}
```
## Appendix: Attested Geolocation with TPM-Bound Geolocation
- **Keylime supports dynamic quotes at runtime.**
  - Keylime is fundamentally designed for continuous attestation and runtime integrity monitoring, meaning it must frequently request fresh TPM Quotes from the agent node.
  - **Runtime Attestation:** Keylime does not stop after the initial boot check (measured boot). It relies on the Linux Integrity Measurement Architecture (IMA) to continuously monitor file integrity at runtime. When the Keylime Verifier requests a quote from the agent, the agent interacts with the TPM to generate a new quote over the PCRs, which includes the aggregated measurement of the kernel and running processes.
  - **Agent API:** The Keylime Agent exposes a REST API endpoint (e.g., `GET /v2.1/quotes/integrity`) specifically designed to fulfill requests from the Verifier. Each time this API is called, the agent instructs the local TPM to execute the `TPM_Quote` command, producing a fresh, cryptographically signed snapshot of the current PCR values. This process is inherently dynamic.
- **How to add dynamic geolocation.**
  - **Reserve a dynamic PCR:** Select a Platform Configuration Register (PCR) not used by the boot process (typically PCR 17 or 18).
  - **Extend the agent workload:** Deploy a custom extension or script (delivered via Keylime's Secure Payload mechanism) on the agent node that:
    - Retrieves current GPS/geolocation data along with a nonce and timestamp.
    - Hashes this composite data.
    - Executes the TPM command `tpm2_pcrextend` to extend the reserved PCR with the new measurement.
  - **Generate a quote:** When the Keylime Verifier requests a quote, the attestation includes the extended value of the reserved PCR, proving the geolocation data (and nonce) were measured into the secure hardware at the time of attestation.
  - **OPA policy validation:** Downstream OPA policy evaluation can now verify both the current software state and the attested location before allowing access.
