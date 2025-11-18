#!/usr/bin/env bash
# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
# Setup script for Phase 3 components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Unified-Identity - Phase 3: Setup"
echo "=========================================="

# Check prerequisites
echo ""
echo "[STEP] Checking prerequisites..."

# Python 3
if ! command -v python3 &> /dev/null; then
    echo "[ERROR] python3 not found. Please install Python 3.8+"
    exit 1
fi
echo "[OK] Python 3 found: $(python3 --version)"

# tpm2-tools
if ! command -v tpm2 &> /dev/null; then
    echo "[WARN] tpm2-tools not found. TPM operations will not work."
    echo "[INFO] Install with: sudo apt-get install tpm2-tools (Debian/Ubuntu)"
    echo "[INFO] Or: sudo yum install tpm2-tools (RHEL/CentOS)"
else
    echo "[OK] tpm2-tools found: $(tpm2 --version | head -1)"
fi

# TPM device check
if [ -e /dev/tpmrm0 ]; then
    echo "[OK] Hardware TPM resource manager found: /dev/tpmrm0"
elif [ -e /dev/tpm0 ]; then
    echo "[OK] Hardware TPM found: /dev/tpm0"
else
    echo "[WARN] No hardware TPM found. Will use swtpm if available."
fi

# Make scripts executable
echo ""
echo "[STEP] Setting up scripts..."
chmod +x "$SCRIPT_DIR/tpm-plugin/tpm_plugin_cli.py"
chmod +x "$SCRIPT_DIR/scripts/start_keylime_cert_server.py"
chmod +x "$SCRIPT_DIR/test/test_e2e_phase3.sh"
chmod +x "$SCRIPT_DIR/test/test_integration_phase3.sh"
echo "[OK] Scripts made executable"

# Create directories
echo ""
echo "[STEP] Creating directories..."
# Use user-writable directories for testing
mkdir -p "$HOME/.keylime/run" 2>/dev/null || mkdir -p /tmp/keylime-run
mkdir -p "$HOME/.spire/data/agent/tpm-plugin" 2>/dev/null || mkdir -p /tmp/spire-data/tpm-plugin
echo "[OK] Directories created (using user-writable locations)"

# Check Python imports
echo ""
echo "[STEP] Checking Python imports..."
cd "$SCRIPT_DIR/tpm-plugin"
if python3 -c "import sys; sys.path.insert(0, '.'); from tpm_plugin import TPMPlugin; print('OK')" 2>/dev/null; then
    echo "[OK] TPM Plugin imports successfully"
else
    echo "[WARN] TPM Plugin import check failed (may need dependencies)"
fi

if python3 -c "import sys; sys.path.insert(0, '.'); from delegated_certification import DelegatedCertificationClient; print('OK')" 2>/dev/null; then
    echo "[OK] Delegated Certification Client imports successfully"
else
    echo "[WARN] Delegated Certification Client import check failed"
fi

cd "$SCRIPT_DIR"
if python3 -c "import sys; sys.path.insert(0, 'keylime'); from keylime.delegated_certification_server import DelegatedCertificationServer; print('OK')" 2>/dev/null; then
    echo "[OK] Certification Server imports successfully"
else
    echo "[WARN] Certification Server import check failed (may need keylime dependencies)"
fi

# Check if script is being sourced or executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being executed directly - show completion message
    echo ""
    echo "=========================================="
    echo "Unified-Identity - Phase 3: Setup Complete"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "1. Enable feature flag: export UNIFIED_IDENTITY_ENABLED=true"
    echo "2. Start Keylime Agent certification server:"
    echo "   python3 scripts/start_keylime_cert_server.py"
    echo "3. Configure SPIRE Agent with feature flag enabled"
    echo "4. Run tests: ./test/test_e2e_phase3.sh"
    echo ""
    echo "See README.md for detailed instructions."
fi
# If script is sourced, setup functions are available but completion message doesn't show
