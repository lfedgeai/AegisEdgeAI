# Fix: SPIRE Agent Not Creating Workload API Socket

## Root Cause

The SPIRE Agent is failing to attest because:
1. The `unified_identity` node attestor needs to send `SovereignAttestation` to the server
2. `SovereignAttestation` is built using the TPM Plugin CLI script
3. The TPM Plugin CLI script path is not being found when the agent starts
4. Without the TPM Plugin, the agent falls back to stub data
5. The server rejects the stub data and the agent crashes during attestation
6. Because attestation fails, the Workload API socket is never created

## The Fix

You have two options:

### Option 1: Copy tpm_plugin_cli.py to the Default Location (RECOMMENDED)

The SPIRE Agent automatically looks for the TPM Plugin CLI in these locations:
1. `/tmp/spire-data/tpm-plugin/tpm_plugin_cli.py`
2. `$HOME/AegisEdgeAI/hybrid-cloud-poc/tpm-plugin/tpm_plugin_cli.py`

**You already did this earlier!** Run this command again to make sure:

```bash
cp ~/dhanush/hybrid-cloud-poc-backup/tpm-plugin/tpm_plugin_cli.py \
   /tmp/spire-data/tpm-plugin/tpm_plugin_cli.py
chmod +x /tmp/spire-data/tpm-plugin/tpm_plugin_cli.py
```

Then verify it exists:
```bash
ls -la /tmp/spire-data/tpm-plugin/tpm_plugin_cli.py
```

### Option 2: Modify test_complete.sh to Explicitly Pass TPM_PLUGIN_CLI_PATH

If Option 1 doesn't work, modify `test_complete.sh` around line 2290.

**Current code (line 2287-2290):**
```bash
if [ "${UNIFIED_IDENTITY_ENABLED}" = "true" ]; then
    echo "    Using TPM-based proof of residency (unified_identity node attestor)"
    setsid nohup "${SPIRE_AGENT}" run -config "${AGENT_CONFIG}" > /tmp/spire-agent.log 2>&1 &
```

**Change to:**
```bash
if [ "${UNIFIED_IDENTITY_ENABLED}" = "true" ]; then
    echo "    Using TPM-based proof of residency (unified_identity node attestor)"
    echo "    TPM_PLUGIN_CLI_PATH=${TPM_PLUGIN_CLI_PATH}"
    setsid nohup env TPM_PLUGIN_CLI_PATH="${TPM_PLUGIN_CLI_PATH}" TPM_PLUGIN_ENDPOINT="${TPM_PLUGIN_ENDPOINT}" UNIFIED_IDENTITY_ENABLED="${UNIFIED_IDENTITY_ENABLED}" "${SPIRE_AGENT}" run -config "${AGENT_CONFIG}" > /tmp/spire-agent.log 2>&1 &
```

## Testing the Fix

After applying the fix, test it:

```bash
# 1. Stop any running SPIRE Agent
pkill -f spire-agent

# 2. Make sure TPM Plugin Server is running
ps aux | grep tpm_plugin_server.py | grep -v grep

# 3. Verify the CLI script is in place
ls -la /tmp/spire-data/tpm-plugin/tpm_plugin_cli.py

# 4. Start the agent manually to test
cd ~/dhanush/hybrid-cloud-poc-backup
export TPM_PLUGIN_CLI_PATH="/tmp/spire-data/tpm-plugin/tpm_plugin_cli.py"
export TPM_PLUGIN_ENDPOINT="unix:///tmp/spire-data/tpm-plugin/tpm-plugin.sock"
export UNIFIED_IDENTITY_ENABLED="true"

nohup ./spire/bin/spire-agent run -config ./python-app-demo/spire-agent.conf > /tmp/spire-agent.log 2>&1 &

# 5. Wait a few seconds and check the logs
sleep 5
tail -50 /tmp/spire-agent.log | grep -i "unified-identity\|tpm plugin\|workload api"

# 6. Check if the Workload API socket was created
ls -la /tmp/spire-agent/public/api.sock
```

## Expected Output

If the fix works, you should see in the logs:
```
level=info msg="Unified-Identity: TPM plugin client initialized"
level=info msg="Unified-Identity: Built real SovereignAttestation using TPM plugin"
level=info msg="Unified-Identity: Agent Unified SVID renewed"
```

And the socket should exist:
```
srwxr-xr-x 1 dell dell 0 Dec  8 17:00 /tmp/spire-agent/public/api.sock
```

## If It Still Doesn't Work

Check these:

1. **Is the TPM Plugin Server running?**
   ```bash
   ps aux | grep tpm_plugin_server.py | grep -v grep
   netstat -an | grep /tmp/spire-data/tpm-plugin/tpm-plugin.sock
   ```

2. **Can the CLI script connect to the server?**
   ```bash
   /tmp/spire-data/tpm-plugin/tpm_plugin_cli.py /get-app-key
   ```

3. **Check SPIRE Agent logs for errors:**
   ```bash
   tail -100 /tmp/spire-agent.log | grep -i "error\|warn\|fail"
   ```

4. **Check if SPIRE Server is running:**
   ```bash
   ps aux | grep spire-server | grep -v grep
   ls -la /tmp/spire-server/private/api.sock
   ```

## Why This Happens

The `test_complete.sh` script exports `TPM_PLUGIN_CLI_PATH` at line 21, but when it starts the SPIRE Agent with `setsid nohup`, the environment variables might not be inherited properly. The agent then can't find the TPM Plugin CLI script and falls back to stub data, which causes attestation to fail.

By copying the script to `/tmp/spire-data/tpm-plugin/tpm_plugin_cli.py` (one of the default locations the agent checks), the agent can find it automatically without needing the environment variable.
