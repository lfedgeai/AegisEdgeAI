import json
from llama_cpp import Llama

class NarrativeGenerator:
    def __init__(self, model_path, n_ctx=4096):
        """
        Initializes the NarrativeGenerator with a local LLM.

        :param model_path: Path to the GGUF model file.
        :param n_ctx: The context size for the model.
        """
        self.model_path = model_path
        # Set verbose=False and a low temperature for more deterministic output
        self.llm = Llama(
            model_path=self.model_path,
            n_ctx=n_ctx,
            temperature=0.1, # Lower temperature reduces randomness
            verbose=False
        )

    def generate_narrative(self, evidence_set, framework_name):
        """
        Generates a compliance narrative by having the LLM map evidence to controls.
        Includes a retry mechanism for robustness.

        :param evidence_set: A list of structured evidence.
        :param framework_name: The name of the compliance framework (e.g., "PCI DSS", "HIPAA").
        :return: A string containing the generated narrative.
        """
        prompt = self._create_prompt(evidence_set, framework_name)

        # Retry mechanism to handle occasional empty responses from the LLM
        for _ in range(2): # Try up to 2 times
            output = self.llm(prompt, max_tokens=2048, stop=["\n\n"], echo=False)
            narrative = output['choices'][0]['text'].strip()
            if narrative:
                return narrative

        # If still no narrative after retries, return a default message.
        return "The AI model did not produce a valid narrative for the given evidence."

    def _create_prompt(self, evidence_set, framework_name):
        """
        Creates a prompt that instructs the LLM to act as a compliance auditor.
        """
        prompt = (
            f"You are an expert compliance auditor. Your task is to analyze the provided evidence "
            f"and map it to the specific, relevant controls within the '{framework_name}' framework. "
            f"For each piece of evidence, identify the corresponding control and explain your reasoning.\n\n"
            f"Here is the evidence to analyze:\n"
        )

        for evidence in evidence_set:
            prompt += f"- Evidence: {json.dumps(evidence)}\n"

        prompt += (
            "\nBased on this evidence, please generate a compliance report that includes:\n"
            "1. A summary of your findings.\n"
            "2. A mapping of each piece of evidence to a specific control (e.g., PCI DSS Req. 10.2).\n"
            "3. A brief explanation for each mapping.\n"
            "\nCompliance Report:"
        )
        return prompt