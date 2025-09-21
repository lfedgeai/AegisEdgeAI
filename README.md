# "AegisEdgeAI" - Securing AI at the Edge

**AegisEdgeAI** delivers verifiable trust for AI at the edge — from manufacturing to live operations — ensuring workloads run only on approved, uncompromised devices, in approved locations. Where typical models verify the user, the device, or the workload in isolation, AegisEdgeAI cryptographically binds all three identities together. This continuous chain of identity, integrity, and location assurance closes supply‑chain and provenance gaps, streamlines audits, and turns compliance proof into a market differentiator. **In short: AegisEdgeAI makes it impossible for an AI workload to run on the wrong machine, in the wrong location, or in a compromised state — and cryptographically proves it.**

## Binding user, device, and workload identities from manufacture through runtime with geofencing enforcement
![Alt text](zero-trust/images/AegisEdgeAI-flow.png)

## Why it matters

- **Unlock regulated markets** – Meet location and integrity compliance requirements with verifiable, automated proof that spans user, device, and workload.

- **Reduce audit friction** – Provide clear, end‑to‑end evidence that all three identity pillars are authentic and uncompromised.

- **Turn trust into a feature** – Make holistic, hardware‑rooted trust a customer‑visible advantage.

## Stakeholders

- [Ramki Krishnan](https://lf-edge.atlassian.net/wiki/people/557058:c8c42130-9c8b-41ae-b9e2-058af2eff879?ref=confluence) (Independent) (Lead)
- [Andreas Spanner](https://lf-edge.atlassian.net/wiki/people/59fc56048499730e3412487a?ref=confluence) (Red Hat)
- Michael Epley (Red Hat)
- A. Prasad (Oracle)
- Srini Addepalli (Aryaka)
- [Vijaya Prakash Masilamani](https://lf-edge.atlassian.net/wiki/people/712020:4ffd801f-be21-429e-b9b8-d8cc749364a9?ref=confluence) (Fidelity)
- [Bala Siva Sai Akhil Malepati](https://github.com/saiakhil2012) (Independent)
- [Pranav Kirtani](https://github.com/pranavkirtani) (Independent) 
- [Clyde D'Cruz](https://github.com/clydedacruz) (Independent)
  
## Problem Statement - Common Threats

Current security approaches for inference applications, secret stores, system agents, AI agents, and model repositories face **critical gaps** — gaps amplified in **edge AI** deployments and further complicated by emerging **multi‑agent** and **Model Context Protocol (MCP)** interoperability patterns. These challenges — documented in the [IETF Verifiable Geofencing draft](https://github.com/nedmsmith/draft-klspa-wimse-verifiable-geo-fence/blob/main/draft-lkspa-wimse-verifiable-geo-fence.md), and summarize below, which outlines broad use cases and deployment patterns, including edge computing — are summarized below.

### Token Replay and Identity Abuse

- **Bearer tokens** ([RFC 6750]) safeguard resources but can be replayed if stolen — e.g., via compromise of an identity provider (Okta) or a metadata server (Kubernetes bootstrap token, Spiffe/Spire bootstrap token).

- **Proof‑of‑Possession (PoP) tokens** ([RFC 7800]) bind a token to a private key, reducing replay risk, but remain vulnerable to **account manipulation** (MITRE T1098), enabling:
  - Execution of **invalid workload versions**
  - Execution of **valid workloads** on disallowed hosts or in disallowed regions

- In **AI agent ecosystems**, stolen or manipulated credentials can allow an agent to impersonate another, invoke sensitive tools, or exfiltrate data — especially dangerous when agents operate autonomously or in chained workflows.

### Weak Location Assurance

- **IP‑based geofencing** (firewall rules based on source IP) provides only weak location assurances — easily bypassed via VPNs, proxies, or IP spoofing.

- **AI agents** coordinating across sites via MCP or other protocols may inherit false location claims from compromised peers, propagating bad data or triggering actions in restricted jurisdictions.

### Data Provenance Gaps

- No cryptographically verifiable link between **measurement location**, **device identity**, and **collected data**.

- In **federated learning** or **multi‑agent inference**, poisoned or replayed data from an unverified source can corrupt models or decision pipelines without detection.

### MCP Protocol–Specific Risks

- **Token passthrough** and **mis‑scoped permissions** can let a compromised MCP server act as a "confused deputy," granting agents access to resources beyond their intended scope.

- **Unverified MCP servers** or weak authentication between MCP clients and servers can allow malicious endpoints to inject tools, alter context, or exfiltrate sensitive data.

- **Consent fatigue** and **runtime environment weaknesses** (e.g., insufficient sandboxing) increase the risk of privilege creep and lateral movement in multi‑agent systems.

### Why These Gaps Are Critical for Edge AI Deployments?

1. **Physical Exposure of Trust Anchors** Edge nodes — and the AI agents/system agents running on them — often live in uncontrolled or semi‑trusted environments (factory floors, roadside cabinets, retail stores, customer premises).
   - Local theft of bearer/PoP/MCP credentials bypasses the "secure perimeter" assumptions of cloud IAM.

2. **Weaker Identity Provider Perimeter** In cloud, IdP and metadata services are behind hardened control planes. At the edge, bootstrap and MCP discovery flows may traverse untrusted networks or run on devices without HSM‑grade protection, making token replay or key theft more feasible.

3. **Policy Enforcement Drift** Cloud workloads run in tightly controlled regions with enforced placement policies. Edge workloads — including autonomous AI agents — can be silently relocated or cloned to disallowed geos/hosts if attestation, **Proof of Residency (PoR)** / **Proof of Geofencing (PoG)**, and geofencing aren't cryptographically enforced.

4. **Location Spoofing Risk** IP‑based controls are brittle at the edge. Without hardware‑rooted location proofs, AI agents can be tricked into acting on falsified geolocation data, undermining compliance and safety.

5. **Data Provenance Blind Spots** Edge sensors, inference agents, and MCP‑mediated tool calls generate high‑value data for regulatory or safety‑critical decisions. Without binding *what* was measured to *where* and *by which attested agent/device*, compliance and tamper detection are impossible.

## Problem Statement - AI Model Placement‑Driven Threats

### Local Model Placement

*(Model and agent co‑located within the same process, device, or trusted compute base)*

- **Single trust‑anchor exposure** Host compromise hands an attacker control over both orchestration logic and model runtime — maximising blast radius.

- **Unified compromise path** Malicious code, model‑weight swaps, or data‑flow manipulation require no network breach — they happen inside one trust zone.

- **Intellectual property / model theft** Proprietary weights, architectures, and pipelines can be exfiltrated for offline cloning or adversarial reverse‑engineering.

- **Silent functional drift** An adversary can replace the model with a poisoned variant that behaves acceptably under casual testing but embeds malicious logic or bias.

- **Integrity scope ambiguity** Without enforced measurement boundaries, stakeholders cannot be sure both control and inference components remain unaltered after restart or update.

### Remote Model Placement

*(Model hosted in cloud or edge‑cluster; agent interacts via network calls)*

- **Network trust dependency** Transport weaknesses allow interception, replay, or redirection of inference requests/responses.

- **Jurisdictional exposure** Absent location‑bound session identity, models can be invoked from disallowed geographies, breaching compliance or contractual residency terms.

- **In‑flight output manipulation** Even structured outputs can be altered en route, producing unsafe or misleading downstream actions.

- **Endpoint impersonation / model substitution** Weak endpoint verification allows redirection to compromised or malicious model services.

- **Prompt / input tampering at a distance** For LLMs (and other models sensitive to crafted inputs), unprotected transit can permit injection or alteration that changes downstream system behavior.

### Why These Challenges Are **Critical** in Edge AI

- **Distributed, physically exposed nodes** Edge deployments lack the hardened perimeters of centralised data centres, making them more susceptible to physical and side‑channel attacks.

- **Jurisdictional and sovereignty constraints** Edge nodes often operate across regulated borders, amplifying the impact of uncontrolled model invocation or data egress.

- **High‑impact real‑time actions** Edge AI frequently drives autonomous or safety‑critical systems — meaning any model compromise directly threatens operations, compliance, or safety.

- **Intermittent connectivity & dynamic topologies** Trust decisions must withstand disconnected operation; this magnifies the consequences of stale or poisoned models.

- **Attack surface diversity** Edge systems integrate heterogeneous hardware, firmware, and software stacks — creating multiple, intersecting vectors for compromise.

## Problem Statement – Hardware and Software Supply Chain

### Hardware Supply Chain Threats

- **Unverified hardware enrollment** — Nodes can be racked with counterfeit or rogue chassis/TPMs if enrollment isn’t bound to manufacturer‑issued TPM Endorsement Keys (EKs). Impact: Compromised trust anchors at the very start of the lifecycle undermine all downstream attestation and geofencing.

- **Component and firmware substitution** — NICs, GPUs, DIMMs, or firmware can be swapped or downgraded between factory and deployment. TPM PCRs may not reflect all FRU changes. Impact: Introduces malicious firmware or side‑channel vectors into heterogeneous edge hardware, bypassing OS‑level controls.

- **Out‑of‑band compromise** — Attackers with physical access can alter hardware inventory without touching the host OS, evading in‑band detection. Impact: Breaks provenance guarantees for AI workloads and telemetry.

### Software Supply Chain Threats

- **Post‑enrollment drift/tampering** — Even on genuine hardware, OS, kernel, or critical binaries can be altered after deployment. Impact: Malicious changes persist undetected without continuous runtime attestation, corrupting AI inference or control loops.

- **Dependency and model repository compromise** — Inference agents or system components may pull from unverified registries or repos. Impact: Injects malicious code or altered models into production without triggering signature mismatches if signing keys are stolen.

### Why These Gaps Are Critical for Edge AI Deployments

- **Physical exposure of trust anchors** — Edge nodes live in uncontrolled environments (factory floors, roadside cabinets, retail stores). Hardware swaps or firmware downgrades can happen without triggering cloud‑style perimeter defenses.

- **Weaker identity provider perimeter** — At the edge, bootstrap and discovery flows may traverse untrusted networks or run without HSM‑grade protection, making key theft and enrollment abuse more feasible.

- **Policy enforcement drift** — Without hardware‑rooted identity and continuous attestation, workloads can be silently relocated or modified, breaking compliance and safety guarantees.

- **Data provenance blind spots** — AI outputs lose regulatory and operational value if the hardware and software state producing them can’t be cryptographically tied to a known‑good baseline.

## Solution Overview

Building on the [IETF Verifiable Geofencing draft](https://datatracker.ietf.org/doc/draft-klspa-wimse-verifiable-geo-fence/) — which defines an architecture for cryptographically verifiable geofencing and residency proofs — this design offers an **edge‑focused, production‑ready microservice blueprint** for secure, verifiable data flows (e.g., operational metrics, federated learning) at the edge.

This approach begins addressing the critical security gaps in current inference, agent, and model‑repository patterns, while remaining open to further extension and innovation.

### 1. Proof of Residency (PoR)

**Challenge addressed:** Weak bearer/proof‑of‑possession token models for system and AI agents in sensitive edge contexts.

**Approach:** Cryptographically bind — rather than rely on convention or configuration — the following elements to issue a PoR workload certificate/token:

- **Workload identity** (e.g., executable code hash)
- **Approved host platform hardware identity** (e.g., TPM PKI key)
- **Platform policy** (e.g., Linux kernel version, measured boot state)

### 2. Proof of Geofencing (PoG)

**Challenge addressed:** Token misuse risks and unreliable Source IP checks for location‑sensitive edge workloads.

**Approach:** Cryptographically bind the PoR attestation above **plus**:

- **Approved host platform location hardware identity** (e.g., GNSS module or mobile sensor hardware/firmware version)

This produces a PoG workload certificate/token, enabling verifiable enforcement of geographic policy at the workload level.

### 3. Addressing Hardware and Software Supply Chain Threats (work in progress)
To mitigate the hardware and software supply chain threats above, AegisEdgeAI adopts a layered trust model that binds device identity, hardware integrity, and runtime state into a continuous attestation chain from manufacturing through operation.

**Hardware Inventory Attestation – BMC Path (Hardware Management Plane)**

- **Approach:** At boot, the server's hardware management plane—anchored by the BMC—collects a signed inventory of components and firmware (NICs, GPUs, DIMMs, BIOS, etc.) via secure, out‑of‑band protocols (e.g., Redfish + Secured Component Verification). This inventory is compared against a purchase‑order‑bound allowlist maintained in the attestation policy service.

- **Effect:** Detects component swaps, firmware downgrades, or unauthorized additions, independently of the host OS state, leveraging the isolated hardware management plane's visibility and integrity.

- **Edge Benefit:** Preserves hardware provenance across heterogeneous, multi‑vendor edge stacks, ensuring trust is established before in‑band software attestation begins.

**Hardware Identity Gate – Remote boot attestation and runtime integrity measurement (Keylime etc.) TPM EK Allowlist**

- **Approach:** Preload manufacturer‑issued TPM Endorsement Key certificates (e.g., Server manufacturer TPM EK certs from the Purchase Order) into the Keylime registrar's allowlist.

- **Effect:** Enrollment is cryptographically tied to known manufacturing batches. Unknown chassis/TPMs are blocked before any attestation begins.

- **Edge Benefit:** Defeats rogue node onboarding in physically exposed, perimeter‑less deployments.

**Runtime Integrity Attestation – Remote boot attestation and runtime integrity measurement (Keylime etc.)**

- **Approach:** Continuous TPM quotes plus IMA/EVM measurement of kernel and file integrity against golden baselines.

- **Effect:** Identifies software drift or tampering post‑enrollment, with automated policy responses (alert, quarantine, rebuild).

- **Edge Benefit:** Sustains runtime trust for AI workloads, ensuring inference and control loops run on verified software stacks.

## Progress

### Edge data collection

A production‑ready prototype microservice design for secure, verifiable data (e.g., operational metrics etc.) collection at the edge.

Details: [README.md](https://github.com/lfedgeai/AegisEdgeAI/tree/main/zero-trust/README.md)

#### Security Highlights

- **Proof of Residency** at the edge → The metrics agent is cryptographically bound to the host platform hardware TPM identity. All the data from the edge metrics agent, including replay protection, is signed by a host TPM resident key which is verified by the collector. The host TPM resident signing key is certified by the host TPM attestation key (AK) which is certified by the host TPM endorsement key (EK). TPM AK is an ephemeral host identity. TPM EK is the permanent host identity.

- **Proof of Geofencing** at the edge → The geographic region is included in the payload from the edge metrics agent and is signed by host TPM. The geographic region verification is done by collector before data is ingested into the system.

#### How to test Prototype?

- Refer [README_demo.md](https://github.com/lfedgeai/AegisEdgeAI/tree/main/zero-trust/README_demo.md)

### TPM tools for macOS - In progress

Details: [README.md](https://github.com/lfedgeai/AegisEdgeAI/tree/main/swtpm-macos/README.md)

## Additional Resources

- **Zero‑Trust Sovereign AI Deck** – Public presentation outlining PoR/PoG architecture, market‑entry cases, and integration flow.  
  [View Deck (OneDrive)](https://1drv.ms/b/c/746ada9dc9ba7cb7/ETTLFqSUV3pCsIWiD4zMDt0BXzSwcCMGX8cA-qllKfmYvw?e=ONrjf1) 

- **Blog: Unlock the Future of Access** – In‑depth article on moving from IP‑based security to hardware‑rooted sovereign Zero Trust, with phased implementation examples.  
  [Read Blog](https://github.com/lfedgeai/AegisEdgeAI/blob/main/blog.md)

- **IETF 123 WIMSE Presentation** – *Zero‑Trust Sovereign AI: WIMSE Impact*  
  [View Slides](https://datatracker.ietf.org/meeting/123/materials/slides-123-wimse-zero-trust-sovereign-ai-wimse-impact-04)

- **IETF 123 RATS Presentation** – *Zero‑Trust Sovereign AI: RATS Impact*  
  [View Slides](https://datatracker.ietf.org/meeting/123/materials/slides-123-rats-zero-trust-sovereign-ai-rats-impact-00)

## References
(1) https://simplynuc.com/blog/banks-data-closer-to-customers/

(2) https://keylime.readthedocs.io/en/latest/

(3) https://github.com/keylime/enhancements/pull/108
