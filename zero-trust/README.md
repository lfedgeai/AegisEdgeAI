# Edge AI Zero-Trust Demo

This document provides a step-by-step guide to demonstrate the Edge AI zero-trust system with multiple agents and various security scenarios.

## Pre-requisites (./system-setup.sh will install swtpm, tpm2-tools; check the below steps)
| Environment        | swtpm Version                                              | tpm2-tools Version                                                         | Python Version  |
|--------------------|-----------------------------------------------------------|----------------------------------------------------------------------------|-----------------|
| **RHEL 10.0 (Coughlan)**   | TPM emulator version 0.9.0, Copyright (c) 2014-2022 IBM Corp. and others | tool="tpm2_print" version="5.7" tctis="libtss2-tctildr" tcti-default=tcti-device | Python 3.12.9  |
| **Ubuntu 22.04.5** | TPM emulator version 0.6.3, Copyright (c) 2014-2021 IBM Corp. | tool="flushcontext" version="5.2" tctis="libtss2-tctildr" tcti-default=tcti-device | Python 3.11.13  |
| **WSL**            | TPM emulator version 0.6.3, Copyright (c) 2014-2021 IBM Corp. | tool="flushcontext" version="5.2" tctis="libtss2-tctildr" tcti-default=tcti-device | Python 3.10.12  |

###  Command to get swtpm version
```bash
swtpm --version
```
### Command to get tpm2-tools version
```bash
tpm2_print --version
```
### Command to get Python3 version
```bash
python3 --version
```

## Window 1 - Main Terminal
### Install swtpm, tpm2-tools, python packages and initialize system
```bash
./system-setup.sh

# Append SWTPM environment variables to ~/.bashrc
cat <<'EOF' >> ~/.bashrc

# SWTPM and TPM2TOOLS environment variables
export SWTPM_DIR="$HOME/.swtpm/ztpm"
export SWTPM_PORT=2321
export SWTPM_CTRL=2322
export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321"
export EK_HANDLE=0x81010001
export AK_HANDLE=0x8101000A
export APP_HANDLE=0x8101000B
EOF

source ~/.bashrc

# Initialize the system
./initall.sh

# Create test agents
python3 create_agent.py agent-001
python3 create_agent.py agent-geo-policy-violation-002
```

## Window 2 - Collector Service
```bash
# Start the collector service
PORT=8500 python collector/app.py
```

## Window 3 - Gateway Service
```bash
# Start the gateway service
PORT=9000 python gateway/app.py
```

## Window 4 - Agent 001
```bash
# Start the first agent
python start_agent.py agent-001
```

## Window 5 - Agent Geo Policy Violation 002
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

**Window 1 - Main Terminal**
# Test agent-geo-policy-violation-002 metrics generation
curl -X POST "https://localhost:8402/metrics/generate" \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "application"}' \
  --insecure
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

## For Utils and Debugging 
Refer [README_utils.md](README_utils.md)


