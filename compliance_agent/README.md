# Compliance Agent

This directory contains the Compliance Agent, a standalone microservice designed to process observability data and validate it against a deterministic set of rules.

## "Compliance as Code" Workflow

This project uses a "Compliance as Code" approach to manage and automate compliance validation. The workflow is designed to be deterministic, reliable, and maintainable.

The core workflow is as follows:

1.  **Define Requirements:** Compliance requirements (e.g., from the PCI DSS document) are defined in a structured, human-readable YAML file: `pci_requirements.yaml`. This serves as the single source of truth for the controls.

2.  **Auto-Generate Rule Stubs:** The `rule_generator.py` tool reads the YAML file and automatically generates the corresponding Python `Rule` object definitions. This eliminates manual boilerplate and ensures consistency between the documented requirements and the code.

3.  **Implement and Review (Human-in-the-Loop):** A security engineer copies the auto-generated rule stubs into `rules_engine.py`. Their task is to implement the final, environment-specific `validation_logic` for each rule. This keeps a human expert in the loop for the most critical part of the process.

4.  **Automated Validation:** Once implemented, the `RulesEngine` uses these deterministic rules to validate log data and generate consistent, fact-based compliance reports via the API.

## Features

- **Deterministic Rules Engine**: Validates log entries against a configurable set of rules defined in `rules_engine.py`.
- **Automated Report Generation**: Generates a consistent, fact-based compliance report from the structured evidence using a template.
- **Flask API**: Exposes a simple API endpoint for processing logs and generating compliance reports.
- **Streamlit UI**: Includes a user-friendly interface for interacting with the agent.

## Setup and Installation

### 1. Install Dependencies

First, ensure you have installed all the required Python packages from the `requirements.txt` file in this directory:

```bash
pip install -r requirements.txt
```

### 2. Run the Compliance Agent

Once the dependencies are installed, you can start the compliance agent's Flask server. Run the following command from the `compliance_agent` directory:

```bash
python app.py
```

The server will start on `http://0.0.0.0:5001` by default.

## Generating New Compliance Rules

To add new compliance rules, follow the "Compliance as Code" workflow:

1.  **Add to YAML:** Add a new entry to the `pci_requirements.yaml` file with the new control's details.
2.  **Run the Generator:** Run the rule generator from the `compliance_agent` directory:
    ```bash
    python rule_generator.py
    ```
3.  **Implement the Logic:** Copy the generated Python code from the console into `rules_engine.py` and implement the `validation_logic`.

## Running Tests

To run the unit tests, navigate to the **root of the repository** and run the following command:

```bash
python -m unittest discover -s compliance_agent
```