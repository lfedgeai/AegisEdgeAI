import unittest
import json
from unittest.mock import patch

# Use absolute imports, assuming tests are run from the project root
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

        # A valid log should produce one piece of evidence with two matched rules.
        evidence = self.engine.validate_log(log_valid)
        self.assertEqual(len(evidence), 1)
        self.assertEqual(len(evidence[0]['matched_rules']), 2)

        # An invalid log should produce no evidence.
        self.assertEqual(len(self.engine.validate_log(log_invalid)), 0)

    @patch('compliance_agent.app.narrative_generator')
    def test_process_logs_endpoint(self, mock_generator):
        """Test the /process_logs endpoint with the new API format."""
        mock_generator.generate_narrative.return_value = "Mocked narrative about PCI DSS"

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
        self.assertEqual(data['compliance_report']['narrative'], "Mocked narrative about PCI DSS")
        self.assertEqual(data['compliance_report']['framework'], "PCI DSS")
        # Ensure the evidence structure is correct in the API response
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

    def test_empty_narrative_response(self):
        """Test the endpoint's handling of an empty narrative from the LLM."""
        # Mock the narrative generator to return an empty string
        with patch('compliance_agent.app.narrative_generator') as mock_generator:
            mock_generator.generate_narrative.return_value = ""

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
            # Check that the API returns the default message for the narrative
            self.assertEqual(data['compliance_report']['narrative'], "The AI model did not produce a valid narrative for the given evidence.")

if __name__ == '__main__':
    # To run tests, navigate to the project root and run:
    # python -m unittest discover -s compliance_agent
    unittest.main()