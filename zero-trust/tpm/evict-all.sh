#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] Listing current persistent handles..."
handles=$(tpm2_getcap handles-persistent | awk '{print $2}')

if [ -z "$handles" ]; then
  echo "[INFO] No persistent handles found."
  exit 0
fi

for h in $handles; do
  echo "[STEP] Evicting handle $h ..."
  # Try to evict; if it fails, continue
  if tpm2_evictcontrol -C o -c "$h" 2>/dev/null; then
    echo "[OK] Handle $h evicted."
  else
    echo "[WARN] Could not evict handle $h (may already be gone or reserved)."
  fi
done

echo "[INFO] Done."
