#!/bin/bash
# Installation script for prerequisites
# Usage: ./install_prerequisites.sh [host_ip]
# If host_ip is provided, will SSH to that host and install packages there
# Otherwise installs on local system

set -e

HOST_IP="${1:-}"
SSH_USER="${SSH_USER:-$USER}"

if [ -n "$HOST_IP" ]; then
    echo "Installing packages on remote host: $HOST_IP"
    SSH_CMD="ssh ${SSH_USER}@${HOST_IP}"
    SUDO_CMD="sudo"
else
    echo "Installing packages on local system"
    SSH_CMD=""
    SUDO_CMD="sudo"
fi

run_cmd() {
    if [ -n "$SSH_CMD" ]; then
        $SSH_CMD "$1"
    else
        eval "$1"
    fi
}

echo "=========================================="
echo "Installing Prerequisites"
echo "=========================================="

# Detect OS
echo "Detecting OS..."
OS_INFO=$(run_cmd "cat /etc/os-release | grep -E '^ID=' | cut -d'=' -f2 | tr -d '\"'")
echo "Detected OS: $OS_INFO"

if [ "$OS_INFO" != "ubuntu" ] && [ "$OS_INFO" != "debian" ]; then
    echo "Error: This script currently supports Ubuntu/Debian only"
    exit 1
fi

echo ""
echo "--- Updating package lists ---"
run_cmd "$SUDO_CMD apt-get update -qq"

echo ""
echo "--- Installing Essential System Packages ---"
run_cmd "$SUDO_CMD apt-get install -y curl wget git vim net-tools iproute2 iputils-ping dnsutils ca-certificates"

echo ""
echo "--- Installing TPM2 Tools and Libraries ---"
run_cmd "$SUDO_CMD apt-get install -y tpm2-tools tpm2-abrmd libtss2-dev libtss2-esys-3.0.2-0 libtss2-sys1 libtss2-tcti-device0 libtss2-tcti-swtpm0"

echo ""
echo "--- Installing Software TPM (swtpm) ---"
run_cmd "$SUDO_CMD apt-get install -y swtpm swtpm-tools"

echo ""
echo "--- Installing Build Tools ---"
run_cmd "$SUDO_CMD apt-get install -y build-essential gcc g++ make cmake pkg-config libclang-dev libclang-14-dev"

echo ""
echo "--- Installing OpenSSL Development Libraries ---"
run_cmd "$SUDO_CMD apt-get install -y libssl-dev"

echo ""
echo "--- Installing Python Development Packages ---"
run_cmd "$SUDO_CMD apt-get install -y python3 python3-dev python3-pip python3-venv python3-distutils"

echo ""
echo "--- Installing Rust Toolchain ---"
if run_cmd "which rustc" 2>/dev/null; then
    echo "Rust already installed: $(run_cmd 'rustc --version')"
else
    echo "Installing Rust via rustup..."
    run_cmd "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
    run_cmd "source \$HOME/.cargo/env && rustc --version"
    echo "Note: You may need to run 'source \$HOME/.cargo/env' or restart your shell to use rustc"
fi

echo ""
echo "--- Installing/Updating Go Toolchain ---"
if run_cmd "which go" 2>/dev/null; then
    CURRENT_GO=$(run_cmd "go version | awk '{print \$3}'")
    echo "Go already installed: $CURRENT_GO"
    if [[ "$CURRENT_GO" < "go1.20" ]]; then
        echo "Go version is older than 1.20, updating..."
        run_cmd "$SUDO_CMD rm -rf /usr/local/go"
        run_cmd "cd /tmp && wget -q https://go.dev/dl/go1.22.0.linux-amd64.tar.gz"
        run_cmd "$SUDO_CMD tar -C /usr/local -xzf /tmp/go1.22.0.linux-amd64.tar.gz"
        run_cmd "rm /tmp/go1.22.0.linux-amd64.tar.gz"
        echo "Go updated. You may need to add /usr/local/go/bin to PATH"
    fi
else
    echo "Installing Go 1.22.0..."
    run_cmd "cd /tmp && wget -q https://go.dev/dl/go1.22.0.linux-amd64.tar.gz"
    run_cmd "$SUDO_CMD tar -C /usr/local -xzf /tmp/go1.22.0.linux-amd64.tar.gz"
    run_cmd "rm /tmp/go1.22.0.linux-amd64.tar.gz"
    echo "Go installed. You may need to add /usr/local/go/bin to PATH"
fi

echo ""
echo "--- Installing Python Packages ---"
echo "Installing/updating key Python packages..."
run_cmd "python3 -m pip install --upgrade pip"
run_cmd "python3 -m pip install --upgrade spiffe>=0.2.0 cryptography>=41.0.0 grpcio>=1.60.0 grpcio-tools>=1.60.0 protobuf>=4.25.0 requests>=2.31.0 pre-commit"

echo ""
echo "--- Setting up TSS Group ---"
if run_cmd "getent group tss" 2>/dev/null; then
    echo "TSS group exists"
else
    echo "Creating TSS group..."
    run_cmd "$SUDO_CMD groupadd -r tss"
fi

# Add user to tss group if not already in it
CURRENT_USER=$(run_cmd "whoami")
if ! run_cmd "groups | grep -q tss"; then
    echo "Adding user $CURRENT_USER to tss group..."
    run_cmd "$SUDO_CMD usermod -a -G tss $CURRENT_USER"
    echo "Note: You may need to log out and back in for group changes to take effect"
else
    echo "User $CURRENT_USER is already in tss group"
fi

echo ""
echo "=========================================="
echo "Installation Complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. If Rust was just installed, run: source \$HOME/.cargo/env"
echo "2. If Go was just installed/updated, ensure /usr/local/go/bin is in your PATH"
echo "3. If you were added to tss group, log out and back in"
echo "4. Verify installation by running: ./check_packages.sh"
echo ""
