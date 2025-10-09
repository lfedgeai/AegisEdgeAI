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
        self.llm = Llama(
            model_path=self.model_path,
            n_ctx=n_ctx,
            temperature=0.2,
            verbose=False
        )

    def generate_narrative(self, evidence_set, framework_name):
        """
        Generates a compliance narrative using a simplified, direct prompt.

        :param evidence_set: A list of structured evidence.
        :param framework_name: The name of the compliance framework.
        :return: A string containing the generated narrative.
        """
        prompt = self._create_prompt(evidence_set, framework_name)

        # Retry mechanism to handle occasional empty responses
        for _ in range(3):
            output = self.llm(prompt, max_tokens=1024, stop=["\n\n"], echo=False)
            narrative = output['choices'][0]['text'].strip()
            if narrative:
                return narrative

        return "The AI model did not produce a valid narrative for the given evidence."

    def _create_prompt(self, evidence_set, framework_name):
        """
        Creates a simple, direct prompt to guide the LLM's response.
        """
        evidence_str = "\n".join([f"- {json.dumps(e)}" for e in evidence_set])

        prompt = (
            f"You are a compliance auditor. Based on the following evidence, "
            f"write a brief summary for a {framework_name} compliance report.\n\n"
            f"Evidence:\n{evidence_str}\n\n"
            f"Summary:"
        )
        return prompt