# AegisSovereignAI: Trusted AI for the Distributed Enterprise

**AegisSovereignAI** is the **Trust Integration Layer** for the Linux Foundation AI ecosystem. It delivers verifiable trust for AI workloads across the **distributed enterprise**—unifying open standards from the CNCF (SPIFFE/Keylime/OPA) and IETF (RATS/WIMSE) into a contiguous **Chain of Trust** from Silicon to Prompt.

We don't just integrate with AI frameworks; we actively harden them. As the authors of the **Zero-Trust Governance Middleware** proposal for **LangChain**, we are driving security standards directly into the tools developers use daily.

While frameworks like **OPEA** define *how* to build Enterprise AI, and **AAIF** defines *how* agents communicate (MCP), **AegisSovereignAI** defines *how* to trust them. We bridge the gap between **Centralized Clouds** and the **Far Edge**, providing cryptographic proof that your AI agents are running on verified hardware, in authorized jurisdictions, and acting within sovereign policy limits—regardless of where they physically sit.

<p align="center">
  <img src="images/readme-arch.svg" alt="AegisSovereignAI 3-Layer Trust Model" width="800">
</p>

## The Trusted AI Stack
AegisSovereignAI addresses the three critical layers required to unlock regulated markets across a distributed fleet:

### 1. Infrastructure Security (The Foundation)
* **Hardware Supply Chain:** We utilize **TPM Endorsement Keys (EK)** and **BMC-based Inventory Attestation** to detect component swapping or firmware downgrades before the OS even boots.
* **Runtime Integrity ("Self-Healing Trust"):** We simplify security operations by binding **Keylime** (IMA/EVM) integrity checks directly to the **SPIRE Agent's** periodic re-attestation loop.
    * **The Mechanism:** The Agent must prove its binary integrity (via TPM Quote) every renewal cycle.
    * **The Result:** If the `spire-agent` or `kubelet` binaries are tampered with, the Server denies the renewal. The compromised node is naturally cut off from the mesh, requiring no manual "Kill Switch" infrastructure.

### 2. Workload Identity (The Bridge)
* **Proof of Residency (PoR):** We issue cryptographic certificates that bind the **Workload Identity** (executable hash) to the **Hardware Identity** (TPM). This replaces weak bearer tokens with hardware-rooted proof of possession.
* **Proof of Geofencing (PoG):** We extend PoR to include **Location Identity** (GNSS/Mobile Sensors), ensuring data sovereignty by preventing AI agents from running in disallowed jurisdictions.

### 3. AI Governance & Compliance (The New Layer)
* **Zero-Trust Data Filtering:** Middleware that enforces **OPA (Open Policy Agent)** rules on RAG retrieval contexts.
* **Immutable Audit Logs:** Generation of compliance artifacts that capture the "Immutable Triad" (User Input + Context Hash + Model Config), turning "trust" into a mathematically verifiable feature.

## Why It Matters
* **Unified Control Plane:** Eliminate security silos. Apply a single, rigorous trust policy that spans your Multi-Cloud, On-Premise Data Centers, and Edge locations.
* **Unlock Regulated Markets:** Meet strict data sovereignty and integrity requirements with verifiable proof that spans user, device, and workload.
* **Reduce Audit Friction:** Provide clear, end-to-end evidence that identity pillars are authentic.
* **Turn Trust into a Feature:** Make holistic, hardware-rooted trust a customer-visible advantage.

## Built on Open Standards
AegisSovereignAI does not reinvent the wheel. Instead, we act as the unifying control plane that cryptographically binds best-in-class open-source projects into a cohesive trust fabric.

* **[SPIFFE/SPIRE](https://spiffe.io) (CNCF):** The industry standard for **Workload Identity**. We use SPIRE to issue short-lived, verifiable X.509 certificates that replace static API keys.
* **[Keylime](https://keylime.dev) (CNCF):** The standard for **Remote Attestation**. We use Keylime to validate TPM quotes and Linux Kernel integrity (IMA) in real-time.
* **[Open Policy Agent (OPA)](https://www.openpolicyagent.org) (CNCF):** The standard for **Policy-as-Code**. We use OPA to make granular "Allow/Deny" decisions on RAG data retrieval.
* **[LangChain](https://www.langchain.com):** The leading framework for **LLM Orchestration**. Our governance middleware is designed as a drop-in LangChain component.

## Contributions
We actively contribute to open standards and upstream projects to harden the global AI supply chain.

* **[IETF Draft: Verifiable Geofencing & Unified Identity](https://datatracker.ietf.org/doc/draft-lkspa-wimse-verifiable-geo-fence/)**
    * **Status:** Active Internet-Draft (IETF WIMSE/RATS Working Group)
    * **Scope:** Defines the protocol for cryptographically binding a **Workload Identity** (SPIFFE) to its **Physical Location** and **Hardware Identity** (TPM).
    * **Implementation:** The open-source reference implementation for this standard is available in our **[Hybrid Cloud PoC](hybrid-cloud-poc)**.

* **[LangChain Proposal: Zero-Trust Governance Middleware](proposals/rag-governance.md)**
    * **Status:** Draft / RFC (Submitted to LangChain Community)
    * **Scope:** Standardizing **Policy-as-Code** and **Verifiable Audit Logs** for Enterprise RAG systems. This proposal solves "Context Contamination" by cryptographically binding the retrieved context to the model decision.

## Stakeholders
* **Ramki Krishnan (Vishanti Systems)** (Project Lead / Maintainer)
* Andreas Spanner (Red Hat)
* Michael Epley (Red Hat)
* A. Prasad (Oracle)
* Srini Addepalli (Aryaka)
* Vijaya Prakash Masilamani (Independent)
* Bala Siva Sai Akhil Malepati (Independent)
* Dhanush (Vishanti Systems)
* Pranav Kirtani (Independent)

## Problem Statement: The Distributed Trust Gap

In a modern distributed enterprise, inference happens everywhere—from secure cloud data centers to branch offices and tactical edge servers. This sprawl creates **fragmented security models** where the "Cloud" is secure (IAM), but the "Edge" is exposed (Physical Access). This inconsistency creates amplification points for emerging **Multi-Agent** threats.

### A. Infrastructure Threats
1.  **Token Replay & Identity Abuse:** Bearer tokens (RFC 6750) can be stolen and replayed. Even "Cloud Identity" is vulnerable if the underlying host is compromised.
2.  **Weak Location Assurance:** IP-based geofencing is easily bypassed via VPNs. AI agents inheriting false location claims can trigger compliance violations.
3.  **Physical Exposure:** Edge nodes in semi-trusted environments (factories, retail) are vulnerable to physical tampering and hardware substitution.

### B. Application & Governance Threats
1.  **Data Provenance Gaps:** In distributed RAG pipelines, there is no cryptographic link between *what* was measured and *who* measured it. Poisoned data can corrupt decision pipelines without detection.
2.  **MCP Protocol Risks:** In the Model Context Protocol (MCP), "confused deputy" attacks can allow agents to access resources beyond their scope. Unverified MCP servers can inject malicious tools or exfiltrate data.
3.  **Model Placement Risks:**
    * *Local Placement:* Host compromise grants control over both the orchestration logic and the model weights (IP theft).
    * *Remote Placement:* Weak endpoint verification allows "Man-in-the-Middle" attacks on inference requests.

## Core Solution Architecture

### 1. Unified Workload Identity
We extend the standard software identity (SPIFFE) by cryptographically binding it to the physical reality of the device. This creates a "Unified ID" that serves as the root of trust for all three critical security assertions:

* **A. Proof of Residency (PoR)**
    * **Challenge:** Weak bearer tokens in exposed environments allow identity theft and replay attacks.
    * **Solution:** We bind **Workload Identity** (Code Hash) + **Host Hardware Identity** (TPM PKI) + **Platform Policy** (Kernel Version). This generates a certificate that proves *what* is running and *where* it is running.

* **B. Proof of Geofencing (PoG)**
    * **Challenge:** Unreliable IP-based location checks are easily bypassed via VPNs.
    * **Solution:** We extend PoR to include **Location Hardware Identity** (GNSS/Mobile Sensors). This enables verifiable enforcement of geographic policy at the workload level, ensuring data sovereignty even on the far edge.

* **C. Supply Chain Security**
    * **Challenge:** Counterfeit hardware and firmware downgrades in physical deployments.
    * **Solution:** We enforce a layered hardware gate:
        * *Enrollment:* Restricted to manufacturer-issued **TPM Endorsement Keys (EK)**.
        * *Inventory:* Out-of-band verification of components (NICs, GPUs) against purchase orders via BMC.

### 2. Zero-Trust RAG Governance
Security does not stop at identity; it must extend to the data the AI consumes.

* **Challenge:** "Context Contamination" and the "GenAI Audit Paradox." In RAG systems, malicious actors can inject poisoned data into the retrieval pipeline, and standard logs cannot prove *why* a model made a specific decision.
* **Solution:** We introduce a **Policy Enforcement Point (PEP)** middleware that sits between the vector database and the LLM.
    * *Pre-Computation:* It enforces **OPA (Open Policy Agent)** rules to filter retrieved context before the model sees it.
    * *Post-Computation:* It generates an immutable audit log that cryptographically binds the **User Prompt** + **Retrieved Context Hash** + **Model Response**.

## Additional Resources
* **Zero‑Trust Sovereign AI Deck:** [View Deck](https://1drv.ms/b/c/746ada9dc9ba7cb7/ETTLFqSUV3pCsIWiD4zMDt0BXzSwcCMGX8cA-qllKfmYvw?e=ONrjf1)
* **IETF Presentations:**
    * IETF 123 WIMSE: [View Slides](https://datatracker.ietf.org/meeting/123/materials/slides-123-wimse-zero-trust-sovereign-ai-wimse-impact-04)
    * IETF 123 RATS: [View Slides](https://datatracker.ietf.org/meeting/123/materials/slides-123-rats-zero-trust-sovereign-ai-rats-impact-00)

## References
1.  [Simply NUC: Banks Data Closer to Customers](https://simplynuc.com/blog/banks-data-closer-to-customers/)
2.  [Keylime Documentation](https://keylime.readthedocs.io/en/latest/)
3.  [SPIFFE/SPIRE Documentation](https://spiffe.io/docs/)