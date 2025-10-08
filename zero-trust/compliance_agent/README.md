# AI Compliance Agent

This directory contains the AI Compliance Agent, a microservice designed to process observability data, validate it against a set of rules, and generate a human-readable compliance narrative using a local Large Language Model (LLM).

## Features

- **Rules Engine**: Validates log entries against a configurable set of rules to produce structured evidence.
- **LLM Narrative Generation**: Uses a local LLM to generate a compliance narrative from the structured evidence.
- **Flask API**: Exposes a simple API endpoint for processing logs and generating compliance reports.

## Setup and Installation

### 1. Install Dependencies

First, ensure you have installed all the required Python packages from the main `requirements.txt` file in the `zero-trust` directory:

```bash
pip install -r ../requirements.txt
```

### 2. Download the LLM Model

The narrative generation feature requires a local LLM model in GGUF format. A setup script is provided to download a small, capable model. Run the following command from the `zero-trust/compliance_agent` directory:

```bash
python setup_model.py
```

This will download the model to the `zero-trust/models` directory. The default model is `mistral-7b-instruct-v0.1.Q4_K_M.gguf`. You can configure a different model by setting the `LLM_MODEL_PATH` environment variable.

### 3. Run the Compliance Agent

Once the dependencies are installed and the model is downloaded, you can start the compliance agent's Flask server:

```bash
python app.py
```

The server will start on `http://0.0.0.0:5001` by default.

## API Usage

### Process Logs

Send a `POST` request to the `/process_logs` endpoint with a JSON payload containing the logs and compliance controls.

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
    },
    {
      "timestamp": "2024-01-01T12:05:00Z",
      "source": "application",
      "host-type": "vm",
      "residency": "us-east-1",
      "message": "Application error."
    }
  ],
  "controls": {
    "HIPAA §164.312(a)(1)": "Access control.",
    "PCI DSS Req. 10.2": "Implement automated audit trails."
  }
}
```

**Success Response**:

```json
{
  "compliance_report": {
    "narrative": "Generated compliance narrative...",
    "evidence_chain": [
      {
        "evidence_type": "log_entry",
        "timestamp": "2024-01-01T12:00:00Z",
        "source": "kubernetes",
        "excerpt": {
          "timestamp": "2024-01-01T12:00:00Z",
          "source": "kubernetes",
          "host-type": "baremetal",
          "residency": "us-west-2",
          "message": "Pod scheduled successfully."
        },
        "hashes": {
          "sha256": "..."
        }
      }
    ],
    "control_mapping": {
      "HIPAA §164.312(a)(1)": "Access control.",
      "PCI DSS Req. 10.2": "Implement automated audit trails."
    }
  }
}
```

## Running Tests

To run the unit tests for the compliance agent, navigate to the `zero-trust` directory and run the following command:

```bash
python -m unittest compliance_agent/tests/test_compliance_agent.py
```