# Fix: SPIRE Agent Socket Not Found Error

## Problem

When running `test_complete.sh`, Step 10 (Generating Sovereign SVID) fails with:
```
Error: SPIRE Agent socket not found at /tmp/spire-agent/public/api.sock
Make sure SPIRE Agent is running
```

## Root Cause

The Python scripts (`fetch-sovereign-svid.py` and `fetch-sovereign-svid-grpc.py`) check for the SPIRE Agent socket immediately without waiting. The SPIRE Agent may still be starting up or completing attestation when the scripts run.

## Solution

Added a 30-second wait loop to both Python scripts before checking for the socket.

### Files Modified

1. **python-app-demo/fetch-sovereign-svid.py**
2. **python-app-demo/fetch-sovereign-svid-grpc.py**

### Changes

Before:
```python
socket_path = "/tmp/spire-agent/public/api.sock"

if not os.path.exists(socket_path):
    print(f"Error: SPIRE Agent socket not found at {socket_path}")
    print("Make sure SPIRE Agent is running")
    return None, None
```

After:
```python
socket_path = "/tmp/spire-agent/public/api.sock"

# Wait for socket to be ready (up to 30 seconds)
import time
max_wait = 30
for i in range(max_wait):
    if os.path.exists(socket_path):
        break
    if i == 0:
        print(f"Waiting for SPIRE Agent socket at {socket_path}...")
    time.sleep(1)

if not os.path.exists(socket_path):
    print(f"Error: SPIRE Agent socket not found at {socket_path}")
    print(f"Waited {max_wait} seconds but socket was not created")
    print("Make sure SPIRE Agent is running")
    return None, None
```

## Testing

Run the complete test again:
```bash
./test_complete_control_plane.sh --no-pause
./test_complete.sh --no-pause
```

Step 10 should now wait for the socket to be ready instead of failing immediately.

## Why This Works

The SPIRE Agent creates the Workload API socket (`/tmp/spire-agent/public/api.sock`) after:
1. Starting up
2. Connecting to SPIRE Server
3. Completing attestation
4. Receiving its Agent SVID

This process can take a few seconds, especially on the first run. The wait loop gives the agent time to complete these steps before the Python scripts try to connect.

## Related

- The test script (`test_complete.sh`) already waits up to 90 seconds for the agent to attest (Step 7)
- However, Step 10 runs the demo script which didn't have its own wait logic
- This fix ensures the demo script can be run standalone or as part of the test suite
