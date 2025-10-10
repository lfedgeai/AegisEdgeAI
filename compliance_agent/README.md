# Compliance Agent

This directory contains the Compliance Agent, a standalone microservice designed to process observability data and validate it against a deterministic set of rules.

## Features

- **Deterministic Rules Engine**: Validates log entries against a configurable set of rules to produce structured evidence. Each rule includes a specific control mapping and a pre-defined explanation.
- **Automated Report Generation**: Generates a consistent, fact-based compliance report from the structured evidence using a template.
- **Flask API**: Exposes a simple API endpoint for processing logs and generating compliance reports.
- **Streamlit UI**: Includes a user-friendly interface for interacting with the agent.
- **AI-Powered "Compliance as Code" Tools**: A suite of tools that use local LLMs to help you build and validate your compliance rules, including a Rule Scaffold Generator and a Multi-Model Rule Auditor.

## Setup and Installation

### 1. Install Dependencies

First, ensure you have installed all the required Python packages from the `requirements.txt` file in this directory:

```bash
pip install -r requirements.txt
```

### 2. Download AI Models (for AI Tools)

If you plan to use the AI-powered tools (Scaffold Generator or Rule Auditor), you must first download the required LLM models. Run the following command from the `compliance_agent` directory:

```bash
python setup_model.py
```

## Running the Core Application

To run the main compliance agent and its UI, use the following commands.

### 1. Start the Flask Backend

Run the following command from the `compliance_agent` directory:

```bash
python app.py
```

The server will start on `http://0.0.0.0:5001` by default.

### 2. Start the Streamlit UI

In a separate terminal, run the following command from the `compliance_agent/ui` directory:

```bash
streamlit run app.py
```

## "Compliance as Code" Workflow Tools

This project includes AI-powered tools to help build and validate your compliance rules.

### Generating Rule Scaffolds with AI

To kickstart the creation of a new compliance rule, you can use the `scaffold_generator.py` tool. It takes a high-level requirement (e.g., "PCI DSS Req. 1.2.1") and uses an LLM to generate a structured YAML template for the new rule. This template includes a suggested name, control mapping, rationale, recommended evidence types, and a commented-out validation template for a security engineer to complete.

To use the generator, run the following command from the `compliance_agent` directory:

```bash
python scaffold_generator.py "PCI DSS Req. 1.2.1"
```

### Auditing Compliance Rules with Multi-Model Consensus

After you have implemented a rule, you can use the advanced auditing tool to validate it with a consensus-based approach using three LLMs. This provides a highly robust validation of the rule's correctness and logic. The auditor loads all three models defined in `config.py`, gets an independent assessment from each, and calculates an average similarity score to quantify their level of agreement.

To run the auditor, use the following command from the `compliance_agent` directory:

```bash
python rule_auditor.py
```

## Running Tests

To run the unit tests, navigate to the **root of the repository** and run the following command:

```bash
python -m unittest discover -s compliance_agent
```