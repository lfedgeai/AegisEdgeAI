import os
import sys
import json
from flask import Flask, request, jsonify

# Add project root to Python path, which is the 'zero-trust' directory
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(script_dir, '..'))
sys.path.insert(0, project_root)

from config import settings
from compliance_agent.rules_engine import RulesEngine, example_rule_host_type, example_rule_residency
from compliance_agent.narrative_generator import NarrativeGenerator

# Get the model path from settings
model_path = settings.llm_model_path

# Check if the model file exists
if model_path and not os.path.exists(model_path):
    print(f"Warning: Model file not found at {model_path}")
    model_path = None
elif model_path:
    print(f"Model file found at {model_path}")
else:
    print("Warning: LLM model path not configured. Narrative generation will be disabled.")

app = Flask(__name__)

# Initialize the Rules Engine
rules = [example_rule_host_type, example_rule_residency]
rules_engine = RulesEngine(rules)

# Initialize the Narrative Generator
narrative_generator = None
if model_path:
    try:
        narrative_generator = NarrativeGenerator(model_path)
    except Exception as e:
        print(f"Warning: Failed to initialize NarrativeGenerator. {e}")

@app.route('/process_logs', methods=['POST'])
def process_logs():
    data = request.get_json()
    logs = data.get('logs', [])
    controls = data.get('controls', {})

    all_evidence = []
    for log in logs:
        evidence = rules_engine.validate_log(log)
        if evidence:
            all_evidence.extend(evidence)

    if not all_evidence:
        return jsonify({"message": "No evidence found based on the provided logs."})

    narrative = "Narrative generation is not available. Please check the model configuration."
    if narrative_generator:
        try:
            narrative = narrative_generator.generate_narrative(all_evidence, controls)
        except Exception as e:
            return jsonify({"error": f"Failed to generate narrative: {e}"}), 500

    return jsonify({
        "compliance_report": {
            "narrative": narrative,
            "evidence_chain": all_evidence,
            "control_mapping": controls
        }
    })

if __name__ == '__main__':
    app.run(
        host=settings.compliance_agent_host,
        port=settings.compliance_agent_port,
        debug=settings.debug
    )