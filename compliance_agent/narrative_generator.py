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
        Generates a compliance narrative using a few-shot prompt.

        :param evidence_set: A list of structured evidence.
        :param framework_name: The name of the compliance framework.
        :return: A string containing the generated narrative.
        """
        prompt = self._create_prompt(evidence_set, framework_name)

        # A single attempt should be sufficient with a few-shot prompt.
        output = self.llm(prompt, max_tokens=2048, stop=["\n\n"], echo=False)
        narrative = output['choices'][0]['text'].strip()

        if not narrative:
            return "The AI model did not produce a valid narrative for the given evidence."

        return narrative

    def _create_prompt(self, evidence_set, framework_name):
        """
        Creates a few-shot prompt to guide the LLM's response.
        """
        # Hardcoded example for the few-shot prompt
        example_evidence = json.dumps([{
            "evidence_type": "log_entry",
            "timestamp": "2024-10-09T10:00:00Z",
            "source": "firewall",
            "excerpt": {"action": "deny", "src_ip": "10.0.0.5", "dest_ip": "8.8.8.8"},
            "matched_rules": ["rule_deny_all_egress"],
            "hashes": {"sha256": "..."}
        }])

        example_report = (
            "**Compliance Report:**\n\n"
            "**1. Summary of Findings:**\n"
            "The evidence indicates that the firewall is correctly configured to deny all egress traffic by default, which is a key security best practice.\n\n"
            "**2. Control Mapping:**\n"
            "The firewall log showing a 'deny' action maps directly to **PCI DSS Requirement 1.2.1**, which requires restricting inbound and outbound traffic to only that which is necessary.\n\n"
            "**3. Explanation:**\n"
            "The firewall's denial of outbound traffic demonstrates enforcement of a restrictive access control policy, aligning with the principle of least privilege required by PCI DSS."
        )

        # The actual prompt for the current request
        current_evidence = "\n".join([f"- Evidence: {json.dumps(e)}" for e in evidence_set])

        prompt = (
            f"You are an expert compliance auditor. Your task is to analyze the provided evidence and map it to the specific, "
            f"relevant controls within the given framework. Follow the format of the example below.\n\n"
            f"--- EXAMPLE START ---\n"
            f"Framework: PCI DSS\n"
            f"Evidence to analyze:\n- Evidence: {example_evidence}\n\n"
            f"{example_report}\n"
            f"--- EXAMPLE END ---\n\n"
            f"Now, generate a report for the following request:\n"
            f"Framework: {framework_name}\n"
            f"Evidence to analyze:\n{current_evidence}\n\n"
            f"**Compliance Report:**"
        )
        return prompt