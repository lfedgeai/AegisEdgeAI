# Upstream Community Engagement Guide

**AegisSovereignAI** (LF Edge/AI Project)

This document outlines the sequential steps for introducing the Unified Identity feature to upstream communities.

---

## Phase 1: SPIRE Community (Week 1-2)

### Step 1.1: Join SPIFFE Slack
- **Link:** https://slack.spiffe.io/
- **Channel:** `#spire-dev`

### Step 1.2: Post Introduction Message

> **Subject: [RFC] Hardware Attestation Claims in X.509 SVIDs via Keylime Integration**
>
> Hi SPIRE community! 👋
>
> We're from the **AegisSovereignAI** project under LF Edge/AI. We've developed a CredentialComposer plugin that extends X.509 SVIDs with hardware attestation claims from Keylime TPM verification.
>
> **What we built:**
> - A `unifiedidentity` CredentialComposer plugin that adds an AttestedClaims X.509 extension (OID `1.3.6.1.4.1.55744.1.1`)
> - TPM "App Key" support - workload-specific keys certified by Keylime's Attestation Key
> - Geolocation claims bound to TPM PCR-15
>
> **Use Case: Sovereign Banking AI Inference**
> A European bank runs AI inference on edge devices across multiple jurisdictions. Regulatory compliance (GDPR, PSD2) requires cryptographic proof that:
> 1. The workload is running on verified, untampered hardware (TPM attestation)
> 2. The data never leaves the specified geofence (location proofs in SVID)
> 3. Access to customer keys is bound to hardware identity, not just bearer tokens
>
> Our solution replaces fragile IP-based geofencing with hardware-rooted "Proof of Residency" embedded directly in X.509 SVIDs.
>
> **Reference:** [Hybrid Cloud PoC README](https://github.com/lfedgeai/AegisSovereignAI/tree/main/hybrid-cloud-poc#the-problem) - see "The Problem" and "The Solution" sections
>
> **Resources:**
> - Repository: https://github.com/lfedgeai/AegisSovereignAI/tree/main/hybrid-cloud-poc
> - Architecture: https://github.com/lfedgeai/AegisSovereignAI/blob/main/hybrid-cloud-poc/README-arch-sovereign-unified-identity.md
> - Roadmap: https://github.com/lfedgeai/AegisSovereignAI/blob/main/hybrid-cloud-poc/UPSTREAM_MERGE_ROADMAP.md
>
> We'd love to discuss upstreaming this as a formal SPIRE plugin. Would there be interest in a community meeting presentation?
>
> Thanks!


### Step 1.3: Request Community Meeting Slot
- **Meeting Schedule:** Bi-weekly (check SPIFFE calendar)
- **Request via:** Slack or GitHub Discussion

### Step 1.4: Submit GitHub Discussion/RFC
- **Location:** https://github.com/spiffe/spire/discussions
- **Type:** RFC for CredentialComposer plugin extension

---

## Phase 2: Keylime Community (Week 2-3)

### Step 2.1: Join Keylime Slack
- **Link:** https://cloud-native.slack.com/
- **Channel:** `#keylime`

### Step 2.2: Post Introduction Message

> **Subject: [RFC] App Key Verification API for SPIRE Integration**
>
> Hi Keylime community! 👋
>
> We're from the **AegisSovereignAI** project under LF Edge/AI. We've extended Keylime to support "App Keys" - TPM-bound application keys that enable SPIRE workload identity with hardware attestation.
>
> **What we built:**
> - **App Key Verification API** in the Keylime Verifier for on-demand SPIRE queries
> - **Delegated Certification** where the Attestation Key (AK) signs workload App Keys
> - **Geolocation Attestation** with nonce-bound location claims in PCR-15
> - **rust-keylime extensions** for TPM quote generation with geolocation
>
> **Use Case: Telecom Edge 5G with CAMARA APIs**
> A telecom operator deploys AI workloads at 5G edge sites. The solution integrates with [GSMA CAMARA Device Location APIs](https://www.camaraproject.org/) to provide:
> 1. Mobile device location verification via carrier network (not GPS spoofing)
> 2. TPM-bound proof that the edge node is in the licensed spectrum zone
> 3. Hardware-rooted identity for regulatory spectrum compliance
>
> Keylime verifies the TPM quote containing CAMARA-verified location, which SPIRE then embeds into workload SVIDs.
>
> **Reference:** [CAMARA Hardware Location Proposal](https://github.com/lfedgeai/AegisSovereignAI/blob/main/proposals/camara-hardware-location.md)
>
> **Changes:**
> - `keylime/app_key_verification.py` - New verification endpoint
> - `rust-keylime/` - Agent extensions for App Key certification
> - Feature-flagged with `unified_identity_enabled`
>
> **Resources:**
> - Repository: https://github.com/lfedgeai/AegisSovereignAI/tree/main/hybrid-cloud-poc
> - Architecture: https://github.com/lfedgeai/AegisSovereignAI/blob/main/hybrid-cloud-poc/README-arch-sovereign-unified-identity.md
>
> Would love to present at a community call and discuss the best path to upstream these features!
>
> Thanks!

### Step 2.3: Request Community Meeting Slot
- **Meeting Schedule:** Bi-weekly (check Keylime GitHub wiki)

### Step 2.4: Submit RFC Issue
- **Location:** https://github.com/keylime/keylime/issues
- **Label:** `enhancement`, `RFC`

---

## Phase 3: Envoy Community (Week 3-4)

### Step 3.1: Join Envoy Slack
- **Link:** https://envoyproxy.slack.com/
- **Channel:** `#wasm`

### Step 3.2: Post Introduction Message

> **Subject: WASM Filter for X.509 Unified Identity Claims Extraction**
>
> Hi Envoy community! 👋
>
> We're from the **AegisSovereignAI** project under LF Edge/AI. We've built a Rust-based WASM filter that extracts custom X.509 extension claims from SPIRE SVIDs for policy enforcement in hybrid cloud scenarios.
>
> **What it does:**
> - Extracts Unified Identity extension (OID `1.3.6.1.4.1.55744.1.1`) from client certificates
> - Parses sensor ID, geolocation, IMEI/IMSI claims
> - Supports three verification modes: Trust, Runtime (cached), Strict (real-time)
> - Calls a sidecar for CAMARA device location verification (mobile sensors)
> - Exposes Prometheus metrics for observability
>
> **Use Case: Zero-Trust Manufacturing IoT**
> A manufacturing plant with mobile robots and fixed sensors requires:
> 1. **GPS sensors** on fixed equipment → Trusted at attestation time (bypass sidecar)
> 2. **Mobile sensors** on robots → Real-time location verification via CAMARA APIs
> 3. **Policy enforcement** at the Envoy gateway based on sensor type and location
>
> The WASM filter extracts the sensor type from the SVID and routes to appropriate verification mode, enforcing that only devices in the authorized zone can access production systems.
>
> **Reference:** [Enterprise Private Cloud README](https://github.com/lfedgeai/AegisSovereignAI/blob/main/hybrid-cloud-poc/enterprise-private-cloud/README.md)
>
> **Resources:**
> - WASM Filter: https://github.com/lfedgeai/AegisSovereignAI/tree/main/hybrid-cloud-poc/enterprise-private-cloud/wasm-plugin
> - Full System: https://github.com/lfedgeai/AegisSovereignAI/tree/main/hybrid-cloud-poc
>
> We're planning to publish this as a standalone WASM filter. Happy to share more details or do a demo!
>
> Thanks!

### Step 3.3: Publish as Standalone Project
- Host under LF Edge/AI GitHub organization
- Add to Envoy WASM extensions examples (optional)

---

## Phase 4: Cross-Project Coordination (Week 4+)

### Step 4.1: LF Edge TAC Presentation
- Present the integration to LF Edge Technical Advisory Council
- Get organizational support for cross-CNCF collaboration

### Step 4.2: Joint Blog Post
- Publish on LF Edge blog
- Cross-post to CNCF blog (if approved)
- Title suggestion: "Hardware-Rooted Workload Identity: Bridging SPIRE and Keylime for Sovereign Edge"

### Step 4.3: Submit PRs in Phases
Based on community feedback, submit PRs to:
1. **SPIRE:** CredentialComposer plugin
2. **Keylime:** App Key Verification API + rust-keylime extensions
3. **Envoy:** WASM filter as standalone project reference

---

## Timeline Summary

| Week | Activity |
|------|----------|
| 1 | Join Slack channels, post SPIRE introduction |
| 2 | Request SPIRE meeting, post Keylime introduction |
| 3 | Present at SPIRE call, request Keylime meeting, post Envoy introduction |
| 4 | Present at Keylime call, submit RFCs based on feedback |
| 5+ | Begin PR submissions, iterate based on reviews |

---

## Contact & Resources

- **Repository:** https://github.com/lfedgeai/AegisSovereignAI
- **PoC Directory:** https://github.com/lfedgeai/AegisSovereignAI/tree/main/hybrid-cloud-poc
- **Roadmap:** https://github.com/lfedgeai/AegisSovereignAI/blob/main/hybrid-cloud-poc/UPSTREAM_MERGE_ROADMAP.md
