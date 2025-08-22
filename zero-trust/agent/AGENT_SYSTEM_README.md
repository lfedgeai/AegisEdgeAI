# Multi-Agent System for Edge AI

This document describes the new multi-agent system that allows you to run multiple agents with individual configurations, each with their own TPM context files and geolocation settings.

## Overview

The system now supports multiple agents where each agent has:
- **Agent name** (e.g., `agent-001`, `agent-002`)
- **Individual configuration file** with TPM settings and geolocation
- **TPM context file** for signing operations
- **Geolocation information** (country, state, city)
- **Agent-specific allowlist** in the collector

## Architecture Changes

### Before (Single Agent)
```
Agent → Gateway → Collector
```

### After (Multiple Agents)
```
Agent-001 (Santa Clara) → Gateway → Collector
Agent-002 (Austin)      → Gateway → Collector
Agent-003 (New York)    → Gateway → Collector
```

Each agent has its own configuration and the collector maintains an allowlist of all authorized agents.

## Agent Configuration Structure

### Agent Configuration File (`agents/<agent-name>/config.json`)

```json
{
  "agent_name": "agent-001",
  "tpm_public_key_path": "tpm/appsk_pubkey.pem",
  "tpm_context_file": "tpm/app.ctx",
  "geolocation": {
    "country": "US",
    "state": "California",
    "city": "Santa Clara"
  },
  "description": "Primary edge AI agent for Santa Clara deployment",
  "created_at": "2025-08-15T18:00:00Z",
  "status": "active"
}
```

### Collector Allowlist (`collector/allowed_agents.json`)

```json
[
  {
    "agent_name": "agent-001",
    "tpm_public_key_path": "tpm/appsk_pubkey.pem",
    "geolocation": {
      "country": "US",
      "state": "California",
      "city": "Santa Clara"
    },
    "status": "active",
    "created_at": "2025-08-15T18:00:00Z"
  },
  {
    "agent_name": "agent-002",
    "tpm_public_key_path": "tpm/appsk_pubkey.pem",
    "geolocation": {
      "country": "US",
      "state": "Texas",
      "city": "Austin"
    },
    "status": "active",
    "created_at": "2025-08-15T18:00:00Z"
  }
]
```

## Usage

### 1. Creating Agents

Use the agent management script to create new agents:

```bash
# Create a new agent
python manage_agents.py create agent-001 US California "Santa Clara"

# Create another agent
python manage_agents.py create agent-002 US Texas "Austin"

# Create with description
python manage_agents.py create agent-003 US "New York" "New York" --description "NYC edge deployment"
```

### 2. Listing Agents

```bash
# List all configured agents
python manage_agents.py list

# Get information about a specific agent
python manage_agents.py info agent-001
```

### 3. Starting Agents

Start individual agents with their specific configurations:

```bash
# Start agent-001
python start_agent.py agent-001

# Start agent-002
python start_agent.py agent-002

# Start agent-003
python start_agent.py agent-003
```

### 4. Managing the Allowlist

```bash
# Update the collector allowlist with all agent configurations
python manage_agents.py update-allowlist
```

## API Changes

### Agent Payload Format

The signed metrics payload now includes agent information:

```json
{
  "agent_name": "agent-001",
  "tpm_public_key_path": "tpm/appsk_pubkey.pem",
  "geolocation": {
    "country": "US",
    "state": "California",
    "city": "Santa Clara"
  },
  "metrics": {
    "timestamp": "2025-08-15T06:00:00Z",
    "metrics": {...},
    "service": {...}
  },
  "geographic_region": {
    "region": "US",
    "state": "California",
    "city": "Santa Clara"
  },
  "nonce": "...",
  "signature": "...",
  "digest": "...",
  "algorithm": "sha256",
  "timestamp": "2025-08-15T06:00:00Z"
}
```

### New Collector Endpoints

#### List Allowed Agents
```bash
GET /agents
```

Response:
```json
{
  "status": "success",
  "allowed_agents": ["agent-001", "agent-002"],
  "count": 2,
  "timestamp": "2025-08-15T18:00:00Z"
}
```

#### Get Agent Information
```bash
GET /agents/{agent_name}
```

Response:
```json
{
  "status": "success",
  "agent_info": {
    "agent_name": "agent-001",
    "tpm_public_key_path": "tpm/appsk_pubkey.pem",
    "geolocation": {
      "country": "US",
      "state": "California",
      "city": "Santa Clara"
    },
    "status": "active",
    "created_at": "2025-08-15T18:00:00Z"
  },
  "timestamp": "2025-08-15T18:00:00Z"
}
```

## Security Features

### Agent Verification

The collector now verifies:
1. **Agent Name**: Must be in the allowlist
2. **TPM Public Key Path**: Must match the expected path
3. **Geolocation**: Must match the expected location
4. **Signature**: Must be valid for the agent's TPM key

### Verification Flow

```
1. Agent sends signed payload with agent information
2. Collector validates payload structure
3. Collector verifies agent is in allowlist
4. Collector verifies TPM public key path matches
5. Collector verifies geolocation matches
6. Collector verifies signature using public key
7. Collector processes metrics
```

## File Structure

```
edge-ai/
├── agents/
│   ├── agent-001/
│   │   └── config.json
│   ├── agent-002/
│   │   └── config.json
│   └── agent-003/
│       └── config.json
├── collector/
│   ├── allowed_agents.json          # New allowlist format
│   ├── allowed_app_public_keys.json # Old format (deprecated)
│   └── app.py
├── utils/
│   ├── agent_verification_utils.py  # New agent verification
│   ├── public_key_utils.py
│   └── tpm2_utils.py
├── start_agent.py                   # New agent startup script
├── manage_agents.py                 # New agent management script
└── test_agent_system.py            # New test script
```

## Testing

### Run the Complete Test Suite

```bash
# Test the new agent system
python test_agent_system.py
```

This will test:
- Agent configuration loading
- Collector allowlist functionality
- Agent verification
- Multiple agent support
- Complete end-to-end flow

### Individual Tests

```bash
# Test agent management
python manage_agents.py list

# Test agent startup (help)
python start_agent.py --help

# Test collector endpoints
curl https://localhost:8444/agents --insecure
curl https://localhost:8444/agents/agent-001 --insecure
```

## Migration from Single Agent

If you're migrating from the old single-agent system:

1. **Backup your current configuration**
2. **Create agent configurations**:
   ```bash
   python manage_agents.py create agent-001 US California "Santa Clara"
   ```
3. **Update the allowlist**:
   ```bash
   python manage_agents.py update-allowlist
   ```
4. **Start the new agent**:
   ```bash
   python start_agent.py agent-001
   ```

## Environment Variables

The agent startup script automatically sets these environment variables from the agent configuration:

- `AGENT_NAME`: Agent name from config
- `TPM2_APP_CTX_PATH`: TPM context file path
- `PUBLIC_KEY_PATH`: TPM public key path
- `GEOGRAPHIC_REGION`: Country from geolocation
- `GEOGRAPHIC_STATE`: State from geolocation
- `GEOGRAPHIC_CITY`: City from geolocation

## Troubleshooting

### Common Issues

#### Agent Not Found in Allowlist
```
Error: Agent verification failed
```
**Solution**: Make sure the agent is in the allowlist:
```bash
python manage_agents.py update-allowlist
```

#### TPM Context File Not Found
```
Error: TPM2 app context not found
```
**Solution**: Ensure the TPM context file exists and the path is correct in the agent config.

#### Geolocation Mismatch
```
Error: Geolocation verification failed
```
**Solution**: Check that the agent's geolocation in the config matches the allowlist.

#### Agent Configuration Not Found
```
Error: Agent config not found
```
**Solution**: Create the agent configuration:
```bash
python manage_agents.py create <agent-name> <country> <state> <city>
```

### Debugging

Enable debug logging:
```bash
export LOG_LEVEL=DEBUG
python start_agent.py agent-001
```

Check agent verification logs in the collector:
```bash
tail -f logs/collector.log
```

## Best Practices

1. **Unique Agent Names**: Use descriptive, unique names for each agent
2. **Geolocation Accuracy**: Ensure geolocation information is accurate for compliance
3. **TPM Key Management**: Keep TPM context files secure and backed up
4. **Regular Updates**: Update the allowlist when adding/removing agents
5. **Monitoring**: Monitor agent verification logs for security issues

## Future Enhancements

- **Agent Groups**: Group agents by region or function
- **Dynamic Allowlist**: API endpoints to add/remove agents dynamically
- **Agent Health Monitoring**: Track agent status and health
- **Geographic Policies**: More granular geographic compliance rules
- **Agent Rotation**: Automatic TPM key rotation for agents
