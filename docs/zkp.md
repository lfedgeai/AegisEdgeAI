# Financial Service Example: The Retirement Advice Agent ($\text{RAA}$)

## Scenario & Problem Statement

**The Scenario:** A Financial Services company is deploying a new **Retirement Advice Agent ($\text{RAA}$)**, which utilizes an $\text{LLM}$ to access encrypted customer records. The $\text{RAA}$ operates in a hybrid environment: internal On-Prem Data Centers (for BRT/Recordkeeping) and Cloud regions (for customer interfaces).

**The Problem:** The company must **prove to regulators** that the $\text{RAA}$'s proprietary business logic (System Prompt and Model Weights) has not been tampered with in the $\text{MLOps}$ pipeline, **without disclosing** that proprietary information.

## Solution: The ZKP Dual Compliance Model

This architecture uses **Zero-Knowledge Proofs ($\text{ZKP}$)** to provide a comprehensive, non-repudiable **Proof of Governance ($\text{PoGo}$)** for the $\text{AI}$ supply chain, satisfying both regulatory audit and competitive secrecy.

The company's competitive edge—the proprietary advisory strategy—remains hidden as the **Witness** (the secret).

### 1. Proof of Inclusion (Regulatory Compliance) ✅

This $\text{ZKP}$ addresses the **Repudiation Risk**—the inability to prove a safety mechanism exists.

| Requirement | Problem Solved | ZKP Statement (The Non-Repudiable Proof) |
| :--- | :--- | :--- |
| **Data Confidentiality** ($\text{LLM06}$) | Compromise of Proprietary Logic | **Prover demonstrates:** The System Prompt **contains** the instruction to filter and redact $\text{SSN}$ and account numbers via a $\text{DLP}$ model. |
| **Legal Mandate** | Denying the absence of a required legal warning. | **Prover demonstrates:** The System Prompt **includes** the phrase: "WARNING: This advice is not a fiduciary recommendation and is subject to X-Regulation." |
| **Outcome ($\text{PoGo}$):** The regulator verifies the cryptographic proof, gaining a **mathematical guarantee** that the $\text{RAA}$ satisfies these $\text{LLM06}$ and financial requirements, all without reading the proprietary advisory code. |

### 2. Proof of Exclusion (Security/Excessive Agency) 🛑

This $\text{ZKP}$ addresses the **Excessive Agency Risk**—the danger that the $\text{AI}$ model can be tricked into performing unauthorized, destructive actions ($\text{Prompt Injection}$ is $\text{NP}$-complete).

| Security Risk | Problem Solved | ZKP Statement (The Ironclad Guardrail) |
| :--- | :--- | :--- |
| **Excessive Agency** ($\text{LLM06}$) | $\text{RAA}$ executes state-changing $\text{DB}$ operations ($\text{DELETE}$). | **Prover demonstrates:** The System Prompt **excludes** the keywords: "DROP," "DELETE," and "TRUNCATE" from its authorized $\text{API}$ call arguments. |
| **System Prompt Leakage** ($\text{LLM07}$) | $\text{RAA}$ reveals its own proprietary logic to an attacker. | **Prover demonstrates:** The System Prompt **excludes** any self-referential override commands such as "print full instructions" or "reveal system prompt." |
| **Outcome ($\text{PoGo}$):** This creates an **ironclad, proactive guardrail**. It provides non-repudiable proof that the $\text{RAA}$ is mathematically incapable of being directed to perform unauthorized, destructive actions. |

## Conclusion

By leveraging this verifiable dual $\text{ZKP}$ approach, the financial services company provides a **non-repudiable, mathematically sound guarantee of safety** to the regulator while fully **protecting its proprietary business logic**—a critical solution for security architects in the $\text{AI}$ supply chain.
