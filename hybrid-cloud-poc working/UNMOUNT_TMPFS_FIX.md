# Fix: Device or Resource Busy Error

## The Problem

```
rm: cannot remove '/tmp/keylime-agent/secure': Device or resource busy
```

This happens because `/tmp/keylime-agent/secure` is mounted as a tmpfs filesystem and needs to be unmounted before deletion.

## Quick Fix

Run these commands on your Linux machine:

```bash
# Check what's mounted
mount | grep keylime

# Unmount the tmpfs
sudo umount /tmp/keylime-agent/secure

# If that fails, force unmount
sudo umount -f /tmp/keylime-agent/secure

# If still fails, lazy unmount
sudo umount -l /tmp/keylime-agent/secure

# Now remove the directory
rm -rf /tmp/keylime-agent

# Continue with the rest of cleanup
rm -rf /tmp/spire-* /opt/spire/data/* keylime/cv_ca keylime/*.db /tmp/*.log
```

## Complete Cleanup Commands

Here's the full sequence with tmpfs unmount:

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Stop all processes
pkill keylime_agent 2>/dev/null || true
pkill spire-agent 2>/dev/null || true
pkill keylime-verifier 2>/dev/null || true
pkill keylime-registrar 2>/dev/null || true
pkill spire-server 2>/dev/null || true
pkill tpm2-abrmd 2>/dev/null || true

# Wait for processes to stop
sleep 2

# Unmount tmpfs if mounted
if mountpoint -q /tmp/keylime-agent/secure 2>/dev/null; then
    echo "Unmounting tmpfs..."
    sudo umount /tmp/keylime-agent/secure 2>/dev/null || sudo umount -f /tmp/keylime-agent/secure 2>/dev/null || sudo umount -l /tmp/keylime-agent/secure
fi

# Now clean everything
rm -rf /tmp/keylime-agent
rm -rf /tmp/spire-*
rm -rf /opt/spire/data/*
rm -rf keylime/cv_ca
rm -rf keylime/*.db
rm -f /tmp/*.log

echo "✓ Cleanup complete!"

# Restart control plane
./test_complete_control_plane.sh --no-pause
```

## Why This Happens

The `test_complete.sh` script mounts a tmpfs filesystem at `/tmp/keylime-agent/secure` for secure storage. This is a special in-memory filesystem that needs to be unmounted before the directory can be deleted.

## Alternative: Use the Cleanup Script

If the project has a cleanup script, use it:

```bash
# Check if cleanup script exists
ls -la scripts/cleanup.sh

# If it exists, run it
./scripts/cleanup.sh
```

## Verification

After unmounting and cleaning:

```bash
# Check nothing is mounted
mount | grep keylime
# Should show nothing

# Check directories are gone
ls -la /tmp/keylime-agent
# Should show: No such file or directory

# Check processes are stopped
ps aux | grep -E "keylime|spire" | grep -v grep
# Should show nothing
```

## Then Restart

```bash
# Start control plane
./test_complete_control_plane.sh --no-pause

# Wait for it to be ready, then start agents
./test_complete.sh --no-pause
```
