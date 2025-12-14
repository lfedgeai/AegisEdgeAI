# Langchain Enhancement Proposal (LEP): **Zero-Trust Governance Middleware and Verifiable Audit Logs for RAG**

**LEP Number:** 001 (Draft)

**Title:** Zero-Trust Governance Middleware and Verifiable Audit Logs for RAG

**Status:** Proposal / RFC

**Type:** Standards Track

**Target Component:** `langchain-core` / `langchain-community`

**Authors:** Ramki Krishnan (Vishanti Systems), et al.

---

### 1. Abstract
This proposal introduces a standardized **Governance Middleware** layer into the Retrieval-Augmented Generation (RAG) stack. Currently, RAG architectures typically connect `Retriever` $\rightarrow$ `LLM` directly, treating data filtering as an application-level concern.

We propose injecting a mandatory **Policy Enforcement Point (PEP)** between retrieval and generation. This middleware performs two atomic functions:
1.  **Zero-Trust Context Filtering:** Validates retrieved data chunks against an external policy engine (e.g., OPA) before they enter the LLM context window.
2.  **Verifiable Audit Logging:** Generates a cryptographically verifiable "Compliance Artifact" that logs the **"Immutable Triad"** (User Input, Context Hash, Model Config), solving the "GenAI Audit Paradox" of non-deterministic models.

### 2. Motivation
In critical infrastructure sectors (Banking, Defence, Healthcare), standard RAG architectures introduce two systemic risks that block production adoption:

* **Context Contamination:** A retriever may fetch documents the user is not authorized to see (e.g., a "Public" user retrieves a "Confidential" policy doc). If the LLM reads this chunk, it may leak the secret in its answer. Application-level "if/then" checks are brittle and hard to audit.
* **The GenAI Audit Paradox:** LLMs are probabilistic. Re-running a prompt six months later may yield a different result. Traditional logs (Input/Output) are therefore insufficient for regulatory audits. Auditors need proof of *why* a decision was made, which requires freezing the exact state of the retrieved knowledge at the moment of inference.

#### 2.1 A Note on Non-Determinism
It is important to acknowledge that even with fixed inputs and `temperature=0`, Large Language Models running on parallel GPU architectures (CUDA) may exhibit slight non-determinism due to floating-point associativity.

Therefore, **Output Reproduction** is a technically flawed standard for auditing. We cannot guarantee the model will say the exact same words six months later. This proposal shifts the standard to **Process Non-Repudiation**:
* We may not be able to reproduce the *exact output*.
* But with the **Immutable Triad**, we can cryptographically prove **what the model knew** (Context) and **how it was instructed** (Config).
* This distinguishes between a "Hardware Variance" (acceptable) and a "Governance Failure" (unacceptable, e.g., reading a banned document).

### 3. Architecture: The "Governance Fence"

We introduce a new Chain primitive: `GovernanceChain`. This sits strictly between the Retriever and the Prompt Template.

sequenceDiagram
    participant User
    participant Retriever
    participant GovernanceChain as 🛡️ GovernanceChain
    participant OPA as ⚖️ OPA Engine
    participant LLM

    User->>Retriever: Query: "How do I process a refund?"
    Retriever-->>GovernanceChain: Returns 5 Chunks
    
    rect rgb(255, 240, 240)
        Note over GovernanceChain, OPA: 🔒 Zero-Trust Filter
        GovernanceChain->>OPA: POST /v1/data/filter (User Context + Chunks)
        OPA-->>GovernanceChain: ALLOW (Chunks 1,2,4) | DENY (Chunks 3,5)
    end

    alt All Chunks Denied
        GovernanceChain-->>User: Error: Access Denied
    else Some Chunks Allowed
        GovernanceChain->>LLM: Prompt + [Chunks 1,2,4]
        LLM-->>User: Answer based on allowed data
    end
    
**Current Unsafe Flow:**
`User Query` $\rightarrow$ `Retriever` $\rightarrow$ `[Raw Chunks]` $\rightarrow$ `PromptTemplate` $\rightarrow$ `LLM`

**Proposed Governed Flow:**
`User Query` $\rightarrow$ `Retriever` $\rightarrow$ `[Raw Chunks]` $\rightarrow$ **`GovernanceChain (OPA)`** $\rightarrow$ `[Filtered Chunks]` $\rightarrow$ `PromptTemplate` $\rightarrow$ `LLM`

The `GovernanceChain` enforces a **"Fail Closed"** protocol. If the policy engine is unreachable or returns a `DENY` for all chunks, the chain aborts immediately. The LLM is never contacted, and no cost is incurred.

### 4. Specification

#### A. The Governance Interface
We propose a standard abstract base class that allows users to swap policy backends (OPA, Kyverno, or proprietary banking engines).

```python
class BaseGovernanceHandler(ABC):
    @abstractmethod
    def filter_documents(
        self, 
        user_context: Dict[str, Any], 
        documents: List[Document]
    ) -> List[Document]:
        """
        Filters documents based on external policy.
        Must raise AccessDeniedError if policy dictates 'Fail Closed'.
        """
        pass

    @abstractmethod
    def log_immutable_triad(
        self, 
        input: str, 
        accepted_docs: List[Document], 
        model_config: Dict
    ) -> str:
        """
        Writes the cryptographic 'Compliance Artifact' to the audit ledger.
        Returns a transaction ID.
        """
        pass
```

#### B. The Audit Schema: The "Compliance Artifact"

To solve the audit paradox, the middleware produces a structured JSON log for every transaction. This log captures the Immutable Triad—the minimum data required to mathematically prove the state of the system at time $T$.

**Proposed JSON Schema:**

```json
{
  "transaction_id": "tx_uuid_12345",
  "timestamp": "2025-12-14T10:30:00Z",
  "actor_identity": {
    "user_id": "jdoe_banker",
    "spiffe_id": "spiffe://bank.local/ns/loan-service/sa/credit-bot"
  },
  "governance_decision": {
    "engine": "OPA",
    "policy_version": "v2.1 (Loan_Policy_2025)",
    "outcome": "ALLOW",
    "chunks_filtered_out": 2
  },
  "immutable_triad": {
    "input_hash": "sha256:8f43...",
    "context_hash": "sha256:a7b2...",
    "model_config_hash": "sha256:c9d1..."
  },
  "raw_metadata": {
    "retrieved_doc_ids": ["policy_doc_12", "risk_guidelines_99"],
    "model_name": "llama3-70b-instruct"
  }
}
```

**Cryptographic Binding:** The entire JSON artifact above is serialized and signed using the Private Key associated with the workload's SPIFFE SVID. This creates a tamper-proof "Compliance Envelope" that proves:

* **Integrity:** The log hasn't been altered since generation.
* **Identity:** The log was definitely generated by the credit-bot workload (and not an imposter).

#### C. Integration with Workload Identity (SPIFFE/SPIRE)

This architecture is designed to support hardware-rooted identity.

**The Mechanism:** The user_context dictionary includes a `spiffe_id` field carrying a valid SVID.

**Enhanced Hardware Binding (AegisEdgeAI):** While standard SVIDs identify software, this middleware supports Unified SVIDs (as defined in the AegisEdgeAI project). These IDs cryptographically encode the Device Attestation (TPM) and Geolocational Proof alongside the workload identity.

**The Policy Value:** This enables "Triple-Blind" Governance:

* **Who:** "Only the Trading-Bot..."
* **Where:** "...running on Authorized-Server-05..."
* **What:** "...can see Confidential documents."

### 5. Performance Optimization: OPA Partial Evaluation

For high-scale Enterprise RAG, retrieving documents before filtering them introduces unnecessary latency and database load.

We propose supporting OPA Partial Evaluation to "push down" governance filters into the Vector Database (e.g., Pinecone, Weaviate, pgvector).

**How it works:**

1. The GovernanceChain sends the user_context (Identity) to OPA before retrieval.
2. OPA partially evaluates the policy and returns a set of residual conditions (e.g., `doc.classification == 'public'`).
3. The Chain translates these conditions into native Vector DB filters.

**The Benefit:** Unauthorized documents are never retrieved from the disk. This optimizes I/O and ensures strict "Zero Trust for Data" even at the database query level.

### 6. Benefits

* **Security:** Enforces "Zero Trust for Data" at the infrastructure layer. Prevents the "Confused Deputy" problem where an LLM is tricked into reading secret data.

* **Decoupling:** Enables "Policy-as-Code." Compliance teams can update OPA rules (e.g., "Ban all documents from 2023") without requiring developers to redeploy the bot.

* **Auditability:** Provides a standardized "Compliance Artifact" that satisfies the requirement for explainability in non-deterministic systems.