# Compliance Agent

This directory contains the Compliance Agent, a standalone microservice designed to process observability data and validate it against a deterministic set of rules.

## Features

- **Deterministic Rules Engine**: Validates log entries against a configurable set of rules to produce structured evidence. Each rule includes a specific control mapping and a pre-defined explanation.
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

## API Usage

### Process Logs

Send a `POST` request to the `/process_logs` endpoint with a JSON payload containing the logs and the name of the compliance framework to audit against.

**Endpoint**: `POST /process_logs`

**Request Body**:

```json
{
  "logs": [
    {
      "timestamp": "2024-01-01T12:00:00Z",
      "source": "kubernetes",
      "host-type": "baremetal",
      "residency": "us-west-2",
      "message": "Pod scheduled successfully."
    }
  ],
  "framework": "PCI DSS"
}
```

## Running the UI

This project includes a Streamlit-based UI for easy interaction with the agent. For instructions on how to run it, please see the `README.md` file in the `compliance_agent/ui` directory.

## Running Tests

To run the unit tests for the compliance agent, navigate to the **root of the repository** and run the following command:

```bash
python -m unittest discover -s compliance_agent
```