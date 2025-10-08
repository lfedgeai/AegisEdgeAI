# AI Compliance Agent

This directory contains the AI Compliance Agent, a standalone microservice designed to process observability data, validate it against a set of rules, and generate a human-readable compliance narrative using a local Large Language Model (LLM).

## Features

- **Rules Engine**: Validates log entries against a configurable set of rules to produce structured evidence.
- **Intelligent Narrative Generation**: Uses a local LLM to act as a compliance expert, analyzing evidence and mapping it to specific controls within a high-level framework (e.g., "PCI DSS").
- **Flask API**: Exposes a simple API endpoint for processing logs and generating compliance reports.
- **Streamlit UI**: Includes a user-friendly interface for interacting with the agent.

## Setup and Installation

### 1. Install Dependencies

First, ensure you have installed all the required Python packages from the `requirements.txt` file in this directory:

```bash
pip install -r requirements.txt
```

### 2. Download the LLM Model

The narrative generation feature requires a local LLM model in GGUF format. A setup script is provided to download a small, capable model. Run the following command from the `compliance_agent` directory:

```bash
python setup_model.py
```

This will download the model to the `compliance_agent/models` directory. The default model is `mistral-7b-instruct-v0.1.Q4_K_M.gguf`. You can configure a different model by setting the `LLM_MODEL_PATH` environment variable.

### 3. Run the Compliance Agent

Once the dependencies are installed and the model is downloaded, you can start the compliance agent's Flask server. Run the following command from the `compliance_agent` directory:

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