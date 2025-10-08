import json
import hashlib
from datetime import datetime

class RulesEngine:
    def __init__(self, rules):
        self.rules = rules

    def validate_log(self, log_entry):
        """
        Validates a single log entry against the defined rules.
        """
        evidence = []
        for rule in self.rules:
            if rule(log_entry):
                evidence.append(self.create_evidence(log_entry))
        return evidence

    def create_evidence(self, log_entry):
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

if __name__ == '__main__':
    # Example usage
    rules = [example_rule_host_type, example_rule_residency]
    engine = RulesEngine(rules)

    # Example log entries
    log1 = {
        "timestamp": "2024-01-01T12:00:00Z",
        "source": "kubernetes",
        "host-type": "baremetal",
        "residency": "us-west-2",
        "message": "Pod scheduled successfully."
    }
    log2 = {
        "timestamp": "2024-01-01T12:05:00Z",
        "source": "application",
        "host-type": "vm",
        "residency": "us-east-1",
        "message": "Application error."
    }

    evidence1 = engine.validate_log(log1)
    evidence2 = engine.validate_log(log2)

    print("Evidence from log 1:")
    print(json.dumps(evidence1, indent=2))

    print("\nEvidence from log 2:")
    print(json.dumps(evidence2, indent=2))