import json
from llama_cpp import Llama

class NarrativeGenerator:
    def __init__(self, model_path, n_ctx=4096):
        """
        Initializes the NarrativeGenerator with a local LLM.
        """
        self.model_path = model_path
        self.llm = Llama(
            model_path=self.model_path,
            n_ctx=n_ctx,
            temperature=0.2,
            verbose=False
        )

    def generate_summary(self, framework_name, structured_findings):
        """
        Generates a human-readable summary from structured findings.

        :param framework_name: The name of the compliance framework.
        :param structured_findings: A list of dictionaries, each containing a rule name, control mapping, and explanation.
        :return: A string containing the generated summary.
        """
        prompt = self._create_prompt(framework_name, structured_findings)

        output = self.llm(prompt, max_tokens=1024, stop=["\n\n"], echo=False)
        summary = output['choices'][0]['text'].strip()

        if not summary:
            return "The AI model did not produce a valid summary for the given findings."

        return summary

    def _create_prompt(self, framework_name, structured_findings):
        """
        Creates a simple, direct prompt for summarization.
        """
        findings_str = "\n".join([
            f"- Rule: {finding['rule_name']}\n"
            f"  Control: {finding['control_mapping']}\n"
            f"  Explanation: {finding['explanation']}\n"
            for finding in structured_findings
        ])

        prompt = (
            f"You are a compliance auditor. Based on the following structured findings, "
            f"write a brief, fluent summary for a {framework_name} compliance report.\n\n"
            f"Structured Findings:\n{findings_str}\n\n"
            f"Summary:"
        )
        return prompt