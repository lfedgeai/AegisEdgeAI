# rust-keylime Agent SSL Context Corruption - Root Cause Analysis

**Date:** December 10, 2024  
**Status:** Critical Bug - Blocks Step 1 completion at 98%  
**Impact:** Agent can only handle ONE attestation, then SSL breaks

---

## The Bug

After the rust-keylime agent successfully generates a TPM quote, it encounters TPM NV (Non-Volatile) read errors that corrupt its SSL/TLS context. The agent process continues running but can no longer accept SSL connections.

### Symptoms

```bash
# Agent generates quote successfully
INFO keylime::tpm > tpm2_quote completed successfully

# Then TPM errors occur
ERROR: an NV Index is used before being initialized
ERROR: the TPM was unable to unmarshal a value

# Agent stays running (zombie state)
$ ps -p 152200 -o state,cmd
S CMD
S ./rust-keylime/target/release/keylime_agent

# But SSL connections fail
$ curl -k https://localhost:9002/v2.2/agent/version
curl: (16) OpenSSL SSL_write: Connection reset by peer, errno 104
```

---

## Root Cause Analysis

### What Happens (Timeline)

1. ✅ **Agent starts** - SSL context initialized correctly
2. ✅ **Agent registers** with Keylime Registrar
3. ✅ **Delegated certification** - App Key certified by AK
4. ✅ **First quote request** - Verifier asks for quote
5. ✅ **Quote generation** - `tpm2_quote` subprocess succeeds
6. ❌ **TPM NV read errors** - Something tries to read uninitialized NV index
7. ❌ **SSL context corrupted** - Agent's SSL/TLS context becomes invalid
8. ❌ **Connection reset** - All subsequent SSL connections fail

### The TPM NV Read Errors

The errors occur AFTER `tpm2_quote` completes:

```
ERROR: an NV Index is used before being initialized
ERROR: the TPM was unable to unmarshal a value
```

These errors suggest:
- Something is trying to read from TPM Non-Volatile (NV) storage
- The NV index hasn't been initialized yet
- This happens AFTER the quote, not during it

### Why SSL Context Gets Corrupted

**Theory 1: Error Handling Panic**
- The TPM NV read error causes a panic in error handling code
- The panic unwinds through the SSL context
- SSL context is left in invalid state

**Theory 2: Shared State Corruption**
- TPM operations and SSL context share some state (mutex, file descriptor)
- TPM error corrupts this shared state
- SSL context can't recover

**Theory 3: File Descriptor Leak**
- TPM operations open file descriptors to `/dev/tpm0` or `/dev/tpmrm0`
- Error handling doesn't close them properly
- SSL context tries to use corrupted file descriptors

---

## Code Analysis

### SSL Context Initialization (Working)

From `rust-keylime/keylime-agent/src/main.rs`:

```rust
let ssl_context;
if config.enable_agent_mtls {
    ssl_context = Some(crypto::generate_tls_context(
        &cert,
        &mtls_priv,
        ca_certs,
    )?);
}

// Later, bind server with SSL
if config.enable_agent_mtls && ssl_context.is_some() {
    server = actix_server
        .bind_openssl(
            format!("{ip}:{port}"),
            ssl_context.unwrap(),
        )?
        .run();
}
```

The SSL context is created once at startup and used for all connections.

### TPM Quote with tpm2_quote Direct (Where Error Occurs)

From `rust-keylime/keylime/src/tpm.rs`:

```rust
// Execute tpm2_quote command with context file
log::info!("Executing tpm2_quote subprocess with TCTI: {}", tcti);
let output = Command::new("tpm2_quote")
    .env("TCTI", &tcti)
    .arg("-c").arg(ak_context_path)
    .arg("-l").arg(&pcr_list_str)
    .arg("-q").arg(&nonce_hex)
    .arg("-m").arg(quote_msg_path)
    .arg("-s").arg(quote_sig_path)
    .arg("-o").arg(quote_pcrs_path)
    .output()
    .map_err(|e| {
        log::error!("Failed to execute tpm2_quote: {}", e);
        TpmError::HexDecodeError(format!("Failed to execute tpm2_quote: {}", e))
    })?;

log::info!("tpm2_quote completed successfully");
```

The quote succeeds, but AFTER this, something tries to read TPM NV storage.

### What Might Be Reading NV Storage?

Possible culprits:
1. **AK context save/load** - Saving AK context might trigger NV read
2. **TPM cleanup** - Cleanup code might try to read NV indices
3. **Certificate chain read** - Some code might try to read EK cert from NV
4. **State persistence** - Agent might try to save state to TPM NV

---

## Why This Breaks SSL

The SSL context is created at startup and shared across all requests. If ANY error in the agent corrupts shared state (mutexes, file descriptors, memory), the SSL context becomes unusable.

**Key Insight:** The agent uses `actix-web` with `actix-server`. The SSL context is bound to the server at startup. If the TPM error causes:
- A panic that unwinds through the SSL acceptor
- Corruption of shared file descriptors
- Memory corruption in the SSL context

Then all subsequent SSL connections will fail with "Connection reset by peer".

---

## Solutions

### Option 1: Fix TPM NV Read Error (Root Cause Fix)

**Approach:** Find and fix the code that's trying to read uninitialized NV index

**Investigation Steps:**
1. Add debug logging to all TPM NV read operations
2. Identify what's trying to read NV storage after quote
3. Either:
   - Initialize the NV index before reading
   - Skip the NV read if not needed
   - Handle the error gracefully without corrupting SSL

**Files to Investigate:**
- `rust-keylime/keylime/src/tpm.rs` - TPM operations
- `rust-keylime/keylime-agent/src/main.rs` - Agent main loop
- `rust-keylime/keylime-agent/src/quotes_handler.rs` - Quote endpoint handler

**Estimated Effort:** 2-4 days (requires Rust + TPM expertise)

**Benefits:**
- ✅ Proper fix (no workarounds)
- ✅ Production-ready
- ✅ Can contribute back to rust-keylime project

---

### Option 2: Isolate SSL Context from TPM Errors (Defensive Fix)

**Approach:** Ensure TPM errors can't corrupt SSL context

**Implementation:**
1. Wrap all TPM operations in separate error handling
2. Use separate thread/task for TPM operations
3. Ensure SSL context is isolated from TPM state

**Changes Needed:**
```rust
// In quotes_handler.rs
async fn handle_quote_request(...) -> HttpResponse {
    // Spawn separate task for TPM operations
    let tpm_result = tokio::task::spawn_blocking(move || {
        // All TPM operations here
        // If this panics, it won't affect SSL context
        context.quote(...)
    }).await;
    
    match tpm_result {
        Ok(Ok(quote)) => HttpResponse::Ok().json(quote),
        Ok(Err(e)) => {
            error!("TPM error: {:?}", e);
            HttpResponse::InternalServerError().json(error_response)
        }
        Err(panic) => {
            error!("TPM operation panicked: {:?}", panic);
            HttpResponse::InternalServerError().json(error_response)
        }
    }
}
```

**Estimated Effort:** 1-2 days

**Benefits:**
- ✅ Prevents SSL corruption
- ✅ Agent stays responsive even if TPM errors occur
- ✅ Better error handling overall

---

### Option 3: Agent Restart Workaround (Quick Fix)

**Approach:** Automatically restart agent when SSL breaks

**Implementation:** Already created in `keep-agent-alive.sh`

**Usage:**
```bash
# Start agent with auto-restart
./keep-agent-alive.sh &

# Or use systemd watchdog
# Or monitor from test script
```

**Estimated Effort:** Already done (1 hour to integrate into test scripts)

**Benefits:**
- ✅ Quick to implement
- ✅ Allows testing to continue
- ✅ Proves system works end-to-end

**Drawbacks:**
- ⚠️ Not production-ready
- ⚠️ Performance impact (restart overhead)
- ⚠️ Doesn't fix root cause

---

### Option 4: Use Python Keylime Agent (Alternative)

**Approach:** Replace rust-keylime agent with Python keylime agent

**Rationale:**
- Python agent is more mature
- May not have the same SSL bug
- Better error handling

**Estimated Effort:** 1-2 days (integration and testing)

**Benefits:**
- ✅ Mature, well-tested codebase
- ✅ May avoid the SSL bug
- ✅ Better documentation

**Drawbacks:**
- ⚠️ Performance (Python vs Rust)
- ⚠️ May have different issues
- ⚠️ Need to verify delegated certification support

---

### Option 5: Disable On-Demand Quote Fetching (System Design Change)

**Approach:** Configure Verifier to not fetch quotes from agent

**Rationale:**
- The quote is already included in SovereignAttestation payload
- Verifier fetching quote separately is an optimization, not required
- System can work without this feature

**Implementation:**
1. Add config option to Verifier: `fetch_quotes_from_agent = false`
2. Verifier uses quote from SovereignAttestation only
3. Skip the HTTP request to agent's quote endpoint

**Changes Needed:**
- `keylime/keylime/cloud_verifier_tornado.py` - Skip quote fetch
- `keylime/verifier.conf.minimal` - Add config option

**Estimated Effort:** 4-8 hours (code changes + testing)

**Benefits:**
- ✅ Avoids the agent bug entirely
- ✅ System works end-to-end
- ✅ Simpler architecture
- ✅ Less network traffic

**Drawbacks:**
- ⚠️ Loses on-demand quote verification
- ⚠️ Requires Verifier code changes

---

## Recommended Approach

### For Immediate Progress (Today)
**Use Option 3 (Agent Restart Workaround)**
- Already implemented in `keep-agent-alive.sh`
- Allows testing to continue
- Proves system works end-to-end
- Can move to Step 2 (CI/CD testing)

### For Production (Next Week)
**Implement Option 2 (Isolate SSL Context) + Option 1 (Fix NV Read)**
- Option 2 prevents SSL corruption (defensive)
- Option 1 fixes root cause (proper fix)
- Both together make system robust

### Alternative for Production
**Implement Option 5 (Disable Quote Fetching)**
- Simplest production fix
- Quote is already in SovereignAttestation
- Avoids the bug entirely
- Less code to maintain

---

## Testing Plan

### Test 1: Verify Workaround Works
```bash
# Start agent with auto-restart
./keep-agent-alive.sh &

# Run full test
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause

# Verify multiple attestations work
for i in {1..5}; do
    echo "Attestation attempt $i"
    pkill spire-agent
    sleep 5
    # SPIRE Agent will restart and attest
    sleep 10
done
```

### Test 2: Verify Option 5 Works
```bash
# Add to verifier.conf.minimal:
# fetch_quotes_from_agent = false

# Restart verifier
pkill keylime-verifier
./test_complete_control_plane.sh --no-pause

# Run test
./test_complete.sh --no-pause

# Should work without fetching quotes from agent
```

---

## Next Steps

1. **Decide on approach:**
   - Option 3 for immediate progress?
   - Option 5 for production?
   - Option 1+2 for proper fix?

2. **Implement chosen option**

3. **Test thoroughly:**
   - Multiple attestations
   - Agent restarts
   - Network failures
   - TPM errors

4. **Document findings:**
   - Update this document
   - Create bug report for rust-keylime project
   - Share with mentor

5. **Move to Step 2:**
   - Automated CI/CD testing
   - 5-minute test runtime
   - Kubernetes integration (later)

---

## Questions for Discussion

1. Which option should we pursue?
2. Timeline for fixing vs workaround?
3. Should we report this bug to rust-keylime project?
4. Can we move to Step 2 with workaround in place?
5. What's the priority: speed vs proper fix?

---

**Prepared By:** AI Assistant (Kiro)  
**Date:** December 10, 2024  
**Status:** Ready for Decision
