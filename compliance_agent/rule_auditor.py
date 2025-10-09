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
    def __init__(self, model_path, n_ctx=4096):
        """
        Initializes the RuleAuditor with a local LLM.
        """
        if not model_path or not os.path.exists(model_path):
            raise FileNotFoundError(f"Model file not found at {model_path}. Please run setup_model.py first.")

        self.llm = Llama(
            model_path=model_path,
            n_ctx=n_ctx,
            temperature=0.1,
            verbose=False
        )

    def audit_rule(self, rule):
        """
        Sends a single rule to the LLM for auditing.
        """
        prompt = self._create_prompt(rule)
        output = self.llm(prompt, max_tokens=1024, stop=["\n\n"], echo=False)
        return output['choices'][0]['text'].strip()

    def _create_prompt(self, rule):
        """
        Creates a specialized prompt to ask the LLM to validate a rule.
        """
        # Extract the source code of the validation logic lambda
        validation_logic_src = inspect.getsource(rule.validation_logic)

        prompt = (
            f"You are an expert compliance and code auditor. Your task is to validate the following compliance rule.\n\n"
            f"Rule Name: {rule.name}\n"
            f"Control Mapping: {rule.control_mapping}\n"
            f"Explanation: {rule.explanation}\n"
            f"Validation Logic (Code): {validation_logic_src}\n\n"
            f"Please provide your assessment on the following points:\n"
            f"1. **Semantic Correctness:** Does the `Explanation` accurately describe the intent of the `Control Mapping`?\n"
            f"2. **Code Correctness:** Does the `Validation Logic` code correctly implement the rule's `Explanation`?\n"
            f"3. **Suggestions for Improvement:** Are there any suggestions for improving the rule's clarity or logic?\n\n"
            f"**Audit Assessment:**"
        )
        return prompt

def main():
    """
    Main function to run the rule auditor tool.
    """
    print("--- Starting Compliance Rule Audit ---")

    # Construct the model path relative to the agent's directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    model_path = None
    if settings.llm_model_path:
        model_path = os.path.join(script_dir, settings.llm_model_path)

    try:
        auditor = RuleAuditor(model_path)
    except FileNotFoundError as e:
        print(f"\nError: {e}")
        sys.exit(1)

    for i, rule in enumerate(ALL_RULES, 1):
        print(f"\n--- Auditing Rule {i}/{len(ALL_RULES)}: {rule.name} ---")
        assessment = auditor.audit_rule(rule)
        print(assessment)
        print("-" * (len(rule.name) + 26))

    print("\n--- Compliance Rule Audit Complete ---")

if __name__ == "__main__":
    main()