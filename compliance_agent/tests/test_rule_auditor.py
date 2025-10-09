import unittest
from unittest.mock import patch, MagicMock

# Use absolute imports, assuming tests are run from the project root
from compliance_agent.rule_auditor import RuleAuditor
from compliance_agent.rules_engine import ALL_RULES

class RuleAuditorTestCase(unittest.TestCase):

    @patch('compliance_agent.rule_auditor.Llama')
    def test_audit_rule_logic(self, MockLlama):
        """
        Tests the RuleAuditor's logic by mocking the LLM.
        """
        # Configure the mock LLM to return a predictable response
        mock_instance = MockLlama.return_value
        mock_instance.return_value = {
            'choices': [{'text': 'This is a mocked one-sentence summary.'}]
        }

        # We must patch the __init__ to avoid the real model loading
        with patch.object(RuleAuditor, '__init__', return_value=None) as mock_init:
            auditor = RuleAuditor()
            auditor.llm = mock_instance # Assign the mock instance

            # We can't easily capture stdout, so we will check the prompt generation
            # and the call to the LLM as a proxy for a full run.

            # Test with the first rule
            rule_to_test = ALL_RULES[0]

            # Generate the prompt that would be sent to the LLM
            prompt = auditor._create_prompt(rule_to_test)

            # Verify the prompt contains the key elements of the rule
            self.assertIn(rule_to_test.name, prompt)
            self.assertIn(rule_to_test.explanation, prompt)
            self.assertIn("Purpose (one sentence):", prompt)

            # Call the audit method
            summary = auditor.audit_rule(rule_to_test)

            # Verify the LLM was called correctly
            mock_instance.assert_called_with(prompt, max_tokens=256, stop=["\n"], echo=False)

            # Verify the output is as expected
            self.assertEqual(summary, "This is a mocked one-sentence summary.")

if __name__ == '__main__':
    unittest.main()