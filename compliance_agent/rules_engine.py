import json
import hashlib
from datetime import datetime

class Rule:
    """
    A class to represent a compliance rule, including its validation logic,
    the control it maps to, and a pre-defined explanation.
    """
    def __init__(self, name, control_mapping, explanation, validation_logic):
        self.name = name
        self.control_mapping = control_mapping
        self.explanation = explanation
        self.validation_logic = validation_logic

    def matches(self, log_entry):
        """Checks if a log entry matches the rule's validation logic."""
        return self.validation_logic(log_entry)

class RulesEngine:
    def __init__(self, rules):
        self.rules = rules

    def validate_log(self, log_entry):
        """
        Validates a single log entry against the defined rules.
        If any rules match, a single evidence entry is created that lists
        all the matched rules and their corresponding details.
        """
        matched_rules_details = []
        for rule in self.rules:
            if rule.matches(log_entry):
                matched_rules_details.append({
                    "rule_name": rule.name,
                    "control_mapping": rule.control_mapping,
                    "explanation": rule.explanation
                })

        if matched_rules_details:
            # Only create one evidence entry, but include details for all matched rules.
            return [self.create_evidence(log_entry, matched_rules_details)]

        return []

    def create_evidence(self, log_entry, matched_rules_details):
        """
        Creates a structured evidence entry from a log entry.
        """
        log_str = json.dumps(log_entry, sort_keys=True)
        log_hash = hashlib.sha256(log_str.encode()).hexdigest()

        return {
            "evidence_type": "log_entry",
            "timestamp": log_entry.get("timestamp", datetime.now().isoformat()),
            "source": log_entry.get("source", "unknown"),
            "excerpt": log_entry,
            "matched_rules": matched_rules_details, # Include the detailed rule info
            "hashes": {
                "sha256": log_hash
            }
        }

# --- Define Specific Compliance Rules ---

rule_host_type = Rule(
    name="Host Type Check",
    control_mapping="PCI DSS Req. 2.1",
    explanation="Ensures that workloads are running on approved hardware types (baremetal).",
    validation_logic=lambda log: log.get("host-type") == "baremetal"
)

rule_residency = Rule(
    name="Data Residency Check",
    control_mapping="PCI DSS Req. 4.2",
    explanation="Verifies that data is processed in approved geographic regions (us-west-2).",
    validation_logic=lambda log: log.get("residency") == "us-west-2"
)

# A list of all rules for the engine to use
ALL_RULES = [rule_host_type, rule_residency]