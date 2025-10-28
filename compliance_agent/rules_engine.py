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

rule_pci_dss_1_2_1 = Rule(
    name="Restrict inbound and outbound...",
    control_mapping="PCI DSS Req. 1.2.1",
    explanation="Restrict inbound and outbound traffic to that which is necessary for the cardholder data environment, and specifically deny all other traffic.",
    # TODO: Implement the validation logic for this rule.
    # Recommended evidence sources: firewall_rules, network_flow_logs
    validation_logic=lambda log: True # Placeholder logic
)

rule_pci_dss_2_1 = Rule(
    name="Always change vendor-supplied defaults...",
    control_mapping="PCI DSS Req. 2.1",
    explanation="Always change vendor-supplied defaults and remove or disable unnecessary default accounts before installing a system on the network.",
    # TODO: Implement the validation logic for this rule.
    # Recommended evidence sources: os_configuration, hardening_checklists
    validation_logic=lambda log: False # Placeholder logic
)

rule_pci_dss_4_2 = Rule(
    name="Never send unprotected PANs...",
    control_mapping="PCI DSS Req. 4.2",
    explanation="Never send unprotected PANs by end-user messaging technologies (for example, e-mail, instant messaging, SMS, chat, etc.).",
    # TODO: Implement the validation logic for this rule.
    # Recommended evidence sources: email_dlp_logs, chat_logs
    validation_logic=lambda log: False # Placeholder logic
)

rule_pci_dss_10_2 = Rule(
    name="Implement automated audit trails...",
    control_mapping="PCI DSS Req. 10.2",
    explanation="Implement automated audit trails for all system components to reconstruct all individual user accesses to cardholder data.",
    # TODO: Implement the validation logic for this rule.
    # Recommended evidence sources: database_audit_logs, os_event_logs, application_logs
    validation_logic=lambda log: False # Placeholder logic
)

# A list of all rules for the engine to use
ALL_RULES = [rule_pci_dss_10_2, rule_pci_dss_4_2, rule_pci_dss_2_1, rule_pci_dss_1_2_1]
