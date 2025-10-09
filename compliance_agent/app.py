import os
import sys
import json

# This block allows the script to be run directly with `python app.py`
# by adding the project root to the Python path.
if __name__ == "__main__" and __package__ is None:
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    sys.path.insert(0, project_root)

from flask import Flask, request, jsonify

# Use absolute imports from the package root
from compliance_agent.config import settings
from compliance_agent.rules_engine import RulesEngine, example_rule_host_type, example_rule_residency
from compliance_agent.narrative_generator import NarrativeGenerator

# Construct the model path relative to the agent's directory
script_dir = os.path.dirname(os.path.abspath(__file__))
model_path = None
if settings.llm_model_path:
    # The model path in config is relative to the `compliance_agent` directory.
    model_path = os.path.join(script_dir, settings.llm_model_path)

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
    # The API now accepts a high-level framework name
    framework = data.get('framework', 'Unspecified Framework')

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
            # Pass the framework name to the enhanced narrative generator
            narrative = narrative_generator.generate_narrative(all_evidence, framework)
            # Add a final check here to ensure the narrative is not empty
            if not narrative:
                narrative = "The AI model did not produce a valid narrative for the given evidence."
        except Exception as e:
            return jsonify({"error": f"Failed to generate narrative: {e}"}), 500

    return jsonify({
        "compliance_report": {
            "narrative": narrative,
            "evidence_chain": all_evidence,
            "framework": framework
        }
    })

if __name__ == '__main__':
    app.run(
        host=settings.host,
        port=settings.port,
        debug=settings.debug
    )