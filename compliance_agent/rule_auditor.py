import os
import sys
import inspect
from llama_cpp import Llama

# This block allows the script to be run directly
if __name__ == "__main__" and __package__ is None:
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    sys.path.insert(0, project_root)

from compliance_agent.config import settings
from compliance_agent.rules_engine import ALL_RULES

class RuleAuditor:
    def __init__(self):
        """
        Initializes the RuleAuditor by loading the configured LLM model.
        """
        script_dir = os.path.dirname(os.path.abspath(__file__))
        # The new config uses a simple path, not a list of models
        model_path = os.path.join(script_dir, settings.llm_model_path)

        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model file not found at {model_path}. Please run setup_model.py first.")

        print("--- Loading LLM Model ---")
        try:
            self.llm = Llama(
                model_path=model_path,
                n_ctx=4096,
                temperature=0.1,
                verbose=False
            )
            print("Model loaded successfully.")
        except Exception as e:
            raise RuntimeError(f"Error loading model: {e}")

    def audit_rule(self, rule):
        """
        Performs a simple, single-task audit on a given rule.
        """
        prompt = self._create_prompt(rule)
        output = self.llm(prompt, max_tokens=256, stop=["\n"], echo=False)
        return output['choices'][0]['text'].strip()

    def _create_prompt(self, rule):
        """
        Creates a simple, direct prompt asking for a one-sentence summary.
        """
        prompt = (
            f"You are a compliance expert. In one sentence, what is the purpose of the following rule?\n\n"
            f"Rule Name: {rule.name}\n"
            f"Control Mapping: {rule.control_mapping}\n"
            f"Explanation: {rule.explanation}\n\n"
            f"Purpose (one sentence):"
        )
        return prompt

def main():
    """
    Main function to run the rule auditor tool.
    """
    print("--- Starting Compliance Rule Sanity Check ---")

    try:
        auditor = RuleAuditor()
    except (RuntimeError, FileNotFoundError) as e:
        print(f"\nError initializing auditor: {e}")
        sys.exit(1)

    for rule in ALL_RULES:
        print(f"\n--- Auditing Rule: {rule.name} ---")
        ai_summary = auditor.audit_rule(rule)

        # The report structure is now deterministic
        print(f"  - Control Mapping: {rule.control_mapping}")
        print(f"  - AI-Generated Summary: {ai_summary if ai_summary else 'No summary generated.'}")
        print("-" * (len(rule.name) + 20))

    print("\n--- Compliance Rule Sanity Check Complete ---")

if __name__ == "__main__":
    main()