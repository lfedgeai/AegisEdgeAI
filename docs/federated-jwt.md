## High-Assurance Federated Authorization Models

The foundation of this architecture is **Federated Identity** between the **Enterprise IDP** and the **Service Provider (SP)**. The advanced requirement is to securely convey **HW-rooted TPM attestation** and **Attested Geographic location** to the SP's policy engine.

### 🏛️ Model 1: JWT-Only Claims (Maximum Cryptographic Assurance)

This model prioritizes security integrity by embedding *all* claims—identity, role, and hardware assurance—into a single, cryptographically **signed JWT**.

#### 🔑 Security Claims and Sourcing
| Claim Type | Location | Assurance Level | Source & Signing Authority |
| :--- | :--- | :--- | :--- |
| **Identity & Role** | JWT Payload | High | Enterprise IDP |
| **TPM Attestation** | **JWT Payload** | **Highest (HW-Rooted)** | Enterprise-Trusted Attestation Service |
| **Attested Geolocation** | **JWT Payload** | **Highest (HW-Rooted)** | Enterprise-Trusted Attestation Service |

#### Flow Breakdown
1.  **Comprehensive Token Issuance:** The **Enterprise IDP** (or its trusted Security Token Service) authenticates the user, then contacts a **Trusted Attestation Service (TAS)** to gather the current TPM status and attested location for the workload.
2.  **Single Signed Token:** The IDP compiles **all claims** and creates one large **JWT**, which it **signs** with its private key. 
3.  **Simplified SP Enforcement:** The Service Provider receives the token and performs a **single signature verification**. If valid, the SP trusts every claim inside.
4.  **Policy Engine Logic:** The SP's Policy Engine reads and acts directly on the combined claims.

#### Trade-Offs (Model 1)
* **PRO:** **Unquestionable Integrity.** The Enterprise's signature covers the hardware assurance claims, eliminating all risk of tampering after issuance.
* **CON:** **Low Agility.** If the attested claims (e.g., location) change, the **entire JWT is instantly stale**. This necessitates a very short Time-to-Live (TTL) and high-overhead token re-issuance requests, impacting performance.

---

### ⚙️ Model 2: Hybrid Claims (Maximum Operational Agility)

This model separates stable identity claims from dynamic assurance claims, enabling real-time policy updates without constant token refresh.

#### ⚙️ Security Claims and Sourcing
| Claim Type | Location | Assurance Level | Source & Integrity Mechanism |
| :--- | :--- | :--- | :--- |
| **Identity & Role** | **JWT Payload** | High | Enterprise IDP (Cryptographically Signed) |
| **TPM Attestation** | **HTTP Extension Header** | High (Internal) | SP-Internal Trusted Attestation Service |
| **Attested Geolocation** | **HTTP Extension Header** | High (Internal) | SP-Internal Trusted Attestation Service |

#### Flow Breakdown
1.  **Core Token Issuance:** The Enterprise IDP issues a standard JWT containing **only** the stable **Identity and Role** claims. This JWT can have a longer TTL.
2.  **Request Flow:** The user's request, carrying the JWT, enters the Service Provider's network (e.g., **API Gateway**).
3.  **Header Injection (Crucial Step):** The Gateway verifies the JWT, then dynamically fetches the *current, real-time* TPM status and Attested Geolocation from the SP's internal **Trusted Attestation Service**. 
4.  **Injection:** The dynamic values are injected into the request as **HTTP Extension Headers** (e.g., `X-Claim-TPM-Attest: Verified`).
5.  **Policy Engine Logic:** The final application policy engine evaluates the claims from **both sources**. The logic is complex but highly granular:

    $$\text{Access Granted if: } [(\text{JWT.role} = \text{"senior\_dev"}) \land (\text{Header.X-Claim-TPM-Attest} = \text{"Verified"})]$$

#### Trade-Offs (Model 2)
* **PRO:** **High Agility.** Real-time claims can be updated instantly (per request) without requiring JWT re-issuance, improving user experience and system responsiveness.
* **CON:** **Security Complexity.** The SP must enforce a robust **Zero Trust** boundary and use strong internal network security (like Mutual TLS or a trusted service mesh) to prevent an attacker from tampering with the non-signed HTTP headers before they reach the final policy engine.

---

### 🌟 Conclusion

The optimal model depends on the organization's risk profile: **Model 1** provides gold-standard **cryptographic proof** at the cost of operational overhead. **Model 2** provides high **operational agility** and real-time context, requiring the SP to assume full security responsibility for the claims once they are inside its trusted network boundary.

Would you like a detailed **architecture diagram** for one of these models?
