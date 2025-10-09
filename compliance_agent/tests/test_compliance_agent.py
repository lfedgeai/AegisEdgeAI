import unittest
import json

# Use absolute imports, assuming tests are run from the project root
from compliance_agent.app import app
from compliance_agent.rules_engine import RulesEngine, ALL_RULES
from compliance_agent.report_generator import ReportGenerator

class ComplianceAgentTestCase(unittest.TestCase):

    def setUp(self):
        """Set up test client and other test variables."""
        app.config['TESTING'] = True
        self.client = app.test_client()
        self.engine = RulesEngine(ALL_RULES)
        self.report_generator = ReportGenerator()

    def test_rules_engine_validation(self):
        """Test the rules engine's validation logic."""
        log_valid = {
            "host-type": "baremetal",
            "residency": "us-west-2"
        }
        log_invalid = {
            "host-type": "vm",
            "residency": "us-east-1"
        }

        evidence = self.engine.validate_log(log_valid)
        self.assertEqual(len(evidence), 1)
        self.assertEqual(len(evidence[0]['matched_rules']), 2)
        self.assertEqual(evidence[0]['matched_rules'][0]['control_mapping'], "PCI DSS Req. 2.1")

        self.assertEqual(len(self.engine.validate_log(log_invalid)), 0)

    def test_report_generator(self):
        """Test the deterministic report generator."""
        findings = [
            {"rule_name": "Host Type Check", "control_mapping": "PCI DSS Req. 2.1", "explanation": "Ensures that workloads are running on approved hardware types (baremetal)."},
            {"rule_name": "Data Residency Check", "control_mapping": "PCI DSS Req. 4.2", "explanation": "Verifies that data is processed in approved geographic regions (us-west-2)."}
        ]
        report = self.report_generator.generate_report("PCI DSS", findings)
        self.assertIn("Compliance Report for Framework: PCI DSS", report)
        self.assertIn("Host Type Check", report)
        self.assertIn("Data Residency Check", report)

    def test_process_logs_endpoint(self):
        """Test the /process_logs endpoint with the new deterministic architecture."""
        payload = {
            "logs": [
                {
                    "host-type": "baremetal",
                    "residency": "us-west-2"
                }
            ],
            "framework": "PCI DSS"
        }

        response = self.client.post('/process_logs', data=json.dumps(payload), content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertIn("compliance_report", data)
        # Check for the 'report' field and the correct evidence structure
        self.assertIn("Compliance Report for Framework: PCI DSS", data['compliance_report']['report'])
        self.assertEqual(data['compliance_report']['framework'], "PCI DSS")
        self.assertEqual(len(data['compliance_report']['evidence_chain']), 1)
        self.assertIn('matched_rules', data['compliance_report']['evidence_chain'][0])

    def test_process_logs_no_evidence(self):
        """Test the /process_logs endpoint when no evidence is found."""
        payload = {
            "logs": [
                {
                    "host-type": "vm",
                    "residency": "us-east-1"
                }
            ],
            "framework": "HIPAA"
        }

        response = self.client.post('/process_logs', data=json.dumps(payload), content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data['message'], "No evidence found based on the provided logs.")

if __name__ == '__main__':
    # To run tests, navigate to the project root and run:
    # python -m unittest discover -s compliance_agent
    unittest.main()