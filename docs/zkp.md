# Concrete Fidelity Example: The Retirement Advice Agent
The Scenario: Fidelity is deploying a new Retirement Advice Agent (RAA) to both its internal On-Prem Data Centers (for BRT/Recordkeeping data) and its AWS Sovereign Cloud region (for high-availability customer-facing interfaces). The RAA uses an LLM that must access encrypted customer records.

## The Problem in Fidelity's Environment
Fidelity needs to prove that the propritary system prompt has not been tampered with in the MLOps pipeline before it handles PII and financial secrets.

## Solution
The RAA generates a ZKP proving that its proprietary System Prompt contains the mandated compliance rules (e.g., "Always redact SSNs") without revealing the secret logic itself. This is critical for auditing AI Safety10.
