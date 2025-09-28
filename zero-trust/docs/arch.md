# Unified workload identity - End-to-end flow with three rings and communication mechanisms - work in progress

This unifies the outermost ring (bm SPIRE agent SVID), outer ring (VM attestation and VM SVID), and inner ring (workload identity and KBS release), with explicit transport and device access at each step.

---

## Outermost ring: Bare-metal SPIRE agent SVID

### Phase 0: Host attestation and bm SVID issuance
- **Initiate:** bm SPIRE agent requests its node SVID from SPIRE server.
- **Comms:** mTLS (bm SPIRE agent ↔ SPIRE server).
- **Evidence:** Host TPM quote via Keylime agent, IMA runtime measurements, optional GPU/geolocation plugins.
- **TPM access:** `/dev/tpm0` (host physical TPM via TIS/CRB).
- **Result:** bm SPIRE agent receives a short‑TTL SVID and uses it to authenticate subsequent VM evidence relays.

---

## Outer ring: VM attestation and VM SVID

### Phase 1: Challenge issuance (server-anchored nonces)
- **Request:** VM/kata agent initiates “attest‑and‑SVID”.
- **Comms:** UDS (workload ↔ VM/kata agent), UDS (VM/kata agent ↔ VM shim), vsock (VM shim ↔ bm SPIRE agent), mTLS (bm SPIRE agent ↔ SPIRE server).
- **Server action:** SPIRE server issues `session_id`, `nonce_host`, `nonce_vm`, `expires_at`, and a signed challenge token.
- **Return path:** mTLS (server→bm), vsock (bm→shim), UDS (shim→VM/kata agent).

### Phase 2: VM quote (vTPM)
- **Compute:** vm_claims_digest over VM measured boot claims (PCRs, VMID, image digest, kata sandbox config hash).
- **Quote:** `TPM2_Quote` with `extraData = H(session_id || nonce_vm || vm_claims_digest)`.
- **TPM access:** `/dev/tpm0` inside VM (vTPM TIS/CRB) or TPM proxy socket.
- **Comms:** UDS (VM/kata agent → VM shim), vsock (VM shim → bm SPIRE agent).
- **Evidence:** VM quote, AK pub, PCRs, event logs, vm_claims_digest, VM metadata.

### Phase 3: Host quote (physical TPM via Keylime)
- **Request:** bm SPIRE agent asks Keylime agent for host quote.
- **Quote:** `TPM2_Quote` with `extraData = H(session_id || nonce_host || host_claims_digest)`.
- **TPM access:** `/dev/tpm0` (host physical TPM).
- **Comms:** local RPC or mTLS (bm SPIRE agent ↔ Keylime agent).
- **Evidence:** Host quote, AK/EK chain, PCRs, IMA allowlist, event logs, host_claims_digest.

### Phase 4: Evidence bundling and verification
- **Bundle:** bm SPIRE agent aggregates VM evidence + host evidence + server challenge token and signs the bundle.
- **Comms:** mTLS (bm SPIRE agent → SPIRE server), mTLS (SPIRE server ↔ Keylime verifier).
- **Verify:** Keylime verifier checks EK/AK chains, PCR profiles, IMA allowlists, event logs, nonce bindings, and shared session_id.
- **Consume nonces:** SPIRE server marks nonces used.
- **Result:** If both host and VM pass, SPIRE server issues VM SVID (short TTL, fused selectors: host AK hash, VM AK hash, PCRs, VM image, sandbox config).
- **Delivery:** mTLS (server→bm), vsock (bm→shim), UDS (shim→VM/kata agent).

---

## Inner ring: Workload identity and key release

### Phase 5: Workload SVID issuance
- **Request:** Workload asks VM SPIRE agent for identity.
- **Comms:** UDS (workload ↔ VM SPIRE agent), mTLS (VM SPIRE agent ↔ SPIRE server using VM SVID).
- **Selectors:** VM SPIRE agent collects workload selectors (UID, cgroup, labels).
- **Result:** SPIRE server issues workload SVID (short TTL). Delivered via UDS to workload.

### Phase 6: KBS key release
- **Request:** Workload presents workload SVID to KBS.
- **Comms:** mTLS with SPIFFE bundle (workload ↔ KBS).
- **Policy:** KBS validates SPIFFE ID, selectors, TTL, and trust roots.
- **Result:** KBS releases scoped key (one‑time unwrap, short TTL) for workload cryptographic operations.

---

## Three rings summary

- **Outermost ring (bm SVID):** Host integrity and bm SPIRE agent trust via physical TPM and Keylime.
- **Outer ring (VM SVID):** VM’s measured boot and session freshness, fused with host evidence; issued only on joint pass.
- **Inner ring (workload SVID):** Workload identity anchored to VM SVID; enables KBS key release to attested workloads.

---

## Full mermaid diagram with comms and rings

```mermaid
sequenceDiagram
    autonumber
    %% Outermost Ring participants
    box Outermost Ring: Bare-metal host trust (bm SVID)
    participant BM as bm SPIRE agent
    participant Server as SPIRE server
    participant KLAgent as Keylime agent (host)
    participant KLVer as Keylime verifier
    participant HostTPM as Host TPM (/dev/tpm0)
    end

    %% Outer Ring participants
    box Outer Ring: VM attestation & VM SVID
    participant Shim as VM shim (UDS)
    participant VMA as VM/kata agent (may include VM SPIRE agent)
    participant vTPM as VM TPM (/dev/tpm0 or proxy)
    end

    %% Inner Ring participants
    box Inner Ring: Workload identity & KBS release
    participant WL as Workload inside VM
    participant KBS as Key Broker Service
    end

    %% Phase 0: bm SVID
    BM->>Server: Request bm node SVID (mTLS)
    BM->>KLAgent: Provide host attestation inputs (local RPC/mTLS)
    KLAgent->>HostTPM: TPM2_Quote + IMA + logs (physical TPM access)
    KLAgent-->>BM: Host evidence
    BM->>Server: Submit host evidence (mTLS)
    Server->>KLVer: Forward for verification (mTLS)
    KLVer-->>Server: Verdict (signed)
    alt Host pass
      Server-->>BM: Issue bm SVID (short TTL) (mTLS)
    else Host fail
      Server-->>BM: Deny bm SVID
    end

    %% Phase 1: Challenge for VM
    VMA->>Shim: Initiate attest-and-SVID (UDS)
    Shim->>BM: Forward request (vsock)
    BM->>Server: Request server challenge (mTLS)
    Server-->>BM: session_id, nonce_host, nonce_vm, expires_at, token (mTLS)
    BM-->>Shim: Relay VM challenge (vsock)
    Shim-->>VMA: Relay VM challenge (UDS)

    %% Phase 2: VM vTPM quote
    VMA->>VMA: Compute vm_claims_digest (PCRs, VMID, image, sandbox)
    VMA->>vTPM: TPM2_Quote extraData=H(session_id||nonce_vm||vm_claims_digest) (TPM device)
    vTPM-->>VMA: VM quote + PCRs + logs + AK
    VMA->>Shim: Send VM evidence (UDS)
    Shim->>BM: Forward VM evidence (vsock)

    %% Phase 3: Host TPM quote
    BM->>KLAgent: Request host TPM2_Quote with extraData=H(session_id||nonce_host||host_claims_digest) (local RPC/mTLS)
    KLAgent->>HostTPM: TPM2_Quote (physical TPM)
    HostTPM-->>KLAgent: Host quote + PCRs + logs + AK/EK chain + IMA
    KLAgent-->>BM: Host evidence

    %% Phase 4: Bundle and verify
    BM->>BM: Assemble & sign bundle (VM + host + challenge token)
    BM->>Server: Submit signed evidence bundle (mTLS)
    Server->>KLVer: Forward bundle + policy IDs (mTLS)
    KLVer->>KLVer: Verify EK/AK chains, PCR profiles, IMA allowlist, event logs, nonces, session_id
    KLVer-->>Server: Combined verdict (host+VM pass/fail)
    Server->>Server: Consume nonces (mark used)
    alt Host+VM pass
      Server-->>BM: Issue VM SVID (fused selectors; short TTL) (mTLS)
      BM-->>Shim: Relay VM SVID (vsock)
      Shim-->>VMA: Deliver VM SVID (UDS)
    else Any fail
      Server-->>BM: Failure (no VM SVID)
      BM-->>Shim: Relay failure (vsock)
      Shim-->>VMA: Inform failure (UDS)
    end

    %% Phase 5: Workload SVID issuance
    WL->>VMA: Request workload identity (UDS)
    VMA->>Server: Authenticate using VM SVID (mTLS)
    Server->>Server: Validate VM SVID (TTL, selectors, revocation)
    VMA->>Server: Send workload selectors (mTLS)
    Server-->>VMA: Issue workload SVID (short TTL) (mTLS)
    VMA-->>WL: Deliver workload SVID (UDS)

    %% Phase 6: KBS key release
    WL->>KBS: Present workload SVID (mTLS/SPIFFE)
    KBS->>KBS: Validate SPIFFE ID, selectors, TTL, trust roots
    KBS-->>WL: Release scoped key (one-time unwrap, short TTL)
```

