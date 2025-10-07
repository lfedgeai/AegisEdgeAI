**Hardware‑Backed Attestation for Precision Time Protocol: Verifiable Residency and Proximity proofs** - work in progress
======================================================================================================

This document defines an extension to Precision Time Protocol (PTP) that provides per‑event cryptographic
attestation using non‑exportable asymmetric keys resident in TPMs or HSMs, and an optional
PTP‑in‑HTTPS/MTLS encapsulation mode. When combined with freshness and multi‑observer correlation, this provides defensible proof of proximity for timing events. PTP‑in‑HTTPS/MTLS adds end‑to‑end confidentiality for timing payloads
across untrusted fabrics.

1. Introduction and motivation
--------------------------------

Precise, auditable time provenance is increasingly required by regulated systems, distributed ledgers,
event forensics, and safety‑critical infrastructures. Existing symmetric PTP authentication primitives
provide integrity but limited non‑repudiation and fragile key distribution (e.g., https://www.ietf.org/id/draft-kumarvarigonda-ptp-auth-extension-00.html).

This draft specifies an asymmetric, TPM/HSM‑backed attestation extension for PTP events plus an
optional PTP‑in‑HTTPS/MTLS encapsulation mode. Goals are per‑event provenance, replay resistance,
staged deployability in heterogeneous environments, and practical offload to SmartNICs or HSMs to
meet performance needs. The optional HTTPS/MTLS encapsulation adds end‑to‑end confidentiality to the
integrity and provenance provided by signing.

2. Goals and non‑goals
----------------------

2.1 Goals

- Provide per‑event cryptographic provenance for PTP timing events using non‑exportable asymmetric keys.
- Define a compact attestation token and wire formats for in‑band and tunneled transports.
- Specify freshness and proximity primitives (nonce challenge, monotonic counters, verifier RTT logging, optional PCR quotes).
- Enable staged deployment: software (TPM) first, SmartNIC/HSM offload next.
- Provide clear verifier/registrar operational guidance and a minimal PKI model.
- Clarify confidentiality tradeoffs introduced by PTP‑in‑HTTPS/MTLS.

2.2 Non‑Goals

- Prove geographic location solely from a signed timestamp.
- Replace or mandate specific in‑fabric transparent‑clock behaviors in unmanaged networks.
- Prescribe vendor firmware implementations beyond measured‑boot and PCR reporting requirements.

3. Terminology and assumptions

- PHC: Packet Hardware Clock exposed by NIC or SmartNIC.
- TPM: Trusted Platform Module supporting non‑exportable keys and Quote operations.
- HSM: Hardware Security Module on SmartNIC or separate appliance.
- Verifier: Service that validates signed attestation tokens and records audit evidence.
- Registrar: PKI/registry service binding `signer_id` to device identity, PCR profile, and revocation state.
- Monotonic Counter: Non‑decreasing hardware or TPM counter used to prevent replay.
- HTTPS/MTLS: HTTP over TLS 1.3 with mutual TLS (client certificates) for endpoint authentication.
- SmartNIC: Programmable NIC with PHC, crypto acceleration, and optionally on‑card HSM.

Assumptions: endpoints have TPM or accessible HSM key material; verifiers and registrars are trusted by
operators; network can carry MTLS connections between endpoints and verifiers.

4. Architectural overview and deployment models
----------------------------------------------

In‑band signed PTP extension

: PTP messages carry an attached attestation TLV for each signed event. This mode preserves end‑to‑end
	integrity and provenance of PTP payloads (signature binds payload, PHC timestamp, nonce, seq, counter)
	while leaving confidentiality and in‑fabric correction semantics to the underlying network fabric.

	Note: In‑band attestation preserves integrity and provenance but does not provide confidentiality;
    PTP payloads remain visible to in‑path observers.

PTP‑in‑HTTPS/MTLS encapsulation

: Native PTP bytes are framed inside persistent HTTPS/MTLS streams between endpoints. Attestation tokens are
	carried inside the same MTLS connection or out‑of‑band to a verifier. This prevents in‑path modification
	and adds confidentiality for timing payloads and attestation metadata.

5. SmartNIC offload patterns
----------------------------

- On‑card signing and TLS acceleration (best performance and minimal host attack surface).
- SmartNIC captures PHC timestamps and proxies sign requests to platform TPM.


