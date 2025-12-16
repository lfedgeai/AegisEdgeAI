# Quick Fix: Verifier Config Error

## Problem
Verifier crashes with: `Could not find option 'enabled_revocation_notifications' in section 'revocations'`

## Root Cause
The `getlist()` function in Keylime's config.py doesn't handle empty values properly. When the config has an empty value (just whitespace), it raises an exception.

## Solution
Ensure the config has exactly this format (with `[]`):

```ini
[revocations]
enabled_revocation_notifications = []
zmq_port = 5556
```

## Quick Fix on Remote Machine

Run these commands on dell@vso:

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Method 1: Use sed to fix the line
sed -i '/enabled_revocation_notifications/c\enabled_revocation_notifications = []' keylime/verifier.conf.minimal

# Verify the fix
grep -A 2 "\[revocations\]" keylime/verifier.conf.minimal

# Should show:
# [revocations]
# enabled_revocation_notifications = []
# zmq_port = 5556
```

## Verify with Python

```bash
python3 << 'EOF'
import configparser
import ast

config = configparser.ConfigParser()
config.read('keylime/verifier.conf.minimal')

value = config.get('revocations', 'enabled_revocation_notifications').strip('" ')
print(f"Value: '{value}'")
parsed = ast.literal_eval(value)
print(f"Parsed: {parsed} (type: {type(parsed).__name__})")
print("✓ Config is valid!" if isinstance(parsed, list) else "✗ Config is invalid!")
EOF
```

## Then Test

```bash
./test_complete_control_plane.sh --no-pause
```

## If Still Failing

Check for hidden characters or line ending issues:

```bash
# Show hex dump of the line
grep "enabled_revocation_notifications" keylime/verifier.conf.minimal | od -c

# Fix line endings if needed
sed -i 's/\r$//' keylime/verifier.conf.minimal
```
