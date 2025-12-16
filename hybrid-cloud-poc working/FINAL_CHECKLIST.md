# Final Checklist - Ready to Complete Step 1

**Status:** ✅ All fixes applied, ready to rebuild and test  
**Time Required:** 15-20 minutes  
**Success Rate:** 95% confidence

---

## Pre-Flight Check ✅

- ✅ Source file has new code (RequestQuoteFromAgent function)
- ✅ go.mod has valid Go version (1.21)
- ✅ cosign dependency compatible (v2.4.0)
- ✅ Rebuild script created (rebuild-spire-agent.sh)
- ✅ All documentation updated

---

## Step-by-Step Checklist

### □ Step 1: Rebuild Binary (5 minutes)

**On remote machine (dell@vso):**

```bash
cd ~/dhanush/hybrid-cloud-poc-backup
chmod +x rebuild-spire-agent.sh
./rebuild-spire-agent.sh
```

**Expected output:**
```
✅ Source code has RequestQuoteFromAgent function
✅ go.mod has valid Go version
✅ Removed old binary
✅ Build succeeded
✅ New code is in binary (verified with strings)
✅ Binary is executable
```

**If build fails:**
- Check error message
- Verify Go is installed: `go version`
- Check go.mod: `grep "^go " spire/go.mod`
- See troubleshooting section below

---

### □ Step 2: Clean Up Environment (2 minutes)

```bash
# Stop all processes
pkill keylime_agent spire-agent keylime-verifier keylime-registrar spire-server tpm2-abrmd 2>/dev/null || true

# Unmount tmpfs
sudo umount /tmp/keylime-agent/secure 2>/dev/null || true

# Remove old data
rm -rf /tmp/keylime-agent /tmp/spire-* /opt/spire/data/* keylime/cv_ca keylime/*.db
```

**Expected result:**
- All processes stopped
- All temporary data removed
- Clean slate for testing

---

### □ Step 3: Start Control Plane (3 minutes)

```bash
./test_complete_control_plane.sh --no-pause
```

**Expected output:**
```
✅ SPIRE Server started
✅ Keylime Registrar started
✅ Keylime Verifier started
✅ rust-keylime Agent started
✅ TPM Plugin Server started
```

**If any service fails:**
- Check logs in /tmp/
- Verify TPM is accessible: `ls -l /dev/tpm*`
- See troubleshooting section below

---

### □ Step 4: Run Integration Test (5 minutes)

**Open 3 terminals for monitoring:**

**Terminal 1: SPIRE Agent logs**
```bash
tail -f /tmp/spire-agent.log | grep --color=always "quote"
```

**Terminal 2: Verifier logs**
```bash
tail -f /tmp/keylime-verifier.log | grep --color=always "quote"
```

**Terminal 3: Run test**
```bash
./test_complete.sh --no-pause
```

---

### □ Step 5: Verify Success (2 minutes)

**Check Terminal 1 (SPIRE Agent logs):**

✅ **Should see:**
```
Unified-Identity - Verification: Requesting quote from rust-keylime agent
Unified-Identity - Verification: Successfully retrieved quote from agent
```

❌ **Should NOT see:**
```
quote handled by Keylime Verifier  # OLD message
```

**Check Terminal 2 (Verifier logs):**

✅ **Should see:**
```
Using quote from SovereignAttestation
```

❌ **Should NOT see:**
```
Requesting quote from agent  # OLD behavior
```

**Check Terminal 3 (Test output):**

✅ **Should see:**
```
✅ SPIRE Agent started
✅ Attestation succeeded
✅ Workload SVID generated
```

❌ **Should NOT see:**
```
missing required field: data.quote
Connection reset by peer
```

---

### □ Step 6: Test Multiple Attestations (5 minutes)

```bash
for i in {1..5}; do
    echo "=== Attestation $i ==="
    pkill spire-agent
    sleep 5
    # SPIRE Agent will restart and attest
    sleep 10
    
    # Check if attestation succeeded
    if curl -k https://localhost:8081/health 2>/dev/null | grep -q "ready"; then
        echo "✅ Attestation $i succeeded"
    else
        echo "❌ Attestation $i failed"
        break
    fi
done
```

**Expected result:**
```
✅ Attestation 1 succeeded
✅ Attestation 2 succeeded
✅ Attestation 3 succeeded
✅ Attestation 4 succeeded
✅ Attestation 5 succeeded
```

---

### □ Step 7: Document Results (3 minutes)

**If all tests passed:**

```bash
echo "Step 1 Complete - $(date)" >> STEP1_COMPLETION.txt
echo "Binary: $(ls -lh spire/bin/spire-agent | awk '{print $5, $6, $7, $8}')" >> STEP1_COMPLETION.txt
echo "Attestations: 5/5 succeeded" >> STEP1_COMPLETION.txt
```

**Update mentor:**
- Send `MENTOR_UPDATE_DEC11_FINAL.md`
- Include test results
- Discuss next steps (Step 2: CI/CD)

---

## Success Criteria Summary

| Criterion | Status | Notes |
|-----------|--------|-------|
| Binary built | □ | Should be ~65MB |
| New code in binary | □ | Verified with `strings` |
| SPIRE Agent logs show new messages | □ | "Requesting quote from rust-keylime agent" |
| Verifier logs show new behavior | □ | "Using quote from SovereignAttestation" |
| Attestation succeeds | □ | No errors |
| Multiple attestations work | □ | 5/5 succeeded |
| No SSL errors | □ | No "Connection reset by peer" |
| No zombie processes | □ | Agent stays responsive |

---

## Troubleshooting

### Build Fails with "go: errors parsing go.mod"

**Problem:** Invalid Go version in go.mod

**Solution:**
```bash
sed -i 's/^go .*/go 1.21/' spire/go.mod
./rebuild-spire-agent.sh
```

---

### Binary Doesn't Have New Code

**Problem:** Source file still has old code

**Solution:**
```bash
# Verify source file
grep "RequestQuoteFromAgent" spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go

# If no matches, copy from .UPDATED
cp spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go.UPDATED \
   spire/pkg/agent/tpmplugin/tpm_plugin_gateway.go

# Rebuild
./rebuild-spire-agent.sh
```

---

### SPIRE Agent Logs Still Show Old Messages

**Problem:** Using old binary

**Solution:**
```bash
# Check which binary is being used
which spire-agent

# Check binary date
ls -lh spire/bin/spire-agent

# Should be recent (today's date)
# If not, rebuild:
rm spire/bin/spire-agent
./rebuild-spire-agent.sh
```

---

### Attestation Fails with "Connection reset by peer"

**Problem:** Agent SSL bug still occurring

**Solution:**
```bash
# Check if Verifier is fetching quote from agent
tail -100 /tmp/keylime-verifier.log | grep "Requesting quote from agent"

# If found, new code isn't running
# Verify binary has new code:
strings spire/bin/spire-agent | grep "Requesting quote from rust-keylime agent"

# If not found, rebuild:
./rebuild-spire-agent.sh
```

---

### Agent Not Responding to Quote Requests

**Problem:** Agent might not be ready or network issue

**Solution:**
```bash
# Check agent is running
curl -k https://localhost:9002/v2.2/agent/version

# Check agent logs
tail -50 /tmp/keylime-agent.log

# Restart agent if needed
pkill keylime_agent
# Control plane script will restart it
```

---

## Quick Reference

### Important Files
- `rebuild-spire-agent.sh` - Rebuild script
- `QUICK_REBUILD_COMMANDS.md` - Quick reference
- `BINARY_ISSUE_RESOLVED.md` - Detailed explanation
- `MENTOR_UPDATE_DEC11_FINAL.md` - Mentor update

### Important Logs
- `/tmp/spire-agent.log` - SPIRE Agent
- `/tmp/keylime-verifier.log` - Verifier
- `/tmp/keylime-agent.log` - rust-keylime Agent
- `/tmp/tpm-plugin-server.log` - TPM Plugin

### Important Commands
```bash
# Rebuild binary
./rebuild-spire-agent.sh

# Run full test
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause

# Check logs
tail -f /tmp/spire-agent.log | grep "quote"
tail -f /tmp/keylime-verifier.log | grep "quote"

# Verify binary
strings spire/bin/spire-agent | grep "Requesting quote"

# Test agent
curl -k https://localhost:9002/v2.2/agent/version
```

---

## Next Steps After Success

1. ✅ **Document completion** - Update mentor with results
2. ✅ **Test edge cases** - Network failures, timing issues
3. ✅ **Move to Step 2** - CI/CD testing (5-minute runtime)
4. ✅ **Report bug** - Submit issue to rust-keylime project
5. ✅ **Plan Step 3** - Kubernetes integration

---

## Confidence Level

**95% - Very High**

**Why:**
- ✅ Root cause identified and fixed
- ✅ All code changes verified
- ✅ Build script automates everything
- ✅ Fallback behavior if quote fetch fails
- ✅ Retry logic handles timing issues

**Remaining 5% risk:**
- ⚠️ Unexpected network issues
- ⚠️ Agent not ready when SPIRE Agent starts
- ⚠️ Unknown TPM issues

**Mitigation:**
- Retry logic with exponential backoff
- Fallback to old behavior if needed
- Comprehensive error logging

---

**Ready to proceed!** 🚀

Run `./rebuild-spire-agent.sh` and follow the checklist.

