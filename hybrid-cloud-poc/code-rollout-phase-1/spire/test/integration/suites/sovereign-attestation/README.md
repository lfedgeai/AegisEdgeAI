# Sovereign Attestation Integration Test

This test suite validates the end-to-end flow of sovereign attestation handling in SPIRE, including:
- Agent receiving sovereign attestation from workloads
- Agent forwarding sovereign attestation to server
- Server verifying attestation with stubbed Keylime client
- Server evaluating policy against attested claims
- Server granting or denying SVID based on policy evaluation

## Test Flow

1. **Setup**: Start SPIRE Server and Agent with Unified-Identity feature flag enabled
2. **Workload Request**: Simulate a workload request with sovereign attestation
3. **Attestation Processing**: Verify that attestation is processed by Keylime (stubbed)
4. **Policy Evaluation**: Verify policy evaluation results
5. **SVID Issuance**: Verify SVID is issued or denied based on policy

## Requirements

- Unified-Identity feature flag must be enabled
- SPIRE Server and Agent must be configured with sovereign components
- Test environment must support gRPC communication

