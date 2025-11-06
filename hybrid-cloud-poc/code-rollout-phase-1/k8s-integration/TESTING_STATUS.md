# Unified-Identity - Phase 1: Testing Status for Sovereign SVID

This document tracks the testing status of all steps in the README for sovereign SVID generation.

## Testing Status Summary

| Step | Description | Status | Notes |
|------|-------------|--------|-------|
| **Step 1** | Start SPIRE (Server, Agent, Keylime Stub) | ✅ **Tested** | All components start successfully with Unified-Identity feature flag |
| **Step 2** | Verify SPIRE Setup | ✅ **Tested** | Sockets created, Keylime stub listening on port 8888 |
| **Step 3** | Create Kubernetes Cluster | ✅ **Tested** | Kind cluster created with socket mount |
| **Step 4** | Create Registration Entry | ✅ **Tested** | Entry created successfully with k8s selectors |
| **Step 5** | Deploy Test Workload | ✅ **Tested** | Simple hostPath option works; CSI driver pending image |
| **Step 6** | Dump SVID from Workload Pod | ✅ **Tested** | kubectl exec script works; SVID successfully extracted |
| **Step 7** | Test Workload Attestors | ✅ **Tested** | Both unix and k8s attestors verified |
| **Step 8** | Test Sovereign SVID Generation | ⚠️ **Partial** | See details below |

## Step 8: Sovereign SVID Generation - Detailed Status

### Option A: Generate SVID from Host (with SovereignAttestation)

**Status:** ⚠️ **API Authorization Issue**

**What Works:**
- ✅ Script connects to SPIRE Server successfully
- ✅ CSR generation works
- ✅ SovereignAttestation preparation works
- ✅ API call structure is correct

**What Doesn't Work:**
- ❌ `BatchNewX509SVID` API returns `PermissionDenied`
- **Root Cause:** The `BatchNewX509SVID` API requires **agent credentials** (`allow_agent: true` in policy), not direct client access

**From `spire/pkg/server/authpolicy/policy_data.json`:**
```json
{
    "full_method": "/spire.api.server.svid.v1.SVID/BatchNewX509SVID",
    "allow_agent": true
}
```

**Solution Options:**
1. **Use Workload API (Recommended for Phase 1):** Workloads get SVIDs via the Workload API through the agent (Step 6). This is the normal flow and works correctly.
2. **Use Agent Credentials:** Modify the script to use agent SVID for authentication (complex, not recommended for Phase 1)
3. **Use MintX509SVID API:** This API allows admin/local access but doesn't support SovereignAttestation in Phase 1

**Current Workaround:**
- Step 6 (Dump SVID from Pod) successfully retrieves SVIDs from workloads
- The SVID contains the correct SPIFFE ID and is valid
- For Phase 1 testing, this demonstrates the end-to-end flow

### Option B: Dump SVID from Kubernetes Pod

**Status:** ✅ **Fully Tested**

**What Works:**
- ✅ kubectl exec script successfully copies spire-agent binary
- ✅ SVID fetched from Workload API socket
- ✅ Certificate extracted and copied to host
- ✅ SVID is valid and contains correct SPIFFE ID

**Limitations:**
- ⚠️ SVID from Workload API doesn't include `AttestedClaims` (those are only in API response when using `BatchNewX509SVID` with `SovereignAttestation`)
- This is expected - Workload API provides standard SVIDs, not sovereign SVIDs with AttestedClaims

## What's Actually Tested for Sovereign SVID

### ✅ Fully Tested Components:

1. **SPIRE Infrastructure:**
   - Server with Unified-Identity feature flag ✅
   - Agent with Unified-Identity feature flag ✅
   - Keylime stub running and accessible ✅
   - Sockets created with correct permissions ✅

2. **Kubernetes Integration:**
   - Cluster creation with socket mount ✅
   - Workload deployment ✅
   - Socket accessible in pods ✅

3. **Workload Attestation:**
   - Unix workload attestor ✅
   - K8s workload attestor ✅
   - Registration entries created ✅

4. **SVID Retrieval:**
   - Workload API access from pods ✅
   - SVID extraction via kubectl exec ✅
   - SVID validation ✅

### ⚠️ Partially Tested:

1. **Sovereign SVID Generation:**
   - API structure and code: ✅ Tested
   - Keylime integration: ✅ Tested (stub responds)
   - Policy engine: ✅ Tested (unit tests)
   - **Direct API call with SovereignAttestation:** ❌ Blocked by authorization policy

## Recommendations

### For Phase 1 Testing:

1. **Use Step 6 (Dump SVID from Pod)** - This demonstrates the complete workflow:
   - Workload gets SVID from Workload API ✅
   - SVID is valid and contains correct SPIFFE ID ✅
   - This is the production pattern for workloads ✅

2. **For AttestedClaims Testing:**
   - The `AttestedClaims` are returned in the `BatchNewX509SVID` API response
   - To test this, you would need to:
     - Either modify authorization policy (not recommended for production)
     - Or use agent credentials (complex setup)
     - Or wait for Phase 2 when we may have a different API endpoint

3. **Current Status is Acceptable for Phase 1:**
   - All infrastructure works ✅
   - Workloads get SVIDs correctly ✅
   - The sovereign attestation code path is implemented and tested via unit tests ✅
   - The API authorization limitation is a security feature, not a bug ✅

## Next Steps

1. **For immediate testing:** Use Step 6 to verify SVID generation from workloads
2. **For AttestedClaims:** Consider adding a test endpoint or modifying authorization for Phase 1 testing only
3. **For production:** The authorization policy is correct - agents should be the only ones calling `BatchNewX509SVID`

