# How to Apply the Code Changes

## Step 1: Replace the File

I've created a complete updated version of the file for you:

**File:** `spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go.UPDATED`

### On Your Local Windows Machine:

1. **Backup the original file:**
   ```powershell
   copy spire\pkg\agent\tpmplugin\tpm_plugin_gateway.go spire\pkg\agent\tpmplugin\tpm_plugin_gateway.go.BACKUP
   ```

2. **Replace with the updated version:**
   ```powershell
   copy spire\pkg\agent\tpmplugin\tpm_plugin_gateway.go.UPDATED spire\pkg\agent\tpmplugin\tpm_plugin_gateway.go
   ```

3. **Verify the changes:**
   ```powershell
   type spire\pkg\agent\tpmplugin\tpm_plugin_gateway.go | findstr "crypto/tls"
   type spire\pkg\agent\tpmplugin\tpm_plugin_gateway.go | findstr "RequestQuoteFromAgent"
   ```

   You should see:
   - `"crypto/tls"` in the imports
   - `func (g *TPMPluginGateway) RequestQuoteFromAgent(nonce string) (string, error)`

---

## Step 2: Copy to Remote Machine

### Option A: Using SCP (if you have SSH access)

```powershell
scp spire\pkg\agent\tpmplugin\tpm_plugin_gateway.go dell@172.26.1.77:~/dhanush/hybrid-cloud-poc-backup/spire/pkg/agent/tpmplugin/
```

### Option B: Manual Copy (if no SSH)

1. **On Windows:** Open the file in a text editor
   ```powershell
   notepad spire\pkg\agent\tpmplugin\tpm_plugin_gateway.go
   ```

2. **Select All and Copy** (Ctrl+A, Ctrl+C)

3. **On Remote Linux Machine:** Open the file in an editor
   ```bash
   nano ~/dhanush/hybrid-cloud-poc-backup/spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go
   ```

4. **Delete all content** (Ctrl+K repeatedly or select all and delete)

5. **Paste the new content** (Ctrl+Shift+V or right-click paste)

6. **Save and exit** (Ctrl+O, Enter, Ctrl+X)

---

## Step 3: Verify on Remote Machine

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Check if crypto/tls import is there
grep "crypto/tls" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go

# Check if RequestQuoteFromAgent function is there
grep "RequestQuoteFromAgent" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go

# Should see output like:
# "crypto/tls"
# func (g *TPMPluginGateway) RequestQuoteFromAgent(nonce string) (string, error) {
# func (g *TPMPluginGateway) requestQuoteFromAgentOnce(quoteURL string) (string, error) {
```

---

## Step 4: Rebuild SPIRE Agent on Remote Machine

```bash
cd ~/dhanush/hybrid-cloud-poc-backup/spire

# Clean previous build
make clean

# Build SPIRE Agent
make build

# Verify build succeeded
ls -lh bin/spire-agent
# Should show a file with recent timestamp
```

---

## Step 5: Test the Changes

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Clean up old state
pkill keylime_agent spire-agent keylime-verifier keylime-registrar spire-server tpm2-abrmd 2>/dev/null || true
rm -rf /tmp/keylime-agent /tmp/spire-* /opt/spire/data/* keylime/cv_ca keylime/*.db

# Start control plane
./test_complete_control_plane.sh --no-pause

# Wait for control plane to be ready
sleep 10

# Start agent services
./test_complete.sh --no-pause

# Wait for first attestation
sleep 30

# Check SPIRE Agent logs for quote fetching
tail -50 /tmp/spire-agent.log | grep -i "quote"

# Should see:
# "Unified-Identity - Verification: Requesting quote from rust-keylime agent"
# "Unified-Identity - Verification: Successfully retrieved quote from agent"
# "Unified-Identity - Verification: SovereignAttestation built successfully with quote included"
```

---

## Step 6: Test Multiple Attestations

```bash
# Test 5 attestation cycles
for i in {1..5}; do
    echo "=== Attestation attempt $i ==="
    pkill spire-agent
    sleep 5
    
    # Wait for SPIRE Agent to restart and attest
    sleep 15
    
    # Check if attestation succeeded
    if curl -k https://localhost:8081/health 2>/dev/null | grep -q "ready"; then
        echo "✅ Attestation $i succeeded"
    else
        echo "❌ Attestation $i failed"
    fi
done
```

---

## What Changed in the File

### 1. Added Import
```go
"crypto/tls"  // Line 19 (in imports section)
```

### 2. Modified BuildSovereignAttestation Function
- Added quote fetching before building SovereignAttestation
- Quote is now included in the attestation payload
- Lines ~350-380

### 3. Added Two New Functions
- `RequestQuoteFromAgent(nonce string) (string, error)` - Main function with retry logic
- `requestQuoteFromAgentOnce(quoteURL string) (string, error)` - Helper for single attempt
- Lines ~400-480

---

## Troubleshooting

### Build Error: "undefined: tls"

**Problem:** Import not added correctly

**Solution:** Make sure line 19 has:
```go
"crypto/tls"
```

### Build Error: "RequestQuoteFromAgent undefined"

**Problem:** Function not added

**Solution:** Make sure the two new functions are at the end of the file (after BuildSovereignAttestation)

### Runtime Error: "Failed to get quote from agent"

**Problem:** rust-keylime agent not running

**Solution:**
```bash
# Check agent status
ps aux | grep keylime_agent
curl -k https://localhost:9002/v2.2/agent/version

# If not running, start it
./test_complete.sh --no-pause
```

---

## Success Criteria

You'll know it worked when:

1. ✅ Build completes without errors
2. ✅ SPIRE Agent logs show "Successfully retrieved quote from agent"
3. ✅ SPIRE Agent logs show "SovereignAttestation built successfully with quote included"
4. ✅ Verifier logs do NOT show "Requesting quote from agent"
5. ✅ Multiple attestations work (all 5 succeed)
6. ✅ No "Connection reset by peer" errors

---

## If Something Goes Wrong

### Restore Original File

**On Remote Machine:**
```bash
cd ~/dhanush/hybrid-cloud-poc-backup
cp spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go.BACKUP spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go
cd spire
make build
```

### Check Logs

```bash
# SPIRE Agent
tail -100 /tmp/spire-agent.log

# rust-keylime Agent
tail -100 /tmp/rust-keylime-agent.log

# Keylime Verifier
tail -100 /tmp/keylime-verifier.log
```

---

## Next Steps After Success

1. ✅ Document your findings
2. ✅ Test with different scenarios
3. ✅ Move to Step 2 (CI/CD testing)
4. ✅ Report agent SSL bug to rust-keylime project

---

**Good luck!** 🚀

If you see all 5 attestations succeed, you've completed Step 1!
