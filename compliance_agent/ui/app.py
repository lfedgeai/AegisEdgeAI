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
st.write("A simple UI to interact with the AI Compliance Agent. Enter your logs and the compliance framework to generate a report.")

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

default_framework = "PCI DSS"

# --- Input Fields ---
col1, col2 = st.columns(2)

with col1:
    st.subheader("📋 Log Data")
    st.write("Enter the log entries to be analyzed (in JSON format).")
    logs_input = st.text_area("Logs", value=default_logs, height=300)

with col2:
    st.subheader("📜 Compliance Framework")
    st.write("Enter the compliance framework to audit against.")
    framework_input = st.text_input("Framework", value=default_framework)

# --- Submit Button and Processing Logic ---
if st.button("Generate Compliance Report", type="primary"):
    if not logs_input or not framework_input:
        st.error("Please provide both logs and a framework.")
    else:
        try:
            # Parse the input JSON
            logs_data = json.loads(logs_input)

            # Prepare the payload for the new API format
            payload = {
                "logs": logs_data,
                "framework": framework_input
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

                    st.markdown("### Audited Framework")
                    st.code(report.get("framework", "N/A"))

                    st.markdown("### Narrative")
                    st.info(report.get("narrative", "No narrative generated."))

                    st.markdown("### Evidence Chain")
                    st.json(report.get("evidence_chain", []))

                else:
                    st.json(report_data)

            else:
                st.error(f"Failed to generate report. Status code: {response.status_code}")
                try:
                    st.json(response.json())
                except json.JSONDecodeError:
                    st.text(response.text)

        except json.JSONDecodeError:
            st.error("Invalid JSON format. Please check your log data.")
        except requests.exceptions.RequestException as e:
            st.error(f"Failed to connect to the compliance agent at {COMPLIANCE_AGENT_URL}. Please ensure the agent is running. Error: {e}")