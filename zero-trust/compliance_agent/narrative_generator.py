import json
from llama_cpp import Llama

class NarrativeGenerator:
    def __init__(self, model_path, n_ctx=2048):
        """
        Initializes the NarrativeGenerator with a local LLM.

        :param model_path: Path to the GGUF model file.
        :param n_ctx: The context size for the model.
        """
        # TODO: The model path needs to be configured and the model file needs to be available.
        # This is a placeholder and will need to be replaced with the actual model path.
        self.model_path = model_path
        self.llm = Llama(model_path=self.model_path, n_ctx=n_ctx)

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

if __name__ == '__main__':
    # This is an example of how to use the narrative generator.
    # Note: This will not run without a valid GGUF model file.

    # Example evidence set (from rules_engine.py)
    evidence_set = [
        {
            "evidence_type": "log_entry",
            "timestamp": "2024-01-01T12:00:00Z",
            "source": "kubernetes",
            "excerpt": {
                "timestamp": "2024-01-01T12:00:00Z",
                "source": "kubernetes",
                "host-type": "baremetal",
                "residency": "us-west-2",
                "message": "Pod scheduled successfully."
            },
            "hashes": {
                "sha256": "..."
            }
        }
    ]

    # Example controls
    controls = {
        "HIPAA §164.312(a)(1)": "Access control.",
        "PCI DSS Req. 10.2": "Implement automated audit trails."
    }

    # The path to the model should be specified here.
    # For example: model_path = "./models/ggml-model-q4_0.gguf"
    model_path = None

    if model_path:
        generator = NarrativeGenerator(model_path=model_path)
        narrative = generator.generate_narrative(evidence_set, controls)
        print("Generated Narrative:")
        print(narrative)
    else:
        print("Please specify the path to your GGUF model file to run this example.")