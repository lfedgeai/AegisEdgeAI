import json
import hashlib
from datetime import datetime

class RulesEngine:
    def __init__(self, rules):
        self.rules = rules

    def validate_log(self, log_entry):
        """
        Validates a single log entry against the defined rules.
        If any rules match, a single evidence entry is created that lists
        all the rules that were matched.
        """
        matched_rules = [rule.__name__ for rule in self.rules if rule(log_entry)]

        if matched_rules:
            # Only create one evidence entry, but list all matched rules.
            return [self.create_evidence(log_entry, matched_rules)]

        return []

    def create_evidence(self, log_entry, matched_rules):
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
            "matched_rules": matched_rules, # Include the list of matched rules
            "hashes": {
                "sha256": log_hash
            }
        }

def example_rule_host_type(log_entry):
    """
    Example rule: Checks if the host-type is baremetal.
    """
    return log_entry.get("host-type") == "baremetal"

def example_rule_residency(log_entry):
    """
    Example rule: Checks if the residency is us-west-2.
    """
    return log_entry.get("residency") == "us-west-2"