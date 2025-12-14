# LEP: Zero-Trust Governance Middleware and Verifiable Audit Logs for RAG

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

### 3. Architecture: The "Governance Fence"

We introduce a new Chain primitive: `GovernanceChain`. This sits strictly between the Retriever and the Prompt Template.

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

B. The Audit Schema: The "Compliance Artifact"To solve the audit paradox, the middleware produces a structured JSON log for every transaction. This log captures the Immutable Triad—the minimum data required to mathematically prove the state of the system at time $T$.Proposed JSON Schema:

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
    "chunks_filtered_out": 2  // "Blocked 2 confidential chunks"
  },
  "immutable_triad": {
    "input_hash": "sha256:8f43...",  // Hash of user prompt
    "context_hash": "sha256:a7b2...", // Hash of the LIST of authorized chunks
    "model_config_hash": "sha256:c9d1..." // Hash of temp=0, model=gpt-4
  },
  "raw_metadata": {
    "retrieved_doc_ids": ["policy_doc_12", "risk_guidelines_99"],
    "model_name": "llama3-70b-instruct"
  }
}

C. Integration with Workload Identity (SPIFFE/SPIRE)
This architecture is designed to support hardware-rooted identity.

The Mechanism: The user_context dictionary in the interface above is extensible.

The Standard: We propose a standard field spiffe_id within user_context that carries a valid SVID (Verifiable Identity Document).

The Policy Value: This allows the OPA policy to enforce service-to-service segmentation (e.g., "The Marketing Bot service is never allowed to read Patient Record chunks, regardless of who the human user is").

5. Benefits
Security: Enforces "Zero Trust for Data" at the infrastructure layer. Prevents the "Confused Deputy" problem where an LLM is tricked into reading secret data.

Decoupling: Enables "Policy-as-Code." Compliance teams can update OPA rules (e.g., "Ban all documents from 2023") without requiring developers to redeploy the bot.

Auditability: Provides a standardized "Compliance Artifact" that satisfies the requirement for explainability in non-deterministic systems.