## ✨ High-Assurance Federated Authorization Models

The foundational architecture is **Federated Identity** between the **Enterprise IDP** and the **Service Provider (SP)**. The objective is to securely and reliably convey **HW-rooted TPM attestation** and **Attested Geographic location** for granular policy enforcement.

### 🏛️ Model 1: JWT-Only Claims (Maximum Cryptographic Assurance)

This model prioritizes security integrity by embedding *all* claims—identity, role, and hardware assurance—into a single, cryptographically **signed JWT**.

#### 🔑 Security Claims and Sourcing
| Claim Type | Location | Assurance Level | Source & Signing Authority |
| :--- | :--- | :--- | :--- |
| **Identity & Role** | JWT Payload | High | Enterprise IDP |
| **TPM Attestation** | **JWT Payload** | **Highest (HW-Rooted)** | Enterprise-Trusted Attestation Service |
| **Attested Geolocation** | **JWT Payload** | **Highest (HW-Rooted)** | Enterprise-Trusted Attestation Service |

#### Flow Breakdown
1.  **Comprehensive Token Issuance:** The **Enterprise IDP** authenticates the user, gathers **all claims** (including TPM/Geo from the TAS), compiles them, and creates one large, single **JWT**. 
2.  **Single Signature:** The IDP **signs** the entire JWT with its private key.
3.  **Simplified SP Enforcement:** The Service Provider performs a **single signature verification** using the Enterprise's public key. If valid, the SP trusts every claim inside.

#### Trade-Offs (Model 1)
* **PRO:** **Unquestionable Integrity.** The single signature guarantees the authenticity and non-tampering of *all* authorization data.
* **CON:** **Low Agility.** The token's Time-to-Live (TTL) must be very short to reflect real-time changes in TPM or location, causing frequent, high-overhead token re-issuance requests.

### 🛡️ Model 2: Hybrid Claims with Nested Signature (Maximum Agility & Integrity)

This model offers the best of both worlds: high operational agility using dynamic HTTP headers, combined with high integrity using a **nested signature** on the real-time claims.

#### 🛡️ Security Claims and Sourcing
| Claim Type | Location | Assurance Level | Source & Integrity Mechanism |
| :--- | :--- | :--- | :--- |
| **Identity & Role** | **JWT Payload** | High | Enterprise IDP (Signed) |
| **TPM/Geo Claims** | **Nested JWT** in **HTTP Header** | **Highest** (Signed) | Enterprise/Device-Signed Token |

#### Flow Breakdown
1.  **Core Token Issuance:** The Enterprise IDP issues a stable, longer-lived JWT containing **only** the stable **Identity and Role** claims.
2.  **Dynamic Claim Generation:** The Enterprise client/workload dynamically generates a small, independent **Nested JWT** containing the latest TPM and Geo claims, which it signs with a **device-specific key**.
3.  **Request Flow:** The Enterprise client sends the **Identity JWT** in the standard `Authorization` header and the **Nested JWT** as an **HTTP Extension Header** (e.g., `X-Claim-Attest`).
4.  **Verification (Split and Decoupled):**
    * The **SP API Gateway** verifies the signature of the **Identity JWT**.
    * The **SP Policy Engine** extracts the **Nested JWT** from the header and verifies its signature using the **device's public key** (obtained via a secure key lookup). 
5.  **Policy Engine Logic:** The policy engine uses the combination of stable claims from the Identity JWT and the verified real-time claims from the Nested JWT.

#### Trade-Offs (Model 2)
* **PRO:** **Highest Flexibility.** Claims can be updated instantly (per request) by the device, maintaining high operational agility without requiring a full token re-issue.
* **CON:** **Maximum Complexity.** Requires sophisticated client-side logic (to generate the nested signed token) and a complex infrastructure on the SP side (to manage and verify device signing keys).
