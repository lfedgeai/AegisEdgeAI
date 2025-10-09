# Compliance Agent

This directory contains the Compliance Agent, a standalone microservice designed to process observability data and validate it against a deterministic set of rules.

## Features

- **Deterministic Rules Engine**: Validates log entries against a configurable set of rules to produce structured evidence. Each rule includes a specific control mapping and a pre-defined explanation.
- **Automated Report Generation**: Generates a consistent, fact-based compliance report from the structured evidence using a template.
- **Flask API**: Exposes a simple API endpoint for processing logs and generating compliance reports.
- **Streamlit UI**: Includes a user-friendly interface for interacting with the agent.
- **AI-Powered Rule Auditor**: An additional tool that uses a local LLM to perform a "sanity check" on the compliance rules themselves, helping to ensure their semantic correctness.

## Setup and Installation

### 1. Install Dependencies

First, ensure you have installed all the required Python packages from the `requirements.txt` file in this directory:

```bash
pip install -r requirements.txt
```

### 2. Download the AI Model (for Rule Auditor)

If you plan to use the AI-powered rule auditor, you must first download the required LLM model. Run the following command from the `compliance_agent` directory:

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

## Running the AI Rule Auditor

To use the AI to validate the correctness of your compliance rules, run the following command from the `compliance_agent` directory:

```bash
python rule_auditor.py
```

The auditor will output an AI-generated sanity check for each rule.

## Running Tests

To run the unit tests, navigate to the **root of the repository** and run the following command:

```bash
python -m unittest discover -s compliance_agent
```