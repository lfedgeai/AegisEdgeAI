# Langchain Enhancement Proposal (LEP): **Zero-Trust Governance Middleware and Verifiable Audit Logs for RAG**

**LEP Number:** 001 (Draft)

**Title:** Zero-Trust Governance Middleware and Verifiable Audit Logs for RAG

**Status:** Proposal / RFC

**Type:** Standards Track

**Target Component:** `langchain-core` / `langchain-community`

**Authors:** Ramki Krishnan (Vishanti Systems), et al.

**Related Standards:** NIST AI RMF (Governance), CNCF Cloud Native Security (Zero Trust)

### 1\. Abstract

This proposal introduces a standardized **Governance Middleware** layer into the Retrieval-Augmented Generation (RAG) stack. Currently, RAG architectures typically connect `Retriever` $\rightarrow$ `LLM` directly, treating data filtering as an application-level concern.

We propose injecting a mandatory **Policy Enforcement Point (PEP)** between retrieval and generation. This middleware performs two atomic functions:

1.  **Zero-Trust Context Filtering:** Validates retrieved data chunks against an external policy engine (e.g., OPA) before they enter the LLM context window.
2.  **Verifiable Audit Logging:** Generates a cryptographically verifiable "Compliance Artifact" that logs the **"Immutable Triad"** (User Input, Context Hash, Model Config), solving the "GenAI Audit Paradox" of non-deterministic models.

### 2\. Motivation

In critical infrastructure sectors (Banking, Defence, Healthcare), standard RAG architectures introduce two systemic risks that block production adoption:

  * **Context Contamination:** A retriever may fetch documents the user is not authorized to see (e.g., a "Public" user retrieves a "Confidential" policy doc). If the LLM reads this chunk, it may leak the secret in its answer. Application-level "if/then" checks are brittle and hard to audit.
  * **The GenAI Audit Paradox:** LLMs are probabilistic. Re-running a prompt six months later may yield a different result. Traditional logs (Input/Output) are therefore insufficient for regulatory audits. Auditors need proof of *why* a decision was made, which requires freezing the exact state of the retrieved knowledge at the moment of inference.

#### 2.1 The Current "Blind" Architecture

In standard RAG pipelines, the Retriever and LLM are directly connected. There is no control plane to inspect what data is actually being fed to the model.

```text
+------+        +-----------+        +--------------------------+        +-----+
| User |        | Retriever |        |      Prompt Template     |        | LLM |
+------+        +-----------+        +--------------------------+        +-----+
   |                  |                            |                        |
   |---- Query ------>|                          (Blindly Accepts)          |
   |                  |--- [CONFIDENTIAL DOC] ---->|                        |
   |                  |--- [PUBLIC DOC] ---------->|                        |
   |                  |                            |                        |
   |                  |                            |--- Context + Query --->|
   |                  |                            |                        |
   |                  |                            |                        |
   |<-------------------------------------------------- Secret Leaked ------|
                                                   (No Audit Log of Context)
```

#### 2.2 A Note on Non-Determinism

It is important to acknowledge that even with fixed inputs and `temperature=0`, Large Language Models running on parallel GPU architectures (CUDA) may exhibit slight non-determinism.

Therefore, **Output Reproduction** is a technically flawed standard for auditing. This proposal shifts the standard to **Process Non-Repudiation**:

  * We may not be able to reproduce the *exact output*.
  * But with the **Immutable Triad**, we can cryptographically prove **what the model knew** (Context) and **how it was instructed** (Config).
  * This distinguishes between a "Hardware Variance" (acceptable noise) and a "Governance Failure" (unacceptable breach, e.g., reading a banned document).

### 3\. Architecture: The "Governance Fence"

We introduce a new architectural primitive: the **`GovernanceChain`**.

This component acts as a **mandatory middleware layer** that separates the *retrieval of knowledge* from the *synthesis of answers*. It establishes a hard **Trust Boundary** within the standard RAG pipeline.

#### 3.1 Logical Flow

The `GovernanceChain` intercepts the flow of data *after* retrieval but *before* prompt construction. It treats the `Retriever` as an untrusted source and the `LLM` as an untrusted consumer.

```text
                      [ TRUST BOUNDARY: THE GOVERNANCE FENCE ]
                                         ||
+------+        +-----------+            ||    +-----------------+        +-----+
| User |        | Retriever |            ||    | GovernanceChain |        | LLM |
+------+        +-----------+            ||    +-----------------+        +-----+
   |                  |                  ||             |                    |
   |---- Query ------>|                  ||             |                    |
   |                  |--- Raw Chunks -- || ----------> |                    |
   |                  |  (Untrusted)     ||             |                    |
   |                  |                  ||             |--- Validate ----> [ OPA ]
   |                  |                  ||             |<-- Allow/Deny --- [Engine]
   |                  |                  ||             |                    |
   |                  |                  ||             |                    |
   |<-- Access Denied ------------------ || <---(Stop)--|                    |
   |   (Default Deny)                    ||             |                    |
   |                  |                  ||             |--- Filtered ------>|
   |                  |                  ||             |    Context         |
   |                  |                  ||             |                    |
   |<----------------------------------- || <------------------- Answer -----|
```

1.  **Interception:** The chain receives the `[Raw Chunks]` from the Retriever.
2.  **Validation:** It queries the **Policy Engine** (e.g., OPA) with the `User Identity` + `Chunk Metadata`.
3.  **Enforcement:**
      * **Deny:** If the policy evaluates to `DENY`, the chunk is dropped. If *all* chunks are dropped, the chain raises an `AccessDeniedError` immediately (**Fail Closed**). The LLM is never contacted.
      * **Allow:** Only permitted chunks are passed to the `PromptTemplate`.

#### 3.2 Component Design

The `GovernanceChain` is designed as a **Runnable** in the LangChain Expression Language (LCEL). It accepts a `Dict` containing `input`, `context`, and `user_info`, and returns a `Dict` with the `filtered_context`.

This design ensures:

  * **Composability:** It can be dropped into any existing chain (`Retrieve | Governance | Generate`).
  * **Atomic Logging:** The chain owns the responsibility of generating the "Compliance Artifact" because it is the only component that sees both the raw input and the final allowed context.

### 4\. Specification

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
    "spiffe_id": "spiffe://bank.local/ns/loan-service/sa/credit-bot",
    "attributes": {
        "location": "US-East-DataCenter", 
        "tpm_verified": true
    }
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

**The Mechanism:** The user\_context dictionary includes a `spiffe_id` field carrying a valid SVID.

**Enhanced Hardware Binding (AegisEdgeAI):** While standard SVIDs identify software, this middleware supports Unified SVIDs (as defined in the AegisEdgeAI project). These IDs cryptographically encode the Device Attestation (TPM) and Geolocational Proof alongside the workload identity.

**The Policy Value:** This enables "Triple-Blind" Governance:

  * **Who:** "Only the Trading-Bot..."
  * **Where:** "...running on Authorized-Server-05..."
  * **What:** "...can see Confidential documents."

### 5\. Performance Optimization: OPA Partial Evaluation

For high-scale Enterprise RAG, retrieving documents before filtering them introduces unnecessary latency and database load.

We propose supporting OPA Partial Evaluation to "push down" governance filters into the Vector Database (e.g., Pinecone, Weaviate, pgvector).

**How it works:**

1.  The GovernanceChain sends the user\_context (Identity) to OPA *before* retrieval.
2.  OPA partially evaluates the policy and returns a set of residual conditions (e.g., `doc.classification == 'public'`).
3.  The Chain translates these conditions into native Vector DB filters.

**The Benefit:** Unauthorized documents are never retrieved from the disk. This optimizes I/O and ensures strict "Zero Trust for Data" even at the database query level.

  * **Note:** While Partial Evaluation is the gold standard for performance, the initial implementation of `GovernanceChain` will support standard "Post-Retrieval Filtering" to ensure broad compatibility with all Retrievers.

### 6\. Benefits

  * **Security:** Enforces "Zero Trust for Data" at the infrastructure layer. Prevents the "Confused Deputy" problem where an LLM is tricked into reading secret data.

  * **Decoupling:** Enables "Policy-as-Code." Compliance teams can update OPA rules (e.g., "Ban all documents from 2023") without requiring developers to redeploy the bot.

  * **Auditability:** Provides a standardized "Compliance Artifact" that satisfies the requirement for explainability in non-deterministic systems.