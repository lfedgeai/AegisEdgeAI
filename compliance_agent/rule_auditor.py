import os
import sys
import inspect
import itertools
from llama_cpp import Llama
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

# This block allows the script to be run directly
if __name__ == "__main__" and __package__ is None:
    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    sys.path.insert(0, project_root)

from compliance_agent.config import settings
from compliance_agent.rules_engine import ALL_RULES

class RuleAuditor:
    def __init__(self):
        """
        Initializes the RuleAuditor by loading all configured LLM models.
        """
        self.models = {}
        script_dir = os.path.dirname(os.path.abspath(__file__))

        print("--- Loading LLM Models ---")
        for model_config in settings.llm_models:
            model_name = model_config["name"]
            model_path = os.path.join(script_dir, model_config["path"])

            if not os.path.exists(model_path):
                print(f"Error: Model file for '{model_name}' not found at {model_path}.")
                print("Please run setup_model.py to download the required models.")
                sys.exit(1)

            print(f"Loading model: {model_name}...")
            try:
                self.models[model_name] = Llama(
                    model_path=model_path,
                    n_ctx=4096,
                    temperature=0.1,
                    verbose=False
                )
                print(f"'{model_name}' loaded successfully.")
            except Exception as e:
                print(f"Error: Failed to load model '{model_name}': {e}")
                sys.exit(1)

        if not self.models:
            raise RuntimeError("No LLM models could be loaded. Please check the configuration.")

        self.vectorizer = TfidfVectorizer()

    def audit_rule_with_consensus(self, rule):
        """
        Audits a single rule with all loaded models and calculates the average similarity score.
        """
        assessments = {}
        prompt = self._create_prompt(rule)

        for model_name, llm in self.models.items():
            print(f"  - Getting assessment from {model_name}...")
            output = llm(prompt, max_tokens=1024, stop=["\n\n"], echo=False)
            assessments[model_name] = output['choices'][0]['text'].strip()

        similarity_score = self._calculate_average_similarity(list(assessments.values()))

        return self._format_consensus_report(rule, assessments, similarity_score)

    def _calculate_average_similarity(self, texts):
        """
        Calculates the average pairwise cosine similarity between a list of texts.
        """
        if len(texts) < 2:
            return None # Cannot calculate similarity with fewer than two texts

        # Filter out empty or whitespace-only strings
        valid_texts = [text for text in texts if text and not text.isspace()]
        if len(valid_texts) < 2:
            return 0.0 # Not enough valid texts to compare

        try:
            tfidf_matrix = self.vectorizer.fit_transform(valid_texts)
            # Get all unique pairs of indices
            index_pairs = list(itertools.combinations(range(len(valid_texts)), 2))

            if not index_pairs:
                return 1.0 # Only one valid text, so perfect similarity

            total_similarity = 0
            for i, j in index_pairs:
                total_similarity += cosine_similarity(tfidf_matrix[i:i+1], tfidf_matrix[j:j+1])[0][0]

            return total_similarity / len(index_pairs)
        except ValueError:
            return 0.0

    def _create_prompt(self, rule):
        """
        Creates a specialized prompt to ask the LLM to validate a rule.
        """
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

    def _format_consensus_report(self, rule, assessments, similarity_score):
        """
        Formats the final report showing each model's assessment and the average similarity score.
        """
        report_parts = [f"\n--- Consensus Report for Rule: {rule.name} ---"]

        for model_name, assessment in assessments.items():
            report_parts.append(f"\n--- Assessment from {model_name} ---")
            report_parts.append(assessment if assessment else "No assessment generated.")

        report_parts.append("\n--- Consensus Analysis ---")
        if similarity_score is not None:
            report_parts.append(f"Average Pairwise Similarity Score: {similarity_score:.4f}")
            if similarity_score > 0.8:
                report_parts.append("Conclusion: High degree of consensus among models.")
            elif similarity_score > 0.5:
                report_parts.append("Conclusion: Moderate degree of consensus. Some differences may exist.")
            else:
                report_parts.append("Conclusion: Low degree of consensus. The models have significant disagreements. Manual review is highly recommended.")
        else:
            report_parts.append("Conclusion: A consensus score could not be calculated (fewer than two valid assessments).")

        report_parts.append("-" * (len(rule.name) + 33))
        return "\n".join(report_parts)

def main():
    """
    Main function to run the multi-model rule auditor tool.
    """
    print("--- Starting Multi-Model Compliance Rule Audit ---")

    try:
        auditor = RuleAuditor()
    except (RuntimeError, FileNotFoundError) as e:
        print(f"\nError initializing auditor: {e}")
        sys.exit(1)

    for rule in ALL_RULES:
        consensus_report = auditor.audit_rule_with_consensus(rule)
        print(consensus_report)

    print("\n--- Multi-Model Compliance Rule Audit Complete ---")

if __name__ == "__main__":
    main()