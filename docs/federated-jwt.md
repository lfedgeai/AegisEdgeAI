## ✨ High-Assurance Federated Authorization Models

The challenge is to securely convey **HW-rooted TPM attestation** and **Attested Geographic location** from the Enterprise workload to the Service Provider's (SP) policy engine in a robust **Federated Identity** architecture.

### 🏛️ Model 1: Single Identity JWT with all claims

This model embeds *all* claims—identity, role, and hardware assurance—into a single, comprehensive, and fully **signed JWT**.

#### 🔑 Security Claims and Sourcing
| Claim Type | Location | Assurance Level | Source & Signing Authority |
| :--- | :--- | :--- | :--- |
| **Identity & Role** | JWT Payload | High | Enterprise IDP |
| **TPM Attestation** | **JWT Payload** | **Highest (HW-Rooted)** | Enterprise-Trusted Attestation Service |
| **Attested Geolocation** | **JWT Payload** | **Highest (HW-Rooted)** | Enterprise-Trusted Attestation Service |

#### Flow and Trade-Offs
1.  **Flow:** The Enterprise IDP gathers all claims and issues a single, signed JWT. The SP performs **one signature verification** (using the IDP's public key) and trusts everything inside the token. 
2.  **PRO:** **Unquestionable Integrity.** The single signature guarantees the authenticity and non-tampering of *all* authorization data, simplifying SP validation.
3.  **CON:** **Low Agility.** The token's Time-to-Live (TTL) must be extremely short (e.g., minutes) to ensure the TPM/Geo data is current, leading to **high-overhead, frequent token re-issuance** requests.

### 🛡️ Model 2: Identity JWT + New Claims in a signed JWT within a HTTP header

This model separates stable identity claims from dynamic assurance claims, placing the latter in a dynamically generated, **signed  JWT** within a HTTP header.

#### 🛡️ Security Claims and Sourcing
| Claim Type | Location | Assurance Level | Source & Integrity Mechanism |
| :--- | :--- | :--- | :--- |
| **Identity & Role** | **JWT Payload** | High | Enterprise IDP (Signed) |
| **TPM/Geo Claims** | **Nested JWT** in **HTTP Header** | **Highest** (Signed) | Enterprise/Device-Signed Token |

#### Flow and Trade-Offs
1.  **Flow:** The Enterprise client generates and signs the Nested JWT for the latest TPM/Geo data. The SP verifies **two signatures** - one for the Identity JWT (IDP key) and one for the HTTP header JWT (device key). 
2.  **PRO:** **Highest Flexibility.** Claims can be updated instantly by the device (per request) without refreshing the Identity JWT, maximizing agility and performance.
3.  **CON (General):** **Maximum Complexity.** Requires a sophisticated client and a complex Service Provider infrastructure to manage and verify a large set of ephemeral device signing keys.

### Model 3: New Claims with a short-lived X.509 Certificate (SVID)
This model replaces the JWT for the primary identity and role claims with a short-lived X.509 Certificate (SVID), issued to the workload. The assurance claims (TPM/Geo) are then anchored to the certificate.

### 🎯 Strategic Conclusion: The Ownership Factor

The optimal authorization model hinges entirely on the ownership and trust relationship between the Enterprise workload and the Service Provider (SP) application.

Deployment Context,Key Challenge,Recommended Model,Rationale
B2B (SP is external),Trust & Complexity: Difficulty in establishing a shared PKI for device-specific keys across organizations.,Model 1,Relies on the simplest trust anchor (the established Enterprise IDP signature) and is the most easily consumed by an external Service Provider.
Internal (SP is Enterprise app),"Performance & Agility: Overcoming the high-overhead, low-agility bottleneck of Model 1.",Model 2 (Transitional),Solves the agility problem immediately by delegating dynamic claims to the device without requiring a full Workload Identity System deployment.
Internal (SP is Enterprise app),"Highest Security & Scalability: Achieving HW-rooted identity, automated renewal, and mutual authentication.",Model 3 (Gold Standard),"Since the Enterprise owns the entire stack, the operational complexity is an acceptable investment to achieve the highest level of assurance, agility, and security via SVIDs and mTLS."


