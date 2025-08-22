
# Multi-Agent Zero-Trust System - Essential Scripts and Debugging

This document describes the essential scripts for the multi-agent zero-trust sovereign AI system.

## System Setup
```bash
./system-setup.sh
```
**Purpose**: Install required components
**What it does**:
- Ensure swtpm, tpm2-tools and python packages are setup. (Note: currently tested with WSL linux)

## System Initialization
```bash
./initall.sh
```
**Purpose**: Initialize SWTPM
**What it does**:
- Ensure TPM is setup properly and TPM AK is created
- Note: These software versions have been tested on Ubuntu Linux 22.04 and Windows Subsystem for Linux

## 🚀 Utils

### 1. Start All Services
```bash
python start_services.py
```
**Purpose**: Starts all microservices (agent, gateway, collector)
**What it does**: 
- Checks if agent-001 exists, creates it if not
- Starts agent-001 on port 8401
- Starts gateway on port 9000  
- Starts collector on port 8500

OR start individually
```bash
PORT=8500 python collector/app.py
PORT=9000 python gateway/app.py
python create_agent.py agent-001
python start_agent.py agent-001
```

### 2. Test End-to-End Flow
```bash
./test_end_to_end_flow.sh
```
**Purpose**: Tests the complete end-to-end flow using curl commands
**What it does**: 
- Checks if all services are running
- Tests the complete agent → gateway → collector flow
- Shows system status and security features

## 🔧 Agent Management

### Create New Agent
```bash
python create_agent.py agent-002
```
**Purpose**: Creates a new agent with full setup
**What it does**:
- Creates agent configuration
- Generates TPM2 keys
- Adds agent to collector allowlist
- Sets up agent-specific files

### Delete Agent
```bash
python delete_agent.py agent-002
```
**Purpose**: Removes an agent and cleans up files
**What it does**:
- Removes agent configuration
- Deletes TPM2 context files
- Removes agent from allowlist

### Manage Agents
```bash
python manage_agents.py
```
**Purpose**: Interactive agent management
**What it does**:
- List all agents
- Create new agents
- Delete agents
- Show agent status

### Cleanup All Agents
```bash
./cleanup_all_agents.sh [--force]
```
**Purpose**: Removes all existing agents from the system
**What it does**:
- Deletes all agent directories
- Removes agent-specific TPM files
- Resets collector allowlist
- Cleans up temporary files
- Preserves default TPM files

**Options**:
- `--force` or `-f`: Skip confirmation prompt
- `--help` or `-h`: Show usage information

**Examples**:
```bash
./cleanup_all_agents.sh          # Interactive mode with confirmation
./cleanup_all_agents.sh --force  # Force cleanup without confirmation
```

## 🎯 Key Commands

```bash
# Test the complete system
./test_end_to_end_flow.sh

# Test agent-001 critical flow
curl -X POST "https://localhost:8401/metrics/generate" \
  -H "Content-Type: application/json" \
  -d '{"metric_type": "application"}' \
  --insecure

# Start all services
python start_services.py

# Create a new agent
python create_agent.py agent-002

# Start a specific agent
python start_agent.py agent-001

# Clean up all agents
./cleanup_all_agents.sh --force

# Run comprehensive tests
python test_summary.py

# Check agent allowlist
cat collector/allowed_agents.json
```

## 🐛 Debug Logging

For detailed debugging and troubleshooting, the system supports environment variable controls:

### Quick Debug Examples
```bash
# Debug all components
DEBUG_ALL=true python start_services.py

# Debug specific components
DEBUG_AGENT=true python agent/app.py
DEBUG_COLLECTOR=true python collector/app.py
DEBUG_GATEWAY=true python gateway/app.py

# Debug individual agent
DEBUG_AGENT=true python start_agent.py agent-001
```

### Environment Variables
- `DEBUG_ALL=true` - Enable debug for all components
- `DEBUG_AGENT=true` - Enable debug for agent only
- `DEBUG_COLLECTOR=true` - Enable debug for collector only
- `DEBUG_GATEWAY=true` - Enable debug for gateway only

See [DEBUG_LOGGING.md](DEBUG_LOGGING.md) for complete documentation.

## 📝 Notes

- All services use HTTPS with self-signed certificates
- TPM2 operations require WSL environment
- Agent configurations are stored in `agents/` directory
- Collector allowlist is in `collector/allowed_agents.json`
- Debug logging can be controlled via environment variables


# Debug Logging Guide

This document explains how to control debug logging for the multi-agent zero-trust system.

## Environment Variables

The system supports several environment variables to control debug logging:

### Global Debug Control
- `DEBUG_ALL=true` - Enables debug logging for ALL components

### Individual Component Debug Control
- `DEBUG_AGENT=true` - Enables debug logging for the Agent only
- `DEBUG_COLLECTOR=true` - Enables debug logging for the Collector only  
- `DEBUG_GATEWAY=true` - Enables debug logging for the Gateway only

### Output Control
- `QUIET_MODE=true` - Reduces service output noise in start_services.py

## Usage Examples

### 1. Start All Services with Debug Logging

```bash
# Enable debug for all components
DEBUG_ALL=true python start_services.py

# Or enable debug for specific components
DEBUG_AGENT=true DEBUG_COLLECTOR=true python start_services.py

# Reduce service output noise
QUIET_MODE=true python start_services.py

# Combine debug and quiet mode
DEBUG_ALL=true QUIET_MODE=true python start_services.py
```

### 2. Start Individual Components with Debug Logging

```bash
# Start agent with debug logging
DEBUG_AGENT=true python agent/app.py

# Start collector with debug logging  
DEBUG_COLLECTOR=true python collector/app.py

# Start gateway with debug logging
DEBUG_GATEWAY=true python gateway/app.py
```

### 3. Start Individual Components with Manual Port Setting

```bash
# Agent with debug logging
DEBUG_AGENT=true PORT=8401 python agent/app.py

# Collector with debug logging
DEBUG_COLLECTOR=true PORT=8500 python collector/app.py

# Gateway with debug logging
DEBUG_GATEWAY=true PORT=9000 python gateway/app.py
```

### 4. Start Agent with start_agent.py

```bash
# Start specific agent with debug logging
DEBUG_AGENT=true python start_agent.py agent-001
```

## Log Levels

- **INFO** (default) - Normal operation logs, important events
- **DEBUG** - Detailed debug information, data flow, cryptographic operations

## What Debug Logging Shows

### Agent Debug Logs
- TPM2 initialization and context loading
- Metrics generation details
- Nonce retrieval process
- Data signing steps (digest, signature generation)
- Payload creation and sending
- Geographic region configuration

### Collector Debug Logs
- Public key utilities initialization
- Agent verification process
- Nonce generation and management
- Signature verification steps
- OpenSSL verification details
- Geographic compliance checks

### Gateway Debug Logs
- Request proxying details
- Header and parameter forwarding
- SSL certificate generation
- Health check responses

## Filtered Messages

The following noisy messages are automatically filtered out:
- `Resetting dropped connection` (urllib3)
- `Starting new HTTPS connection` (urllib3)
- `WARNING: This is a development server` (Werkzeug)
- All urllib3 DEBUG messages (in non-debug mode)
- All werkzeug DEBUG messages (in non-debug mode)

## Examples

### Debug All Components
```bash
DEBUG_ALL=true python start_services.py
```

### Debug Only Agent and Collector
```bash
DEBUG_AGENT=true DEBUG_COLLECTOR=true python start_services.py
```

### Debug Individual Component
```bash
DEBUG_AGENT=true python agent/app.py
```

### Test with Debug Logging
```bash
# Start services with debug
DEBUG_ALL=true python start_services.py

# In another terminal, run the test
./test_end_to_end_flow.sh
```

## Troubleshooting

### Too Much Log Output
If debug logging produces too much output, you can:
1. Use specific component debug flags instead of `DEBUG_ALL=true`
2. Filter logs using grep: `DEBUG_AGENT=true python agent/app.py | grep "signature"`
3. Redirect to file: `DEBUG_AGENT=true python agent/app.py > agent_debug.log 2>&1`

### No Debug Output
If you don't see debug output:
1. Verify the environment variable is set correctly: `echo $DEBUG_AGENT`
2. Check that the variable is `true` (case-sensitive)
3. Ensure you're using the correct component flag

### Component-Specific Issues
- **Agent issues**: Use `DEBUG_AGENT=true`
- **Collector verification issues**: Use `DEBUG_COLLECTOR=true`
- **Gateway routing issues**: Use `DEBUG_GATEWAY=true`
- **End-to-end flow issues**: Use `DEBUG_ALL=true`
