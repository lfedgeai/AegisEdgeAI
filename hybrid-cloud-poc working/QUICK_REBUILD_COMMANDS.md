# Quick Rebuild Commands - Copy/Paste Ready

**Problem Found:** Source file didn't have new code (copy command didn't work)  
**Solution:** I fixed the source file and go.mod. Now you just need to rebuild.

---

## Copy/Paste These Commands on Remote Machine

```bash
# Navigate to project directory
cd ~/dhanush/hybrid-cloud-poc-backup

# Make rebuild script executable
chmod +x rebuild-spire-agent.sh

# Run rebuild script (does everything automatically)
./rebuild-spire-agent.sh
```

**That's it!** The script will:
- ✅ Verify source code has new changes
- ✅ Fix go.mod if needed
- ✅ Remove old binary
- ✅ Build new binary
- ✅ Verify new code is in binary

---

## After Rebuild: Run Full Test

```bash
# Clean up everything
pkill keylime_agent spire-agent keylime-verifier keylime-registrar spire-server tpm2-abrmd 2>/dev/null || true
sudo umount /tmp/keylime-agent/secure 2>/dev/null || true
rm -rf /tmp/keylime-agent /tmp/spire-* /opt/spire/data/* keylime/cv_ca keylime/*.db

# Start control plane
./test_complete_control_plane.sh --no-pause

# Run integration test
./test_complete.sh --no-pause
```

---

## Verify New Code is Running

**Open 3 terminals:**

**Terminal 1: Watch SPIRE Agent logs**
```bash
tail -f /tmp/spire-agent.log | grep --color=always "quote"
```

**Terminal 2: Watch Verifier logs**
```bash
tail -f /tmp/keylime-verifier.log | grep --color=always "quote"
```

**Terminal 3: Run test**
```bash
./test_complete.sh --no-pause
```

---

## What You Should See

### ✅ SPIRE Agent logs (Terminal 1):
```
Unified-Identity - Verification: Requesting quote from rust-keylime agent
Unified-Identity - Verification: Successfully retrieved quote from agent
```

### ✅ Verifier logs (Terminal 2):
```
Using quote from SovereignAttestation
```

### ❌ You should NOT see:
```
quote handled by Keylime Verifier  # OLD message
Requesting quote from agent        # OLD behavior
```

---

## If It Works

**Congratulations! Step 1 is complete!** 🎉

Test multiple attestations:
```bash
for i in {1..5}; do
    echo "=== Attestation $i ==="
    pkill spire-agent
    sleep 5
    # SPIRE Agent will restart and attest
    sleep 10
    curl -k https://localhost:8081/health 2>/dev/null && echo "✅ Success" || echo "❌ Failed"
done
```

---

## If It Doesn't Work

**Check binary has new code:**
```bash
strings spire/bin/spire-agent | grep "Requesting quote from rust-keylime agent"
```

**If no output, rebuild failed. Check:**
```bash
# Verify source file has new code
grep "RequestQuoteFromAgent" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go

# Check go.mod version
grep "^go " spire/go.mod

# Should show: go 1.21
```

---

## Summary

1. **Run:** `./rebuild-spire-agent.sh`
2. **Test:** `./test_complete.sh --no-pause`
3. **Verify:** Check logs for new messages
4. **Celebrate:** Step 1 complete! 🎉

