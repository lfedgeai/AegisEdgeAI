class ReportGenerator:
    """
    Generates a deterministic compliance report from structured findings.
    """
    def generate_report(self, framework_name, structured_findings):
        """
        Creates a human-readable report from structured findings using a template.

        :param framework_name: The name of the compliance framework.
        :param structured_findings: A list of dictionaries, each containing a rule name, control mapping, and explanation.
        :return: A string containing the formatted report.
        """
        if not structured_findings:
            return "No compliance issues were found based on the provided logs."

        report_parts = [f"Compliance Report for Framework: {framework_name}\n"]
        report_parts.append("="*40)

        report_parts.append("\nSummary of Findings:")
        for i, finding in enumerate(structured_findings, 1):
            report_parts.append(
                f"  {i}. {finding['rule_name']}: This rule maps to **{finding['control_mapping']}**. "
                f"It is in place to ensure that {finding['explanation'].lower()}"
            )

        report_parts.append("\nConclusion:")
        report_parts.append(
            "The evidence shows that the system is currently enforcing the configured compliance rules. "
            "Each matched rule and its corresponding control are documented above."
        )

        return "\n".join(report_parts)