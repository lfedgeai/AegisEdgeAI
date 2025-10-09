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
        # Set verbose=False and tune parameters for more deterministic output
        self.llm = Llama(
            model_path=self.model_path,
            n_ctx=n_ctx,
            temperature=0.1, # Lower temperature reduces randomness
            top_p=0.95, # Nucleus sampling to further constrain the model
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
        for _ in range(3): # Try up to 3 times
            output = self.llm(prompt, max_tokens=2048, stop=["\n\n"], echo=False)
            narrative = output['choices'][0]['text'].strip()
            if narrative:
                return narrative

        # If still no narrative after retries, return a default message.
        return "The AI model did not produce a valid narrative for the given evidence."

    def _create_prompt(self, evidence_set, framework_name):
        """
        Creates a refined prompt that instructs the LLM to act as a compliance auditor.
        """
        prompt = (
            f"As an expert compliance auditor, analyze the following evidence and map it to the specific, "
            f"relevant controls within the '{framework_name}' framework. You must provide a "
            f"detailed report that includes a summary of your findings and a clear mapping of "
            f"each piece of evidence to its corresponding control.\n\n"
            f"Evidence to analyze:\n"
        )

        for evidence in evidence_set:
            prompt += f"- Evidence: {json.dumps(evidence)}\n"

        prompt += (
            "\nGenerate a compliance report with the following sections:\n"
            "1. **Summary of Findings:** A brief overview of your conclusions.\n"
            "2. **Control Mapping:** A clear mapping of each piece of evidence to a specific control from the framework.\n"
            "3. **Explanation:** A brief justification for each mapping.\n"
            "\n**Compliance Report:**"
        )
        return prompt