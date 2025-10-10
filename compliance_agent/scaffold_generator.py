import os
import sys
import yaml
from llama_cpp import Llama

# This block allows the script to be run directly
if __name__ == "__main__" and __package__ is None:
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    sys.path.insert(0, project_root)

from compliance_agent.config import settings

class ScaffoldGenerator:
    def __init__(self):
        """
        Initializes the ScaffoldGenerator by loading the configured LLM model.
        """
        script_dir = os.path.dirname(os.path.abspath(__file__))
        # The config now uses a list, but we'll use the first model for this tool.
        model_path = os.path.join(script_dir, settings.llm_models[0]["path"])

        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Model file not found at {model_path}. Please run setup_model.py first.")

        print("--- Loading LLM Model ---")
        try:
            self.llm = Llama(
                model_path=model_path,
                n_ctx=4096,
                temperature=0.2,
                verbose=False
            )
            print("Model loaded successfully.")
        except Exception as e:
            raise RuntimeError(f"Error loading model: {e}")

    def generate_scaffold(self, requirement_id):
        """
        Generates a structured rule scaffold for a given compliance requirement.
        """
        prompt = self._create_prompt(requirement_id)

        for _ in range(3): # Retry up to 3 times for reliability
            output = self.llm(prompt, max_tokens=2048, stop=["---"], echo=False)
            scaffold_text = output['choices'][0]['text'].strip()

            # Basic validation to ensure the output is valid YAML
            try:
                scaffold_data = yaml.safe_load(scaffold_text)
                if isinstance(scaffold_data, dict) and 'name' in scaffold_data:
                    return scaffold_text
            except yaml.YAMLError:
                print("Warning: LLM produced invalid YAML, retrying...")
                continue

        return "# The AI model failed to produce a valid scaffold. Please try again."


    def _create_prompt(self, requirement_id):
        """
        Creates a specialized prompt to ask the LLM to generate a rule scaffold.
        """
        prompt = (
            f"You are an expert in creating 'Compliance as Code' rules. Your task is to generate a structured "
            f"rule scaffold in YAML format for the following compliance requirement: **{requirement_id}**\n\n"
            f"The scaffold must include the following fields:\n"
            f"- **name:** A short, descriptive name for the rule.\n"
            f"- **control_mapping:** The canonical reference for the control.\n"
            f"- **rationale:** A brief explanation of the rule's purpose.\n"
            f"- **evidence_types:** A list of recommended data sources to check (e.g., 'firewall_logs', 'k8s_events').\n"
            f"- **severity:** A hint for the rule's importance (e.g., 'High', 'Medium', 'Low').\n"
            f"- **policy_id:** A placeholder string, like 'POLICY-ID-PENDING'.\n"
            f"- **validation_template:** A commented-out Python code block with suggestions for how a security engineer "
            f"could implement the validation logic. Do not write the final code.\n\n"
            f"Here is an example for 'PCI DSS Req. 1.1.1':\n"
            f"```yaml\n"
            f"name: Firewall Configuration Review\n"
            f"control_mapping: PCI DSS Req. 1.1.1\n"
            f"rationale: Ensures that the firewall configuration is reviewed at least every six months.\n"
            f"evidence_types:\n"
            f"  - firewall_config_change_logs\n"
            f"  - ticketing_system_records\n"
            f"severity: Medium\n"
            f"policy_id: POLICY-ID-PENDING\n"
            f"validation_template: |\n"
            f"  # To implement this rule, you should:\n"
            f"  # 1. Check the last modified date of the firewall configuration file.\n"
            f"  # 2. Query the ticketing system for a corresponding review ticket within the last 6 months.\n"
            f"  # Example logic:\n"
            f"  # last_modified = get_firewall_config_last_modified(log_entry)\n"
            f"  # has_review_ticket = check_ticketing_system(last_modified, '6 months')\n"
            f"  # return has_review_ticket\n"
            f"```\n\n"
            f"Now, generate the YAML scaffold for **{requirement_id}**:\n"
            f"```yaml\n"
        )
        return prompt

def main():
    """
    Main function to run the scaffold generator tool.
    """
    if len(sys.argv) < 2:
        print("Usage: python scaffold_generator.py \"<compliance_requirement_id>\"")
        print("Example: python scaffold_generator.py \"PCI DSS Req. 1.2.1\"")
        sys.exit(1)

    requirement_id = sys.argv[1]

    print(f"--- Generating Rule Scaffold for: {requirement_id} ---")

    try:
        generator = ScaffoldGenerator()
        scaffold = generator.generate_scaffold(requirement_id)
        print("\n--- Generated Scaffold ---")
        print(scaffold)
        print("\n--- End of Scaffold ---")
    except (RuntimeError, FileNotFoundError) as e:
        print(f"\nError: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()