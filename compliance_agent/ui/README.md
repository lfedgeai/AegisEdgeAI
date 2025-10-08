# AI Compliance Agent UI

This directory contains a Streamlit-based web interface for the AI Compliance Agent. This UI allows users to easily input log data and compliance controls to generate a compliance report without directly using the API.

## Prerequisites

Before running the UI, ensure that the AI Compliance Agent is running, as this interface communicates with its API. You can find instructions for running the agent in the parent directory's `README.md` file.

All dependencies for the UI are included in the `requirements.txt` file in the parent `compliance_agent` directory.

## How to Run

Once the dependencies are installed, you can start the Streamlit application with the following command from the `compliance_agent/ui` directory:

```bash
streamlit run app.py
```

The application will be accessible in your web browser, typically at `http://localhost:8501`.

## How to Use

1.  **Enter Log Data**: In the "Log Data" text area, enter the log entries you want to analyze in JSON format.
2.  **Enter Compliance Controls**: In the "Compliance Controls" text area, enter the controls you want to validate against, also in JSON format.
3.  **Generate Report**: Click the "Generate Compliance Report" button.
4.  **View Report**: The generated report, including the narrative, evidence chain, and control mapping, will be displayed below the input fields.