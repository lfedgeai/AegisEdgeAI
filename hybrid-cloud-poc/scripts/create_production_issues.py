#!/usr/bin/env python3
"""
Script to create GitHub issues for production readiness gaps.
Requires GITHUB_TOKEN environment variable to be set.
"""

import os
import json
import requests
import sys

REPO_OWNER = "lfedgeai"
REPO_NAME = "AegisEdgeAI"

def create_issue(title, body, labels=None):
    """Create a GitHub issue using the GitHub API."""
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("Error: GITHUB_TOKEN environment variable not set")
        print("Please set it with: export GITHUB_TOKEN=your_token")
        return False
    
    url = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/issues"
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json"
    }
    
    data = {
        "title": title,
        "body": body,
        "labels": labels or []
    }
    
    try:
        response = requests.post(url, headers=headers, json=data)
        response.raise_for_status()
        issue_data = response.json()
        print(f"✅ Created issue #{issue_data['number']}: {title}")
        print(f"   URL: {issue_data['html_url']}\n")
        return True
    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to create issue: {title}")
        print(f"   Error: {e}")
        if hasattr(e.response, 'text'):
            print(f"   Response: {e.response.text}")
        return False

def main():
    issues = [
        {
            "title": "[Security] SPIRE Agent TPM Plugin Server → Keylime Agent: Use UDS for Security",
            "body": """## Current State
Communication uses HTTPS/mTLS over localhost (`https://127.0.0.1:9002`)

**Status:** ✅ mTLS implemented
- SPIRE Agent TPM Plugin Server (Sidecar) now uses HTTPS with client certificate authentication (mTLS)
- SPIRE Agent TPM Plugin Server (Sidecar) uses verifier's client certificate (signed by verifier's CA, which agent trusts)
- Agent requires and verifies client certificate from SPIRE Agent TPM Plugin Server (Sidecar)
- Communication is encrypted and authenticated

**Remaining Gap:** UDS support (preferred over TCP for localhost communication)

## Required for UDS
- Implement UDS socket support in rust-keylime agent for the delegated certification endpoint
- Update SPIRE Agent TPM Plugin Server (Sidecar) client to use UDS instead of HTTPS
- Protocol can be HTTP/JSON or pure JSON over UDS
- Default UDS path: `/tmp/keylime-agent.sock` or similar

## Location
- `code-rollout-phase-3/tpm-plugin/delegated_certification.py` - Now uses HTTPS/mTLS (client certificate from verifier's CA)
- `code-rollout-phase-2/rust-keylime/keylime-agent/src/main.rs` - Needs UDS socket binding support

## Related
Extracted from `README-arch-sovereign-unified-identity.md` - Gap #1""",
            "labels": []
        },
        {
            "title": "[Security] Keylime Verifier → Mobile Location Microservice: Use UDS for Security",
            "body": """## Current State
Communication is hardcoded to HTTP over localhost (`http://127.0.0.1:9050`)

## Issue
HTTP over TCP is less secure than UDS; traffic could be intercepted or spoofed

## Required
- Implement UDS socket support in mobile location verification microservice
- Update verifier to use UDS instead of HTTP
- Protocol can be HTTP/JSON or pure JSON over UDS
- Default UDS path: `/tmp/mobile-sensor.sock` or similar

## Location
- `keylime/keylime/cloud_verifier_tornado.py` - Verifier integration (`_verify_mobile_sensor_geolocation`)
- `mobile-sensor-microservice/service.py` (needs UDS socket binding support)

## Related
Extracted from `README-arch-sovereign-unified-identity.md` - Gap #2""",
            "labels": []
        },
        {
            "title": "[Security] Keylime Testing Mode: EK Certificate Verification Disabled",
            "body": """## Current State
Keylime is running in testing mode (`KEYLIME_TEST=on`), which disables EK certificate verification for TPM emulators.

## Issue
- EK (Endorsement Key) certificate verification is disabled when `KEYLIME_TEST=on` is set
- This is a security gap as it bypasses verification of the TPM's endorsement key certificate
- The warning message indicates: "WARNING: running keylime in testing mode. Keylime will: - Not check the ekcert for the TPM emulator"
- While hardware TPM is being used, the testing mode still disables EK cert checks

## Required
- Remove `KEYLIME_TEST=on` environment variable from test scripts and production deployments
- Enable EK certificate verification by default for production use
- Ensure EK certificate store is properly configured (`tpm_cert_store` in Keylime config)
- For testing with hardware TPM, EK certificates should still be verified (testing mode is only needed for TPM emulators)

## Location
- `test_complete.sh` - Sets `export KEYLIME_TEST=on` (lines 972, 1003, 1113, 1166, 1685)
- `keylime/keylime/config.py` - Testing mode detection and EK cert check disabling (lines 62-70)
- `keylime/verifier.conf.minimal` - May need `tpm_cert_store` configuration for EK verification

## Related
Extracted from `README-arch-sovereign-unified-identity.md` - Gap #3""",
            "labels": []
        },
        {
            "title": "[Enhancement] rust-keylime Agent: Using /dev/tpm0 Instead of /dev/tpmrm0 and Persistent Handles",
            "body": """## Current State
- rust-keylime agent is using `/dev/tpm0` (direct TPM device) instead of `/dev/tpmrm0` (TPM resource manager)
- Agent uses persistent handles for TPM keys (e.g., App Key at `0x8101000B`)

## Issues

### 1. Direct TPM Device Access (`/dev/tpm0`)
- Using `/dev/tpm0` directly bypasses the TPM resource manager (`tpm2-abrmd`)
- Resource manager provides better session management, handle management, and concurrent access control
- Direct access can lead to handle conflicts and resource contention
- The test script sets `TCTI="device:/dev/tpmrm0"` but rust-keylime agent logs show it's using `/dev/tpm0`

### 2. Persistent Handles
- App Key is persisted at handle `0x8101000B` in the TPM
- Persistent handles survive reboots but can cause issues:
  - Handle conflicts if multiple processes access the same handle
  - Resource exhaustion if handles are not properly managed
  - Security concerns if handles are not properly protected

## Required

### 1. Force rust-keylime agent to use `/dev/tpmrm0`
- Ensure `TCTI` environment variable is set to `device:/dev/tpmrm0` when starting rust-keylime agent
- Verify `tpm2-abrmd` resource manager is running before starting the agent
- Update rust-keylime default TCTI detection to prefer `/dev/tpmrm0` over `/dev/tpm0`

### 2. Persistent Handle Management
- Document persistent handle usage and lifecycle
- Ensure proper cleanup of persistent handles when needed
- Consider using transient handles with context files for better isolation
- Add handle conflict detection and resolution

## Location
- `test_complete.sh` - TCTI configuration for rust-keylime agent (lines 1238-1246, 1418, 1432)
- `rust-keylime/keylime/src/tpm.rs` - TCTI detection defaults to `/dev/tpmrm0` but may fall back to `/dev/tpm0` (lines 578-586)
- `rust-keylime/keylime-agent/src/main.rs` - Agent startup and TCTI usage (lines 365, 615, 790)
- `tpm-plugin/tpm_plugin.py` - App Key persistent handle `0x8101000B` (line 59)

## Related
Extracted from `README-arch-sovereign-unified-identity.md` - Gap #4""",
            "labels": []
        },
        {
            "title": "[Performance] SPIRE TPM Plugin: Uses TSS Subprocess Calls Instead of TSS Library",
            "body": """## Current State
SPIRE TPM Plugin uses `subprocess.run()` to call tpm2-tools commands instead of using the TSS library (tss_esapi) directly

Commands executed via subprocess: `tpm2_createprimary`, `tpm2_create`, `tpm2_load`, `tpm2_evictcontrol`, `tpm2_readpublic`

## Issues

### 1. Performance Overhead
- Subprocess calls have significant overhead (process creation, IPC, parsing output)
- Each TPM operation requires spawning a new process
- Slower than direct TSS library calls

### 2. Error Handling
- Subprocess calls require parsing stdout/stderr for error information
- Less granular error handling compared to TSS library error codes
- Harder to debug TPM operation failures

### 3. Security
- Subprocess calls rely on external tpm2-tools binaries
- Potential for command injection if inputs are not properly sanitized
- Less control over TPM session management

### 4. Dependency Management
- Requires tpm2-tools to be installed and in PATH
- Version compatibility issues between tpm2-tools and TPM firmware
- Additional dependency to maintain

## Required
- Migrate TPM operations to use TSS library (tss_esapi for Python or equivalent)
- Replace subprocess calls with direct TSS API calls:
  - `tpm2_createprimary` → TSS `CreatePrimary`
  - `tpm2_create` → TSS `Create`
  - `tpm2_load` → TSS `Load`
  - `tpm2_evictcontrol` → TSS `EvictControl`
  - `tpm2_readpublic` → TSS `ReadPublic`
- Implement proper TSS context management and session handling
- Maintain backward compatibility during migration

## Location
- `tpm-plugin/tpm_plugin.py` - All TPM operations use `_run_tpm_command()` which calls subprocess (lines 110-141, 188-272)
- `tpm-plugin/tpm_plugin.py` - Commands: `tpm2_createprimary` (line 218), `tpm2_create` (line 229), `tpm2_load` (line 242), `tpm2_evictcontrol` (line 252), `tpm2_readpublic` (lines 188, 263, 269)

## Related
Extracted from `README-arch-sovereign-unified-identity.md` - Gap #5""",
            "labels": []
        },
        {
            "title": "[Performance] rust-keylime Agent: Uses TSS Subprocess Calls Instead of TSS Library",
            "body": """## Current State
rust-keylime agent uses `USE_TPM2_QUOTE_DIRECT=1` environment variable to call `tpm2_quote` as a subprocess instead of using TSS library

Also uses `tpm2 createek` and `tpm2 createak` subprocess calls when `USE_TPM2_QUOTE_DIRECT` is set

This is a workaround for deadlock issues with TSS library when using hardware TPM

## Issues

### 1. Deadlock Workaround
- The subprocess approach is used to avoid deadlocks with TSS library context locks
- When using TSS library directly, quote operations can deadlock with hardware TPM
- The workaround switches from `/dev/tpmrm0` to `/dev/tpm0` to avoid resource manager deadlocks

### 2. Performance Overhead
- Subprocess calls have overhead (process creation, IPC, file I/O for context files)
- Quote operations take ~10 seconds with subprocess approach
- Direct TSS library calls would be faster if deadlock issue is resolved

### 3. Inconsistency
- Agent uses TSS library (`tss_esapi`) for most operations but subprocess for quotes
- Mixed approach makes codebase harder to maintain
- Different error handling paths for TSS vs subprocess operations

### 4. Resource Manager Bypass
- Subprocess approach switches from `/dev/tpmrm0` to `/dev/tpm0` to avoid deadlocks
- This bypasses the TPM resource manager, which provides better session management
- Can lead to handle conflicts and resource contention (see related issue)

## Required

### 1. Fix TSS Library Deadlock
- Investigate and fix root cause of deadlocks with TSS library and hardware TPM
- May be related to context lock management or resource manager interaction
- Consider TSS library version updates or patches

### 2. Migrate to Pure TSS Library
- Remove `USE_TPM2_QUOTE_DIRECT` workaround once deadlock is fixed
- Use TSS library `Quote` operation directly instead of subprocess
- Replace `tpm2 createek` and `tpm2 createak` with TSS library calls

### 3. Maintain Resource Manager
- Ensure TSS library operations work with `/dev/tpmrm0` (resource manager)
- Avoid switching to `/dev/tpm0` as workaround
- Proper session and context management with resource manager

## Location
- `rust-keylime/keylime/src/tpm.rs` - `perform_quote_with_tpm2_command()` and `perform_quote_with_tpm2_command_using_context()` functions (lines 2582-2814, 2816-3040)
- `rust-keylime/keylime/src/tpm.rs` - Uses `Command::new("tpm2_quote")` for subprocess calls (lines 2682, 2939)
- `rust-keylime/keylime-agent/src/main.rs` - `USE_TPM2_QUOTE_DIRECT` flag usage and `tpm2 createek`/`tpm2 createak` subprocess calls (lines 331, 368, 582-583)
- `test_complete.sh` - Sets `USE_TPM2_QUOTE_DIRECT=1` environment variable (lines 1401-1404, 1418, 1420, 1432, 1434, 1447)

## Related
Extracted from `README-arch-sovereign-unified-identity.md` - Gap #6""",
            "labels": []
        }
    ]
    
    print(f"Creating {len(issues)} GitHub issues for {REPO_OWNER}/{REPO_NAME}...\n")
    
    success_count = 0
    for issue in issues:
        if create_issue(issue["title"], issue["body"], issue["labels"]):
            success_count += 1
    
    print(f"\n{'='*60}")
    print(f"Summary: {success_count}/{len(issues)} issues created successfully")
    
    if success_count < len(issues):
        print("\nSome issues failed to create. Please check the errors above.")
        sys.exit(1)
    else:
        print("All issues created successfully!")
        sys.exit(0)

if __name__ == "__main__":
    main()
