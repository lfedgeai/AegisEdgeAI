#!/bin/bash

# ARM64-specific system setup script for AegisEdgeAI
# This script handles ARM64 architecture-specific TPM stack installation

set -euo pipefail

echo "=== AegisEdgeAI ARM64 System Setup ==="

# Detect architecture
ARCH=$(uname -m)
OS=$(uname -s)

if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
  echo "Error: This script is specifically for ARM64 architecture. Detected: $ARCH"
  exit 1
fi

echo "Detected ARM64 architecture: $ARCH on $OS"

# Set build variables
export PREFIX="/usr/local"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$PREFIX/lib:${LD_LIBRARY_PATH:-}"
export PATH="$PREFIX/bin:$PATH"

# Create build directory
BUILD_DIR="/tmp/aegis-arm64-build"
echo "Creating build directory: $BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install system dependencies
install_dependencies() {
    echo "Installing build dependencies..."
    
    if command_exists dnf; then
        # RHEL/Fedora/CentOS
        sudo dnf groupinstall -y "Development Tools"
        sudo dnf install -y \
            autoconf automake libtool pkg-config git cmake \
            openssl-devel json-c-devel libcurl-devel \
            libuuid-devel glib2-devel
    elif command_exists apt; then
        # Ubuntu/Debian
        sudo apt update
        sudo apt install -y \
            build-essential autoconf automake libtool pkg-config git cmake \
            libssl-dev libjson-c-dev libcurl4-openssl-dev \
            uuid-dev libglib2.0-dev
    else
        echo "Error: Unsupported package manager. Please install dependencies manually."
        exit 1
    fi
}

# Function to build libtpms
build_libtpms() {
    echo "Building libtpms for ARM64..."
    
    if [ -d "libtpms" ]; then
        rm -rf libtpms
    fi
    
    git clone https://github.com/stefanberger/libtpms.git
    cd libtpms
    
    ./autogen.sh \
        --with-tpm2 \
        --with-openssl \
        --prefix="$PREFIX" \
        --exec-prefix="$PREFIX"
    
    make -j$(nproc)
    sudo make install
    
    cd ..
    echo "libtpms build completed"
}

# Function to build swtpm
build_swtpm() {
    echo "Building swtpm for ARM64..."
    
    if [ -d "swtpm" ]; then
        rm -rf swtpm
    fi
    
    git clone https://github.com/stefanberger/swtpm.git
    cd swtpm
    
    ./autogen.sh \
        --with-tpm2 \
        --with-openssl \
        --prefix="$PREFIX" \
        --exec-prefix="$PREFIX"
    
    make -j$(nproc)
    sudo make install
    
    cd ..
    echo "swtpm build completed"
}

# Function to build tpm2-tss
build_tpm2_tss() {
    echo "Building tpm2-tss for ARM64..."
    
    if [ -d "tpm2-tss" ]; then
        rm -rf tpm2-tss
    fi
    
    git clone https://github.com/tpm2-software/tpm2-tss.git
    cd tpm2-tss
    
    ./bootstrap
    ./configure \
        --prefix="$PREFIX" \
        --exec-prefix="$PREFIX" \
        --with-tctidefaultmodule=libtss2-tcti-swtpm \
        --with-tctidefaultconfig="swtpm:host=localhost,port=2321"
    
    make -j$(nproc)
    sudo make install
    
    cd ..
    echo "tpm2-tss build completed"
}

# Function to build tpm2-tools
build_tpm2_tools() {
    echo "Building tpm2-tools for ARM64..."
    
    if [ -d "tpm2-tools" ]; then
        rm -rf tpm2-tools
    fi
    
    git clone https://github.com/tpm2-software/tpm2-tools.git
    cd tpm2-tools
    
    ./bootstrap
    ./configure \
        --prefix="$PREFIX" \
        --exec-prefix="$PREFIX"
    
    make -j$(nproc)
    sudo make install
    
    cd ..
    echo "tpm2-tools build completed"
}

# Function to verify installation
verify_installation() {
    echo "Verifying ARM64 TPM stack installation..."
    
    # Update library cache
    sudo ldconfig
    
    # Check if binaries exist and can run
    local success=true
    
    if command_exists swtpm; then
        echo "✓ swtpm found: $(swtpm --version | head -1)"
    else
        echo "✗ swtpm not found"
        success=false
    fi
    
    if command_exists tpm2_createprimary; then
        echo "✓ tpm2-tools found: $(tpm2_createprimary --version | head -1)"
    else
        echo "✗ tpm2-tools not found"
        success=false
    fi
    
    # Check libraries
    if ldconfig -p | grep -q libtss2-esys; then
        echo "✓ libtss2-esys found"
    else
        echo "✗ libtss2-esys not found"
        success=false
    fi
    
    if [ "$success" = true ]; then
        echo "✓ ARM64 TPM stack installation verified successfully"
    else
        echo "✗ ARM64 TPM stack installation verification failed"
        return 1
    fi
}

# Function to create ARM64-specific configuration
create_arm64_config() {
    echo "Creating ARM64-specific configuration..."
    
    # Create systemd service for swtpm if systemd is available
    if command_exists systemctl; then
        # Create swtpm user and group if they don't exist
        if ! getent group swtpm >/dev/null 2>&1; then
            sudo groupadd -r swtpm
            echo "Created swtpm group"
        fi
        if ! getent passwd swtpm >/dev/null 2>&1; then
            sudo useradd -r -g swtpm -d /var/lib/swtpm-localca -s /sbin/nologin -c "Software TPM user" swtpm
            echo "Created swtpm user"
        fi
        
        # Create TPM state directory
        sudo mkdir -p /var/lib/swtpm-localca
        sudo chown swtpm:swtpm /var/lib/swtpm-localca
        
        cat > /tmp/swtpm-arm64.service << 'EOF'
[Unit]
Description=Software TPM Emulator for ARM64
After=network.target

[Service]
Type=simple
User=swtpm
Group=swtpm
ExecStart=/usr/local/bin/swtpm socket --tpmstate dir=/var/lib/swtpm-localca --ctrl type=tcp,port=2321 --server type=tcp,port=2322 --tpm2
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        sudo mv /tmp/swtpm-arm64.service /etc/systemd/system/
        echo "Created systemd service: /etc/systemd/system/swtpm-arm64.service"
    fi
    
    # Create ARM64 environment script
    cat > /tmp/arm64-tpm-env.sh << EOF
#!/bin/bash
# ARM64 TPM Environment Setup

export PREFIX="$PREFIX"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:\${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$PREFIX/lib:\${LD_LIBRARY_PATH:-}"
export PATH="$PREFIX/bin:\$PATH"

# TPM2 Tools configuration
export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321"

echo "ARM64 TPM environment configured"
echo "TPM2TOOLS_TCTI=\$TPM2TOOLS_TCTI"
EOF
    
    sudo mv /tmp/arm64-tpm-env.sh /etc/profile.d/
    chmod +x /etc/profile.d/arm64-tpm-env.sh
    echo "Created environment script: /etc/profile.d/arm64-tpm-env.sh"
}

# Main installation process
main() {
    echo "Starting ARM64 TPM stack installation..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        echo "Warning: Running as root. Consider running as a regular user with sudo access."
    fi
    
    # Install dependencies
    install_dependencies
    
    # Build TPM stack components
    build_libtpms
    build_swtpm
    build_tpm2_tss
    build_tpm2_tools
    
    # Verify installation
    verify_installation
    
    # Create configuration
    create_arm64_config
    
    echo "=== ARM64 TPM stack installation completed successfully ==="
    echo ""
    echo "Next steps:"
    echo "1. Source the environment: source /etc/profile.d/arm64-tpm-env.sh"
    echo "2. Test TPM functionality: ./zero-trust/tpm/swtpm.sh"
    echo "3. Run the main setup: ./zero-trust/system-setup.sh"
    echo ""
    echo "For hardware TPM support, ensure your ARM64 device has a TPM chip"
    echo "and the appropriate kernel modules are loaded."
}

# Cleanup function
cleanup() {
    echo "Cleaning up build directory..."
    cd /
    rm -rf "$BUILD_DIR"
}

# Set trap for cleanup
trap cleanup EXIT

# Run main installation
main "$@"