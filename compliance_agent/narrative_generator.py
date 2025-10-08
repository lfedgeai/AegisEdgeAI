import json
from llama_cpp import Llama

class NarrativeGenerator:
    def __init__(self, model_path, n_ctx=2048):
        """
        Initializes the NarrativeGenerator with a local LLM.

        :param model_path: Path to the GGUF model file.
        :param n_ctx: The context size for the model.
        """
        self.model_path = model_path
        self.llm = Llama(model_path=self.model_path, n_ctx=n_ctx, verbose=False)

    def generate_narrative(self, evidence_set, controls):
        """
        Generates a compliance narrative based on the evidence set and controls.

        :param evidence_set: A list of structured evidence.
        :param controls: A dictionary of compliance controls.
        :return: A string containing the generated narrative.
        """
        prompt = self._create_prompt(evidence_set, controls)

        output = self.llm(prompt, max_tokens=1024, stop=["\n\n"], echo=False)

        return output['choices'][0]['text'].strip()

    def _create_prompt(self, evidence_set, controls):
        """
        Creates a prompt for the LLM based on the evidence and controls.
        """
        prompt = "Generate a compliance narrative based on the following evidence and controls.\n\n"
        prompt += "Controls:\n"
        for control, description in controls.items():
            prompt += f"- {control}: {description}\n"

        prompt += "\nEvidence:\n"
        for evidence in evidence_set:
            prompt += f"- {json.dumps(evidence)}\n"

        prompt += "\nNarrative:"
        return prompt