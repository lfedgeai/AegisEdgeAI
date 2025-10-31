## ✨ High-Assurance Federated Authorization Models

The challenge is to securely convey **HW-rooted TPM attestation** and **Attested Geographic location** from the Enterprise workload to the Service Provider's (SP) policy engine in a robust **Federated Identity** architecture.

### 🏛️ Model 1: JWT-Only Claims (Maximum Cryptographic Assurance)

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

### 🛡️ Model 2: Hybrid Claims with Nested Signature (Maximum Agility & Integrity)

This model separates stable identity claims from dynamic assurance claims, placing the latter in a dynamically generated, **signed Nested JWT** within an HTTP header.

#### 🛡️ Security Claims and Sourcing
| Claim Type | Location | Assurance Level | Source & Integrity Mechanism |
| :--- | :--- | :--- | :--- |
| **Identity & Role** | **JWT Payload** | High | Enterprise IDP (Signed) |
| **TPM/Geo Claims** | **Nested JWT** in **HTTP Header** | **Highest** (Signed) | Enterprise/Device-Signed Token |

#### Flow and Trade-Offs
1.  **Flow:** The Enterprise client generates and signs the Nested JWT for the latest TPM/Geo data. The SP verifies **two signatures**—one for the Identity JWT (IDP key) and one for the Nested JWT (device key). 
2.  **PRO:** **Highest Flexibility.** Claims can be updated instantly by the device (per request) without refreshing the Identity JWT, maximizing agility and performance.
3.  **CON (General):** **Maximum Complexity.** Requires a sophisticated client and a complex Service Provider infrastructure to manage and verify a large set of ephemeral device signing keys.

### 🎯 Strategic Conclusion: The Ownership Factor

The critical differentiator for selecting the optimal model lies in the ownership of the application (the Service Provider):

| Deployment Context | Key Challenge | Recommended Model | Rationale |
| :--- | :--- | :--- | :--- |
| **B2B (SP is external)** | Complexity of managing device keys across organizational boundaries (PKI). | **Model 1** (Tolerate high latency for simplicity and high integrity). | External organizations may struggle to exchange and trust device-specific keys securely and reliably. |
| **Internal (SP is Enterprise app)** | High-latency token refreshes (Model 1 CON). | **Model 2** (The best balance). | Since the **Enterprise owns the device, the IDP, and the SP application**, the necessary **PKI and key lookup** is entirely controlled internally, significantly reducing the complexity of Model 2 and making its agility benefits attainable. |

In the specific context of an Enterprise leveraging its own hardware and applications (like Edge AI), **Model 2 is the clear long-term solution** for achieving both real-time authorization and cryptographic integrity.
