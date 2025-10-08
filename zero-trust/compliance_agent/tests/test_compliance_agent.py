import os
import sys
import json
import unittest
from unittest.mock import patch, MagicMock

# Add project root to Python path
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(script_dir, '..', '..'))
sys.path.insert(0, project_root)

from compliance_agent.app import app
from compliance_agent.rules_engine import RulesEngine, example_rule_host_type, example_rule_residency

class ComplianceAgentTestCase(unittest.TestCase):

    def setUp(self):
        """Set up test client and other test variables."""
        app.config['TESTING'] = True
        self.client = app.test_client()
        self.rules = [example_rule_host_type, example_rule_residency]
        self.engine = RulesEngine(self.rules)

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
        self.assertEqual(len(self.engine.validate_log(log_valid)), 2)
        self.assertEqual(len(self.engine.validate_log(log_invalid)), 0)

    def test_process_logs_endpoint(self):
        """Test the /process_logs endpoint with a mock narrative generator."""
        with patch('compliance_agent.app.narrative_generator') as mock_generator:
            mock_generator.generate_narrative.return_value = "Mocked narrative"

            payload = {
                "logs": [
                    {
                        "host-type": "baremetal",
                        "residency": "us-west-2"
                    }
                ],
                "controls": {
                    "test-control": "A test control"
                }
            }

            response = self.client.post('/process_logs', data=json.dumps(payload), content_type='application/json')
            self.assertEqual(response.status_code, 200)
            data = response.get_json()
            self.assertIn("compliance_report", data)
            self.assertEqual(data['compliance_report']['narrative'], "Mocked narrative")

    def test_process_logs_no_evidence(self):
        """Test the /process_logs endpoint when no evidence is found."""
        payload = {
            "logs": [
                {
                    "host-type": "vm",
                    "residency": "us-east-1"
                }
            ],
            "controls": {}
        }

        response = self.client.post('/process_logs', data=json.dumps(payload), content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data['message'], "No evidence found based on the provided logs.")

if __name__ == '__main__':
    unittest.main()