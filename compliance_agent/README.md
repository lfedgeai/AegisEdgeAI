# Compliance Agent

This directory contains the Compliance Agent, a standalone microservice designed to process observability data and validate it against a deterministic set of rules.

## Features

- **Deterministic Rules Engine**: Validates log entries against a configurable set of rules to produce structured evidence. Each rule includes a specific control mapping and a pre-defined explanation.
- **Automated Report Generation**: Generates a consistent, fact-based compliance report from the structured evidence using a template.
- **Flask API**: Exposes a simple API endpoint for processing logs and generating compliance reports.
- **Streamlit UI**: Includes a user-friendly interface for interacting with the agent.
- **AI-Powered Rule Auditor**: An additional tool that uses a consensus-based approach with multiple LLMs to validate the compliance rules themselves.

## Setup and Installation

### 1. Install Dependencies

First, ensure you have installed all the required Python packages from the `requirements.txt` file in this directory:

```bash
pip install -r requirements.txt
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

## Auditing Compliance Rules with Multi-Model Consensus

This project includes an advanced tool for auditing the compliance rules themselves using a consensus-based approach with three LLMs. This provides a highly robust validation of the correctness and logic of the rules defined in `rules_engine.py`.

The auditor loads all three models defined in the `llm_models` list in `config.py`. It gets an independent assessment from each model and then calculates the average pairwise cosine similarity score to quantify the overall level of agreement among them. A low score indicates a potential disagreement that warrants manual review.

### 1. Configure Models

You can configure which models to use for the audit by editing the `llm_models` list in `compliance_agent/config.py`.

### 2. Download Models

Ensure you have downloaded all the configured LLM models by running the setup script from the `compliance_agent` directory:

```bash
python setup_model.py
```

### 3. Run the Auditor

Run the rule auditor with the following command from the `compliance_agent` directory:

```bash
python rule_auditor.py
```

The auditor will output a detailed consensus report for each rule, including the assessment from each model and the final similarity score.

## Running Tests

To run the unit tests, navigate to the **root of the repository** and run the following command:

```bash
python -m unittest discover -s compliance_agent
```