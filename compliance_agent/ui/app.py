import streamlit as st
import requests
import json

# --- Page Configuration ---
st.set_page_config(
    page_title="AI Compliance Agent UI",
    page_icon="✅",
    layout="wide"
)

# --- App Title ---
st.title("AI Compliance Agent Interface")
st.write("A simple UI to interact with the AI Compliance Agent. Enter your logs and controls below to generate a compliance report.")

# --- API Configuration ---
COMPLIANCE_AGENT_URL = "http://localhost:5001/process_logs"

# --- Default Examples ---
default_logs = """
[
  {
    "timestamp": "2024-01-01T12:00:00Z",
    "source": "kubernetes",
    "host-type": "baremetal",
    "residency": "us-west-2",
    "message": "Pod scheduled successfully on a baremetal node in us-west-2."
  },
  {
    "timestamp": "2024-01-01T12:05:00Z",
    "source": "application",
    "host-type": "vm",
    "residency": "us-east-1",
    "message": "Application failed to start on a virtual machine."
  }
]
"""

default_controls = """
{
  "Data Residency": "All data must be processed on servers located in the US.",
  "Hardware Requirements": "All workloads must run on baremetal servers."
}
"""

# --- Input Fields ---
col1, col2 = st.columns(2)

with col1:
    st.subheader("📋 Log Data")
    st.write("Enter the log entries to be analyzed (in JSON format).")
    logs_input = st.text_area("Logs", value=default_logs, height=300)

with col2:
    st.subheader("📜 Compliance Controls")
    st.write("Enter the compliance controls to validate against (in JSON format).")
    controls_input = st.text_area("Controls", value=default_controls, height=300)

# --- Submit Button and Processing Logic ---
if st.button("Generate Compliance Report", type="primary"):
    if not logs_input or not controls_input:
        st.error("Please provide both logs and controls.")
    else:
        try:
            # Parse the input JSON
            logs_data = json.loads(logs_input)
            controls_data = json.loads(controls_input)

            # Prepare the payload for the API
            payload = {
                "logs": logs_data,
                "controls": controls_data
            }

            # Send the request to the compliance agent API
            with st.spinner("Generating report... This may take a moment."):
                response = requests.post(COMPLIANCE_AGENT_URL, json=payload)

            # Display the result
            st.subheader("Generated Compliance Report")
            if response.status_code == 200:
                report_data = response.json()

                if "compliance_report" in report_data:
                    report = report_data["compliance_report"]

                    st.markdown("### Narrative")
                    st.info(report.get("narrative", "No narrative generated."))

                    st.markdown("### Evidence Chain")
                    st.json(report.get("evidence_chain", []))

                    st.markdown("### Control Mapping")
                    st.json(report.get("control_mapping", {}))
                else:
                    st.json(report_data)

            else:
                st.error(f"Failed to generate report. Status code: {response.status_code}")
                try:
                    st.json(response.json())
                except json.JSONDecodeError:
                    st.text(response.text)

        except json.JSONDecodeError:
            st.error("Invalid JSON format. Please check your input.")
        except requests.exceptions.RequestException as e:
            st.error(f"Failed to connect to the compliance agent at {COMPLIANCE_AGENT_URL}. Please ensure the agent is running. Error: {e}")