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
