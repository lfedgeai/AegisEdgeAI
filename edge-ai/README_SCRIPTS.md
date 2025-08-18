# Multi-Agent Zero-Trust System - Essential Scripts

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

### Changes to .bashrc
export SWTPM_DIR="$HOME/.swtpm/ztpm"
export SWTPM_PORT=2321
export SWTPM_CTRL=2322
export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321"
export EK_HANDLE=0x81010001
export AK_HANDLE=0x8101000A
export APP_HANDLE=0x8101000B

## 🚀 Quick Start

### 1. Test End-to-End Flow
```bash
./test_end_to_end_flow.sh
```
**Purpose**: Tests the complete end-to-end flow using curl commands
**What it does**: 
- Checks if all services are running
- Tests the complete agent → gateway → collector flow
- Shows system status and security features

### 2. Start All Services
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

### 3. Start Individual Agent
```bash
python start_agent.py agent-001
```
**Purpose**: Starts a specific agent
**What it does**: 
- Loads agent configuration
- Initializes TPM2 utilities
- Starts agent service

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

## 📁 System Architecture

```
Agent (8401) → Gateway (9000) → Collector (8500)
     ↓              ↓              ↓
   TPM Sign    Proxy Headers    Verify & Store
   Nonce Req   Forward Body     Agent Validation
   Geo Check   TLS Terminate    Metrics Processing
```

## 🔐 Security Features

- **TPM2 Hardware Security**: Hardware-backed signing with persistent keys
- **Nonce Anti-Replay**: Unique tokens prevent replay attacks
- **Geographic Compliance**: Data residency enforcement
- **Agent Allowlist**: Centralized agent management
- **OpenSSL Verification**: Remote signature verification

## 📊 Data Flow

1. **Agent generates metrics** with current timestamp
2. **Agent gets nonce** from collector via gateway
3. **Agent signs data** using TPM2 with nonce
4. **Agent sends signed payload** to gateway
5. **Gateway proxies request** to collector
6. **Collector verifies signature** using OpenSSL
7. **Collector validates agent** against allowlist
8. **Collector processes metrics** and returns success

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
