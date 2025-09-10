# Edge AI Zero-Trust Demo

This document provides a step-by-step guide to demonstrate the Edge AI zero-trust system with multiple agents and various security scenarios.

## Demo Modes

The system supports two deployment modes with **aligned error handling** and **comprehensive debugging capabilities**:

### **Standard Mode** (Default)
- **Gateway**: Acts as pure proxy, no validation
- **Collector**: Performs all validation (public key, signature, nonce, geolocation)
- **Use Case**: Simpler deployment with centralized validation
- **Error Handling**: All errors returned with consistent format and `rejected_by: "collector"`
- **Debugging**: Complete HTTP header visibility and structured logging

### **Gateway Policy Enforcement Mode** (Cloud Deployment Model)
- **Gateway**: Performs first-layer validation (public key hash, cryptographic signature verification of headers, geographic policy, timestamp)
- **Collector**: Performs second-layer validation (nonce validity, payload signature, end-to-end integrity)
- **Use Case**: Cloud deployment with layered security and faster rejection
- **Error Handling**: All errors returned with consistent format and `rejected_by: "gateway"` or `rejected_by: "collector"`
- **Debugging**: Complete HTTP header visibility and structured logging

**Note**: Both modes provide **aligned error handling** with consistent error response formats, validation types, and detailed error information. The `rejected_by` field clearly indicates which service performed the validation. **Enhanced debugging** provides complete visibility into HTTP headers for policy enforcement troubleshooting with case-insensitive parsing and persistent logging.

**🔐 Gateway Signature Verification Enhancement**: The gateway now performs **full cryptographic signature verification** of the Workload-Geo-ID header using the same TPM2 verification method as the collector. This provides genuine cryptographic security at the gateway layer, not just format validation.



## Pre-requisites (./system-setup.sh will install swtpm, tpm2-tools; check the below steps)
| Environment        | swtpm Version                                              | tpm2-tools Version                                                         | Python Version  |
|--------------------|-----------------------------------------------------------|----------------------------------------------------------------------------|-----------------|
| **RHEL 10.0 (Coughlan)**   | TPM emulator version 0.9.0, Copyright (c) 2014-2022 IBM Corp. and others | tool="tpm2_print" version="5.7" tctis="libtss2-tctildr" tcti-default=tcti-device | Python 3.12.9  |
| **Ubuntu 22.04.5** | TPM emulator version 0.6.3, Copyright (c) 2014-2021 IBM Corp. | tool="flushcontext" version="5.2" tctis="libtss2-tctildr" tcti-default=tcti-device | Python 3.11.13  |
| **WSL**            | TPM emulator version 0.6.3, Copyright (c) 2014-2021 IBM Corp. | tool="flushcontext" version="5.2" tctis="libtss2-tctildr" tcti-default=tcti-device | Python 3.10.12  |
| **Mac mini m4**            | TPM emulator version 0.11.0, Copyright (c) 2014-2022 IBM Corp. and others | tool="tpm2_print" version="5.7-51-geff962d1" tctis="libtss2-tctildr" tcti-default=(null) | Python 3.13.6  |

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
# Linux
./system-setup.sh

# macOS
# build the tools one by one
../swtpm-macos/system-setup-mac-apple.sh

# Append SWTPM environment variables to ~/.bashrc
cat <<'EOF' >> ~/.bashrc

# SWTPM and TPM2TOOLS environment variables
export SWTPM_DIR="$HOME/.swtpm/ztpm"
export SWTPM_PORT=2321
export SWTPM_CTRL=2322
if [[ "$(uname)" == "Darwin" ]]; then
  export TPM2TOOLS_TCTI="libtss2-tcti-swtpm.dylib:host=127.0.0.1,port=${SWTPM_PORT}"
  export DYLD_LIBRARY_PATH="${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
else
  export TPM2TOOLS_TCTI="${TPM2TOOLS_TCTI:-swtpm:host=127.0.0.1,port=${SWTPM_PORT}}"
fi
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

### Option A: Standard Mode (Gateway as Pure Proxy)
```bash
# Start the gateway service with validation disabled (default)
PORT=9000 python gateway/app.py
```

### Option B: Gateway Policy Enforcement Mode (Cloud Deployment Model)
```bash
# Start the gateway service with validation enabled
GATEWAY_VALIDATE_PUBLIC_KEY_HASH=true GATEWAY_VALIDATE_SIGNATURE=true GATEWAY_VALIDATE_GEOLOCATION=true PORT=9000 python gateway/app.py
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

**Expected Response**:
```json
{
  "status": "success",
  "message": "Metrics generated, signed, and sent successfully",
  "payload_id": "1da88c93af68fdbb"
}
```

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

**Expected Error Response (Gateway Policy Enforcement Mode)**:
```json
{
  "status": "error",
  "message": "Failed to send metrics to gateway",
  "details": {
    "error": "Geolocation verification failed",
    "rejected_by": "gateway",
    "validation_type": "geolocation_policy",
    "details": {
      "expected": {"city": "Santa Clara", "country": "US", "state": "California"},
      "received": {"city": "Berlin", "region": "EU", "state": "Germany"},
      "agent_name": "agent-geo-policy-violation-002"
    },
    "timestamp": "2024-01-25T10:30:00Z"
  }
}
```

**Expected Error Response (Standard Mode)**:
```json
{
  "status": "error",
  "message": "Failed to send metrics to gateway",
  "details": {
    "error": "Geolocation verification failed",
    "rejected_by": "collector",
    "validation_type": "geolocation_policy",
    "details": {
      "expected": {"city": "Santa Clara", "country": "US", "state": "California"},
      "received": {"city": "Berlin", "country": "EU", "state": "Germany"},
      "agent_name": "agent-geo-policy-violation-002"
    },
    "timestamp": "2024-01-25T10:30:00Z"
  }
}
```

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

**Expected Error Response (Gateway Policy Enforcement Mode)**:
```json
{
  "error": "Agent not found in allowlist",
  "rejected_by": "gateway",
  "validation_type": "agent_verification",
  "details": {
    "public_key_hash": "cd673d8c6adc3d72d9751dfa61b8cd69b73c4b3ba237aede555d632570697190",
    "validation_type": "public_key_hash",
    "allowlist_status": "not_found"
  },
  "timestamp": "2025-08-27T00:51:19.022333"
}
```

**Expected Error Response (Standard Mode)**:
```json
{
  "status": "error",
  "message": "Failed to send metrics to gateway",
  "details": {
    "error": "Agent not found in allowlist",
    "rejected_by": "collector",
    "validation_type": "agent_verification",
    "details": {
      "public_key_hash": "cd673d8c6adc3d72d9751dfa61b8cd69b73c4b3ba237aede555d632570697190",
      "validation_type": "public_key_hash",
      "allowlist_status": "not_found"
    },
    "timestamp": "2025-08-27T00:51:19.022333"
  }
}
```

---

## Gateway Policy Enforcement Functionality Demo

This section demonstrates the gateway Policy Enforcement functionality in the Cloud Deployment Model.

### Gateway Health Check

**Window 1 - Main Terminal**
```bash
# Check gateway health and allowlist status
curl -k "https://localhost:9000/health"

# Expected response shows:
# - Gateway status: "healthy"
# - Allowlist enabled: true/false
# - Agent count: number of agents in allowlist
# - Validation options: which validations are enabled

**Expected Response (Standard Mode)**:
```json
{
  "status": "healthy",
  "service": "opentelemetry-gateway",
  "version": "1.0.0",
  "gateway_allowlist": {
    "enabled": false,
    "validation_options": {
      "public_key_hash": false,
      "signature": false,
      "geolocation": false
    },
    "agent_count": 2,
    "agents": ["agent-001", "agent-geo-policy-violation-002"]
  },
  "timestamp": "2024-01-25T10:30:00Z"
}
```

**Expected Response (Gateway Policy Enforcement Mode)**:
```json
{
  "status": "healthy",
  "service": "opentelemetry-gateway",
  "version": "1.0.0",
  "gateway_allowlist": {
    "enabled": true,
    "validation_options": {
      "public_key_hash": true,
      "signature": true,
      "geolocation": true
    },
    "agent_count": 2,
    "agents": ["agent-001", "agent-geo-policy-violation-002"]
  },
  "timestamp": "2024-01-25T10:30:00Z"
}
```
```

### Gateway Allowlist Management

**Window 1 - Main Terminal**
```bash
# View current gateway allowlist
cat gateway/allowed_agents.json

# Expected allowlist content:
```json
[
  {
    "agent_name": "agent-001",
    "public_key_hash": "9c85c0ea556fe7227c2965ab19896d95037277871afc342a1bd5c2e046c6a049",
    "geographic_region": "US/California/Santa Clara",
    "created_at": "2024-01-25T10:00:00Z"
  },
  {
    "agent_name": "agent-geo-policy-violation-002",
    "public_key_hash": "abc123def456...",
    "geographic_region": "US/California/Santa Clara",
    "created_at": "2024-01-25T10:05:00Z"
  }
]
```

# Reload gateway allowlist (if needed)
curl -X POST -k "https://localhost:9000/reload-allowlist"

# Expected reload response:
```json
{
  "status": "success",
  "message": "Gateway allowlist reloaded successfully",
  "agent_count": 2,
  "agents": ["agent-001", "agent-geo-policy-violation-002"],
  "timestamp": "2024-01-25T10:30:00Z"
}
```

# Check allowlist after reload
curl -k "https://localhost:9000/health"
```

### Gateway Validation Testing

#### Test 1: Gateway Policy Enforcement Mode vs Standard Mode

**Window 1 - Main Terminal**
```bash
# Stop current gateway (Ctrl+C in Window 3)

# Start gateway in Standard Mode (validation disabled)
PORT=9000 python gateway/app.py

# Test agent-001 (should work - gateway acts as pure proxy)
curl -X POST "https://localhost:8401/metrics/generate" \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "application"}' \
  --insecure

**Expected Response (Standard Mode)**:
```json
{
  "status": "success",
  "message": "Metrics generated, signed, and sent successfully",
  "payload_id": "1da88c93af68fdbb"
}
```

# Stop gateway and start in Gateway Policy Enforcement Mode
GATEWAY_VALIDATE_PUBLIC_KEY_HASH=true GATEWAY_VALIDATE_SIGNATURE=true GATEWAY_VALIDATE_GEOLOCATION=true PORT=9000 python gateway/app.py

# Test agent-001 again (should work - gateway validates and forwards)
curl -X POST "https://localhost:8401/metrics/generate" \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "application"}' \
  --insecure

**Expected Response (Gateway Policy Enforcement Mode)**:
```json
{
  "status": "success",
  "message": "Metrics generated, signed, and sent successfully",
  "payload_id": "1da88c93af68fdbb"
}
```
```

#### Test 2: Gateway Geographic Policy Enforcement

**Window 1 - Main Terminal**
```bash
# Ensure gateway is in Policy Enforcement mode
GATEWAY_VALIDATE_PUBLIC_KEY_HASH=true GATEWAY_VALIDATE_SIGNATURE=true GATEWAY_VALIDATE_GEOLOCATION=true PORT=9000 python gateway/app.py

# Test agent-geo-policy-violation-002 (should be rejected by gateway)
curl -X POST "https://localhost:8402/metrics/generate" \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "application"}' \
  --insecure
```

**Expected Result**: In gateway Policy Enforcement mode, the agent should be rejected at the gateway level for geographic policy violation.

**Expected Error Response (Gateway Policy Enforcement Mode)**:
```json
{
  "error": "Geolocation verification failed",
  "rejected_by": "gateway",
  "validation_type": "geolocation_policy",
  "details": {
    "expected": {"city": "Santa Clara", "country": "US", "state": "California"},
    "received": {"city": "Berlin", "region": "EU", "state": "Germany"},
    "agent_name": "agent-geo-policy-violation-002"
  },
  "timestamp": "2025-08-27T21:34:42.813289"
}
```

**Expected Error Response (Standard Mode)**:
```json
{
  "status": "error",
  "message": "Failed to send metrics to gateway",
  "details": {
    "error": "Geolocation verification failed",
    "rejected_by": "collector",
    "validation_type": "geolocation_policy",
    "details": {
      "expected": {"city": "Santa Clara", "country": "US", "state": "California"},
      "received": {"city": "Berlin", "country": "EU", "state": "Germany"},
      "agent_name": "agent-geo-policy-violation-002"
    },
    "timestamp": "2025-08-27T21:34:42.813289"
  }
}
```

#### Test 3: Gateway vs Collector Validation Comparison

**Window 1 - Main Terminal**
```bash
# Check gateway logs for validation details
tail -f logs/gateway.log

# Check collector logs for validation details  
tail -f logs/collector.log

# Compare validation behavior between modes

### Enhanced Debugging and Monitoring

The system provides comprehensive debugging capabilities for end-to-end policy enforcement troubleshooting:

#### **Gateway Header Logging**
The gateway provides complete HTTP header visibility for every API call with case-insensitive parsing:

**Real-time Logs**:
```
INFO:__main__:2025-08-27T21:34:42.812074Z [info     ] 🔍 [GATEWAY] Full relevant headers for policy enforcement debugging
Content-Type=application/json Signature=6e2e9bceda6d96ad8cb9cbb82bd1a6f3ab8880cd9b98230c662adecacda8638f6c15596651fa1ff1d3e3a08d508de79e20582691526e1938778eeb7630febb608511fb1417f5a574a90cda53e491b51e2e0836c49ef925204f720700e57599ae3c7ecc041528a0f834a90883c94b8e3ee220ad6d5172a01c449a3d6e010712dc9c6debebc4aa1db85de836db406dbc085dfca313daa371bb18257e4beaf83cdf5f84e2e413c199e6bdf0ba61f74653c6bc1b64186a9b018ac76411e217942c0e66411a8f9b13c25fd48d4eb56373d992e3fef45627ba5e8ee3bbdb72799ffe72616e20beed057f4e14816c055dcf0b5944c32b34871ceecf9355b5e4b6c2925f Signature-Input=keyid="716d79b029c9c7bf4813fc487eb8e02529475878d8b2024eb2dc6f3424e58baf", created=1756330482, expires=1756330782, alg="RSA" Workload-Geo-ID={"client_workload_id":"agent-001","client_workload_location":{"region":"US","state":"California","city":"Santa Clara"},"client_workload_location_type":"geographic-region","client_workload_location_quality":"GNSS","client_type":"thick"} endpoint=/metrics method=POST
```

**Policy Enforcement Summary**:
```
INFO:__main__:2025-08-27T21:34:42.925596Z [info     ] 📋 [GATEWAY] Policy enforcement header summary
endpoint=/nonce geolocation_header_present=False policy_enforcement_ready=True signature_header_present=False signature_input_present=True
```

**Persistent Logs** (in `logs/gateway_headers.log`):
```json
{
  "ts": "2025-08-27T21:34:42.530442",
  "endpoint": "/metrics",
  "method": "POST",
  "path": "/metrics",
  "query_params": {},
  "headers": {
    "Workload-Geo-ID": "{\"client_workload_id\":\"agent-001\",\"client_workload_location\":{\"region\":\"US\",\"state\":\"California\",\"city\":\"Santa Clara\"},\"client_workload_location_type\":\"geographic-region\",\"client_workload_location_quality\":\"GNSS\",\"client_type\":\"thick\"}",
    "Signature": "6e2e9bceda6d96ad8cb9cbb82bd1a6f3ab8880cd9b98230c662adecacda8638f6c15596651fa1ff1d3e3a08d508de79e20582691526e1938778eeb7630febb608511fb1417f5a574a90cda53e491b51e2e0836c49ef925204f720700e57599ae3c7ecc041528a0f834a90883c94b8e3ee220ad6d5172a01c449a3d6e010712dc9c6debebc4aa1db85de836db406dbc085dfca313daa371bb18257e4beaf83cdf5f84e2e413c199e6bdf0ba61f74653c6bc1b64186a9b018ac76411e217942c0e66411a8f9b13c25fd48d4eb56373d992e3fef45627ba5e8ee3bbdb72799ffe72616e20beed057f4e14816c055dcf0b5944c32b34871ceecf9355b5e4b6c2925f",
    "Signature-Input": "keyid=\"716d79b029c9c7bf4813fc487eb8e02529475878d8b2024eb2dc6f3424e58baf\", created=1756330482, expires=1756330782, alg=\"RSA\"",
    "Content-Type": "application/json",
    "User-Agent": "python-requests/2.31.0",
    "X-Forwarded-For": null,
    "X-Real-IP": null,
    "Host": "localhost:9000",
    "Accept": "*/*",
    "Authorization": null
  }
}
```

#### **Debug Mode Configuration**
The gateway uses INFO level logging by default for clean operation. Enable detailed debug logging when needed:

```bash
# Enable gateway debug logging
export DEBUG_GATEWAY=true

# Start gateway with debug logging
PORT=9000 python gateway/app.py
```

#### **Clean Security Model**
The system implements a clean separation of concerns:
- **HTTP headers**: Agent identification and context only
- **Payload signature**: Actual security validation (with proper nonce)
- **No unnecessary nonces**: Clean HTTP headers without confusing nonce values
- **Clear separation**: No overlap between HTTP headers and payload validation

#### **Consistent Error Handling**
All services provide aligned error responses with:
- **Consistent error formats**: Same structure across all services
- **Enhanced error messages**: Detailed validation information
- **Proper error propagation**: Full error context maintained through the stack
- **Debug-friendly responses**: Rich error details for troubleshooting

### Additional Error Scenarios

#### Invalid Signature Error Response (Gateway Policy Enforcement Mode):
```json
{
  "error": "Workload-Geo-ID signature verification failed",
  "rejected_by": "gateway",
  "validation_type": "signature_verification",
  "details": {
    "agent_name": "agent-001",
    "public_key_hash": "26702138d1490530fbdd6b848ca08d72502cc34e91910350be17fff5ad54477c",
    "validation_type": "signature_validation",
    "error_type": "verification_failed",
    "signature_length": 512
  },
  "timestamp": "2024-01-25T10:30:00Z"
}
```

#### Unregistered Agent Error Response (Gateway Policy Enforcement Mode):
```json
{
  "error": "Agent not found in allowlist",
  "rejected_by": "gateway",
  "validation_type": "agent_verification",
  "details": {
    "public_key_hash": "cd673d8c6adc3d72d9751dfa61b8cd69b73c4b3ba237aede555d632570697190",
    "validation_type": "public_key_hash",
    "allowlist_status": "not_found"
  },
  "timestamp": "2025-08-27T00:51:19.022333"
}
```

#### Timestamp Proximity Error Response (Gateway Policy Enforcement Mode):
```json
{
  "error": "Request timestamp too far from gateway time",
  "rejected_by": "gateway",
  "validation_type": "request_validation",
  "timestamp": "2024-01-25T10:30:00Z"
}
```

#### Nonce Validation Error Response (Collector Only):
```json
{
  "status": "error",
  "message": "Failed to send metrics to gateway",
  "details": {
    "error": "Agent not found in allowlist",
    "rejected_by": "collector",
    "validation_type": "agent_verification",
    "details": {
      "public_key_hash": "cd673d8c6adc3d72d9751dfa61b8cd69b73c4b3ba237aede555d632570697190",
      "validation_type": "public_key_hash",
      "allowlist_status": "not_found"
    },
    "timestamp": "2025-08-27T00:51:19.022333"
  }
}
```
```

### Complete End-to-End Test

**Window 1 - Main Terminal**
```bash
# Run the complete end-to-end test with gateway Policy Enforcement
./test_end_to_end_flow.sh gateway-policy-enforcement

# Run the standard end-to-end test
./test_end_to_end_flow.sh
```

**Key Differences to Observe**:
- **Standard Mode**: Gateway acts as pure proxy, all validation at collector
- **Gateway Policy Enforcement Mode**: Gateway performs first-layer validation, collector performs second-layer validation
- **Rejection Points**: Standard mode rejects at collector, gateway Policy Enforcement mode can reject at gateway
- **Validation Speed**: Gateway Policy Enforcement mode provides faster rejection for basic issues

**Aligned Error Handling**:
Both modes now provide **consistent error response formats** with the same structure:
- **`rejected_by` field**: Clearly indicates which service performed the validation
- **`validation_type` field**: Consistent validation type names across both modes
- **`details` structure**: Same detailed error information format
- **`timestamp` field**: ISO format timestamps in all responses

**Critical Validation Check - `rejected_by` Field**:
The `rejected_by` field in error responses is the key indicator of which service performed the validation:
- **`"rejected_by": "collector"`** = Standard Mode (Gateway acts as proxy)
- **`"rejected_by": "gateway"`** = Gateway Policy Enforcement Mode (Gateway performs validation)

This field helps verify that the correct validation flow is being used for each deployment model while maintaining consistent error handling across both modes.

**Expected Test Output (Standard Mode)**:
```
🚀 Testing End-to-End Multi-Agent Zero-Trust Flow (README_demo.md Workflow)
==========================================================================
Trust Boundary: Collector only (gateway acts as pure proxy)
Error Handling: Aligned with Gateway Policy Enforcement Mode

✅ Step 1: Creating agents and starting services...
✅ Step 2: Testing agent scenarios...
✅ Test 2.1: Happy Path - agent-001 (should succeed)
✅ Test 2.2: Geographic Policy Violation - agent-geo-policy-violation-002 (rejected by collector)
✅ Test 2.3: Unregistered Agent - agent-unregistered-003 (rejected by collector)
✅ Step 3: All tests completed successfully
```

**Expected Error Responses to Verify (Standard Mode)**:

**Geographic Policy Violation Response:**
```json
{
  "status": "error",
  "message": "Failed to send metrics to gateway",
  "details": {
    "error": "Geolocation verification failed",
    "rejected_by": "collector",
    "validation_type": "geolocation_policy",
    "details": {
      "expected": {"city": "Santa Clara", "country": "US", "state": "California"},
      "received": {"city": "Berlin", "country": "EU", "state": "Germany"},
      "agent_name": "agent-geo-policy-violation-002"
    },
    "timestamp": "2025-08-27T00:51:19.022333"
  }
}
```

**Unregistered Agent Response:**
```json
{
  "status": "error",
  "message": "Failed to send metrics to gateway",
  "details": {
    "error": "Agent not found in allowlist",
    "rejected_by": "collector",
    "validation_type": "agent_verification",
    "details": {
      "public_key_hash": "cd673d8c6adc3d72d9751dfa61b8cd69b73c4b3ba237aede555d632570697190",
      "validation_type": "public_key_hash",
      "allowlist_status": "not_found"
    },
    "timestamp": "2025-08-27T00:51:19.022333"
  }
}
```

**Expected Test Output (Gateway Policy Enforcement Mode)**:
```
🔐 Testing Gateway Policy Enforcement Functionality (Cloud Deployment Model)
================================================================
Trust Boundary: API Gateway + Collector (same internal network)
Gateway Enforcement: Geolocation, Public Key Hash, Signature, Timestamp
Collector Enforcement: Nonce validity, Payload signature
Error Handling: Aligned with Standard Mode

✅ Step 1: Creating agents and starting services...
✅ Step 2: Testing agent scenarios...
✅ Test 2.1: Happy Path - agent-001 (should succeed)
✅ Test 2.2: Geographic Policy Violation - agent-geo-policy-violation-002 (rejected by gateway)
✅ Test 2.3: Unregistered Agent - agent-unregistered-003 (rejected by gateway)
✅ Step 2.4: Gateway Enforcement Testing (Cloud Deployment Model)...
✅ Test 1: Gateway Health and Allowlist Status
✅ Test 2: Gateway enforcement is working (proven by real agent tests above)
✅ Step 3: All tests completed successfully
```

**Expected Error Responses to Verify (Gateway Policy Enforcement Mode)**:

**Geographic Policy Violation Response:**
```json
{
  "error": "Geolocation verification failed",
  "rejected_by": "gateway",
  "validation_type": "geolocation_policy",
  "details": {
    "expected": {"city": "Santa Clara", "country": "US", "state": "California"},
    "received": {"city": "Berlin", "region": "EU", "state": "Germany"},
    "agent_name": "agent-geo-policy-violation-002"
  },
  "timestamp": "2025-08-27T00:51:19.022333"
}
```

**Unregistered Agent Response:**
```json
{
  "error": "Agent not found in allowlist",
  "rejected_by": "gateway",
  "validation_type": "agent_verification",
  "details": {
    "public_key_hash": "cd673d8c6adc3d72d9751dfa61b8cd69b73c4b3ba237aede555d632570697190",
    "validation_type": "public_key_hash",
    "allowlist_status": "not_found"
  },
  "timestamp": "2025-08-27T00:51:19.022333"
}
```

**Key Validation Points to Check**:
- ✅ **`rejected_by` field**: Should show "gateway" for Gateway Policy Enforcement Mode, "collector" for Standard Mode
- ✅ **`validation_type` field**: Should show appropriate validation type (geolocation_policy, agent_verification, etc.)
- ✅ **`details` structure**: Should contain specific validation details
- ✅ **`timestamp` field**: Should be in ISO format
- ✅ **Error message consistency**: Should match the validation type

**Benefits of Aligned Error Handling**:
- 🔄 **Consistent Debugging**: Same error format across both deployment modes
- 📊 **Unified Monitoring**: Single monitoring system can handle both modes
- 🛠️ **Simplified Development**: Developers work with consistent error structures
- 🔍 **Easier Troubleshooting**: Familiar error format regardless of deployment mode
- 📈 **Better Observability**: Consistent logging and error tracking across modes

## For Utils and Debugging 
Refer [README_utils.md](README_utils.md)


