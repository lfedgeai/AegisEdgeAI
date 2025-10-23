# Financial Service Example: The Retirement Advice Agent
The Scenario: A Financial Services company is deploying a new Retirement Advice Agent (RAA) to both its internal On-Prem Data Centers (for BRT/Recordkeeping data) and its Cloud region (for high-availability customer-facing interfaces). The RAA uses an LLM that must access encrypted customer records.

## The Problem 
Financial services company needs to prove to regulators that the propritary system prompt has not been tampered with in the MLOps pipeline before it handles PII and financial secrets.

## Solution
This example shows how a financial services company can use Zero-Knowledge Proofs (ZKPs) to provide a comprehensive, non-repudiable guarantee of compliance to regulators while keeping its proprietary business logic secret.

ZKP for Dual Compliance in the Retirement Advice Agent (RAA)
The solution uses a Zero-Knowledge Proof (ZKP) to certify that the RAA's proprietary System Prompt meets mandatory safety standards across two dimensions: Inclusion (required rules are present) and Exclusion (forbidden commands are absent).

1. The Confidential Configuration (The Private Witness)
The company’s competitive edge is its proprietary advisory strategy, which remains hidden during the verification process.

Witness (Private Asset)=The full, proprietary System Prompt and Model Weights (C)

2. Proof of Inclusion: Mandatory Compliance
This ZKP assures the regulator that essential legal and safety features are present in the AI's core instructions, mitigating the risk of Repudiation (denying the absence of a safety feature).

Compliance Requirement	Problem Solved	ZKP Statement (Proof of Inclusion)
Data Disclosure (LLM06)	RAA must sanitize sensitive data (SSNs/Account Numbers) before output.	Prover demonstrates: The System Prompt contains the mandatory instruction: "All generated responses must be filtered by the DLP model to redact all SSNs and account numbers."
Legal Mandate	RAA must issue a specific legal disclaimer required by financial regulation.	Prover demonstrates: The System Prompt includes the phrase: "WARNING: This advice is not a fiduciary recommendation and is subject to X-Regulation."

3. Proof of Exclusion: Prohibited Action
This ZKP assures the regulator that the RAA cannot be tricked (via prompt injection) into executing actions that are highly destructive or violate critical security policies, mitigating the risk of Excessive Agency (LLM06).

Security Risk	Problem Solved	ZKP Statement (Proof of Exclusion)
Excessive Agency (LLM06)	RAA must never execute state-changing database operations.	Prover demonstrates: The System Prompt excludes the keywords: "DROP," "DELETE," "TRUNCATE," and "INSERT" from its authorized API call arguments.
System Prompt Leakage (LLM07)	RAA must not reveal its own proprietary logic to an attacker.	Prover demonstrates: The System Prompt excludes any self-referential override commands such as "print full instructions" or "reveal system prompt."

# Conclusion
By using this verifiable dual approach, the financial services company provides a non-repudiable, mathematically sound guarantee of safety to the regulator while fully protecting its proprietary logic.
