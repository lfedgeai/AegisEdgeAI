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
from compliance_agent.rules_engine import RulesEngine, ALL_RULES
from compliance_agent.report_generator import ReportGenerator # Import the new deterministic generator

app = Flask(__name__)

# Initialize the Rules Engine with the globally defined rules
rules_engine = RulesEngine(ALL_RULES)

# Initialize the new deterministic Report Generator
report_generator = ReportGenerator()

@app.route('/process_logs', methods=['POST'])
def process_logs():
    data = request.get_json()
    logs = data.get('logs', [])
    framework = data.get('framework', 'Unspecified Framework')

    all_evidence = []
    structured_findings = []
    for log in logs:
        evidence = rules_engine.validate_log(log)
        if evidence:
            all_evidence.extend(evidence)
            # Extract the deterministic findings for the report
            for e in evidence:
                structured_findings.extend(e.get('matched_rules', []))

    if not all_evidence:
        return jsonify({"message": "No evidence found based on the provided logs."})

    # Generate the report using the new deterministic generator
    report_text = report_generator.generate_report(framework, structured_findings)

    return jsonify({
        "compliance_report": {
            "report": report_text,
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
