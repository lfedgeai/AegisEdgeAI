# Edge AI Zero-Trust Demo

This document provides a step-by-step guide to demonstrate the Edge AI zero-trust system with multiple agents and various security scenarios.

## Setup Instructions

### Window 1 - Main Terminal
```bash
# Initialize the system
./initall.sh

# Create test agents
python3 create_agent.py agent-001
python3 create_agent.py agent-geo-policy-violation-002
```

### Window 2 - Collector Service
```bash
# Start the collector service
PORT=8500 python collector/app.py
```

### Window 3 - Gateway Service
```bash
# Start the gateway service
PORT=9000 python gateway/app.py
```

### Window 4 - Agent 001
```bash
# Start the first agent
python start_agent.py agent-001
```

### Window 5 - Agent Geo Policy Violation
```bash
# Start the second agent (geo policy violation test)
python start_agent.py agent-geo-policy-violation-002
```

## Test Scenarios

### Test 1: Happy Path - Normal Operation

**Window 1 - Main Terminal**
```bash
# Test agent-001 metrics generation
curl -X POST "https://localhost:8401/metrics/generate" \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "application"}' \
  --insecure

# Test agent-geo-policy-violation-002 metrics generation
curl -X POST "https://localhost:8402/metrics/generate" \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "application"}' \
  --insecure
```

**Expected Result**: Both agents should successfully generate and send metrics to the collector. (Note: agent-geo-policy-violation-002 will be tested for policy violations in Test 2)

---

### Test 2: Geographic Policy Violation

This test demonstrates how the system handles agents that violate geographic location policies.

**Window 5 - Agent Terminal**
```bash
# Stop agent 2
# (Use Ctrl+C or kill the process)

# Set geographic policy violation
export AGENT_GEO_POLICY_VIOLATION_002_GEOGRAPHIC_REGION=EU/Germany/Berlin

# Restart agent with policy violation
python start_agent.py agent-geo-policy-violation-002
```

**Expected Result**: The agent should be rejected due to geographic policy violation.

---

### Test 3: Unregistered Agent

This test demonstrates how the system handles agents that are not in the collector's allowlist.

**Window 1 - Main Terminal**
```bash
# Create an unregistered agent
python3 create_agent.py agent-unregistered-003
```

**Window 6 - New Terminal**
```bash
# Start the unregistered agent
python start_agent.py agent-unregistered-003
```

**Window 1 - Main Terminal**
```bash
# Test metrics generation for unregistered agent
curl -X POST "https://localhost:8403/metrics/generate" \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "application"}' \
  --insecure
```

**Expected Result**: The unregistered agent should be rejected by the collector.

## System Architecture

- **Agents**: Edge AI agents running on different ports:
  - `agent-001` (port 8401) - Normal agent
  - `agent-geo-policy-violation-002` (port 8402) - Geographic policy violation test
  - `agent-unregistered-003` (port 8403) - Unregistered agent test
- **Collector**: Central service collecting and validating metrics (port 8500)
- **Gateway**: API gateway for external access (port 9000)
- **TPM**: Trusted Platform Module for secure key management
- **Zero-Trust**: Each agent must be individually authenticated and authorized

## Security Features Demonstrated

1. **Agent Authentication**: TPM-based cryptographic identity verification
2. **Geographic Policy Enforcement**: Location-based access control
3. **Allowlist Management**: Only pre-approved agents can send metrics
4. **Secure Communication**: TLS/SSL encrypted communication channels
5. **Unique Key Management**: Each agent has its own unique TPM keys

## Troubleshooting

- Ensure all services are running before testing
- Check logs for detailed error messages
- Verify TPM setup and key generation
- Confirm network connectivity between services
