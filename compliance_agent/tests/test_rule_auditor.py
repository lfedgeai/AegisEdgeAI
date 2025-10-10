import unittest
from unittest.mock import patch, MagicMock

# Use absolute imports, assuming tests are run from the project root
from compliance_agent.rule_auditor import RuleAuditor
from compliance_agent.rules_engine import ALL_RULES

class RuleAuditorTestCase(unittest.TestCase):

    @patch('compliance_agent.rule_auditor.Llama')
    def test_audit_rule_with_consensus(self, MockLlama):
        """
        Tests the RuleAuditor's multi-model consensus logic by mocking the LLM.
        """
        # Configure the mock LLM to return different predictable responses for different models
        mock_mistral = MagicMock()
        mock_mistral.return_value = {'choices': [{'text': 'Mistral assessment.'}]}

        mock_openhermes = MagicMock()
        mock_openhermes.return_value = {'choices': [{'text': 'OpenHermes assessment.'}]}

        mock_zephyr = MagicMock()
        mock_zephyr.return_value = {'choices': [{'text': 'Zephyr assessment.'}]}

        # This will be called for each model loaded in the __init__
        MockLlama.side_effect = [mock_mistral, mock_openhermes, mock_zephyr]

        # We must patch the __init__ to avoid the real model loading and path checking
        with patch.object(RuleAuditor, '__init__', return_value=None) as mock_init:
            auditor = RuleAuditor()
            # Manually set up the mock models and vectorizer
            auditor.models = {
                "Mistral-7B-Instruct-v0.1": mock_mistral,
                "OpenHermes-2.5-Mistral-7B": mock_openhermes,
                "Zephyr-7B-beta": mock_zephyr
            }
            from sklearn.feature_extraction.text import TfidfVectorizer
            auditor.vectorizer = TfidfVectorizer()

            rule_to_test = ALL_RULES[0]

            # Call the audit method
            report = auditor.audit_rule_with_consensus(rule_to_test)

            # Verify the report contains assessments from all three models
            self.assertIn("Assessment from Mistral-7B-Instruct-v0.1", report)
            self.assertIn("Mistral assessment.", report)
            self.assertIn("Assessment from OpenHermes-2.5-Mistral-7B", report)
            self.assertIn("OpenHermes assessment.", report)
            self.assertIn("Assessment from Zephyr-7B-beta", report)
            self.assertIn("Zephyr assessment.", report)

            # Verify that the similarity score is calculated and included
            self.assertIn("Average Pairwise Similarity Score", report)

if __name__ == '__main__':
    unittest.main()