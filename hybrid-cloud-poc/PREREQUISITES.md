# Installation Prerequisites

This document provides detailed information about the prerequisites required to run the Hybrid Cloud Unified Identity PoC.

## Quick Installation

For automated installation of all prerequisites, use the provided installation script:

```bash
# Install on local system
./install_prerequisites.sh

# Install on remote system via SSH
./install_prerequisites.sh 10.1.0.10
```

To verify installation:

```bash
# Check local system
./check_packages.sh

# Check remote system
./check_packages.sh 10.1.0.10
```

## System Requirements

### Operating System
- **Ubuntu 22.04 LTS** (tested and recommended)
- Compatible Debian-based distributions may work but are not tested

### Hardware Requirements
- **TPM 2.0** hardware (or software TPM emulator for testing)
- **Mobile location sensor** (USB tethered smartphone) or GNSS module (optional, for geofencing demo)
- **Network connectivity** between machines
- **Root/sudo access** on both machines

### Network Configuration
- Two machines with static IP addresses:
  - **10.1.0.11** (or similar): Sovereign Cloud/Edge Cloud
  - **10.1.0.10** (or similar): Customer On-Prem Private Cloud

## Required Linux Packages

### Essential System Packages
```bash
sudo apt-get install -y \
  curl wget git vim net-tools iproute2 iputils-ping dnsutils ca-certificates
```

### TPM2 Tools and Libraries
```bash
sudo apt-get install -y \
  tpm2-tools \
  tpm2-abrmd \
  libtss2-dev \
  libtss2-esys-3.0.2-0 \
  libtss2-sys1 \
  libtss2-tcti-device0 \
  libtss2-tcti-swtpm0
```

### Software TPM (for testing without hardware TPM)
```bash
sudo apt-get install -y swtpm swtpm-tools
```

### Build Tools
```bash
sudo apt-get install -y \
  build-essential \
  gcc g++ make cmake \
  pkg-config \
  libclang-dev \
  libclang-14-dev
```

### OpenSSL Development Libraries
```bash
sudo apt-get install -y libssl-dev
```

### Python Development Packages
```bash
sudo apt-get install -y \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  python3-distutils
```

## Programming Language Toolchains

### Python 3.10+

**System Package:**
```bash
sudo apt-get install -y python3 python3-dev python3-pip python3-venv
```

**Required Python Packages (via pip):**
```bash
python3 -m pip install --upgrade pip
python3 -m pip install \
  spiffe>=0.2.0 \
  cryptography>=41.0.0 \
  grpcio>=1.60.0 \
  grpcio-tools>=1.60.0 \
  protobuf>=4.25.0 \
  requests>=2.31.0
```

**Verified Versions:**
- Python: 3.10.12
- spiffe: 0.2.2
- cryptography: 45.0.7
- grpcio: 1.76.0
- protobuf: 6.33.0
- requests: 2.31.0

### Rust Toolchain

**Installation:**
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

**Verified Version:**
- rustc: 1.91.1 or later
- cargo: 1.91.1 or later

**Note:** After installation, add `$HOME/.cargo/bin` to your PATH or run `source $HOME/.cargo/env` in each shell session.

### Go Toolchain

**Installation:**
```bash
# Download Go 1.22.0 or later
cd /tmp
wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz
rm go1.22.0.linux-amd64.tar.gz

# Add to PATH (add to ~/.bashrc or ~/.profile)
export PATH=$PATH:/usr/local/go/bin
```

**Verified Version:**
- Go: 1.22.0 or later (minimum 1.20)

## System Configuration

### TPM Access (TSS Group)

Users must be in the `tss` group to access TPM devices:

```bash
# Create group if it doesn't exist
sudo groupadd -r tss

# Add user to group
sudo usermod -a -G tss $USER

# Log out and back in for changes to take effect
```

**Verify membership:**
```bash
groups | grep tss
```

### Environment Variables

Ensure the following are in your PATH:
- `/usr/local/go/bin` (Go toolchain)
- `$HOME/.cargo/bin` (Rust toolchain)
- `/usr/local/sbin:/usr/local/bin` (system binaries)

Add to `~/.bashrc` or `~/.profile`:
```bash
export PATH=$PATH:/usr/local/go/bin:$HOME/.cargo/bin
```

## Verification

After installation, verify all prerequisites are installed:

```bash
# Check system packages
dpkg -l | grep -E "(tpm2|swtpm|libtss2|libssl-dev|python3-dev|build-essential|libclang)"

# Check toolchains
python3 --version    # Should show 3.10+
rustc --version      # Should show 1.91+
go version           # Should show go1.22+

# Check Python packages
python3 -m pip list | grep -E "(spiffe|cryptography|grpcio|protobuf)"

# Check TPM access
groups | grep tss    # Should show tss group
```

## Troubleshooting

### Rust not found after installation
```bash
source $HOME/.cargo/env
# Or add to ~/.bashrc:
echo 'source $HOME/.cargo/env' >> ~/.bashrc
```

### Go not found after installation
```bash
export PATH=$PATH:/usr/local/go/bin
# Or add to ~/.bashrc:
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
```

### TPM access denied
1. Verify user is in `tss` group: `groups | grep tss`
2. If not, add user: `sudo usermod -a -G tss $USER`
3. Log out and back in
4. Verify TPM device: `ls -l /dev/tpm*`

### Python packages not found
```bash
# Upgrade pip first
python3 -m pip install --upgrade pip

# Install packages
python3 -m pip install spiffe cryptography grpcio protobuf requests
```

### Missing development libraries
If build fails, ensure development packages are installed:
```bash
sudo apt-get install -y libtss2-dev libssl-dev python3-dev libclang-dev
```

## Package Comparison: Working vs Non-Working Systems

### Key Differences Found

**10.1.0.11 (Working System):**
- ✅ Rust toolchain installed (1.91.1)
- ✅ Go 1.22.0
- ✅ libtss2-dev installed
- ✅ swtpm package installed and in PATH
- ✅ tpm2-abrmd installed
- ✅ libclang-dev packages installed
- ✅ Python requests 2.31.0

**10.1.0.10 (Previously Non-Working):**
- ❌ Rust toolchain missing
- ❌ Go 1.18.1 (older version)
- ❌ libtss2-dev missing (runtime libs only)
- ❌ swtpm not in PATH
- ❌ tpm2-abrmd missing
- ❌ libclang-dev packages missing
- ❌ Python requests 2.25.1 (older version)

**After running `install_prerequisites.sh`:**
- ✅ All missing packages installed
- ✅ Rust toolchain installed
- ✅ Go updated to 1.22.0
- ✅ All Python packages updated

## Additional Resources

- [SPIRE Documentation](https://spiffe.io/docs/latest/spire/)
- [Keylime Documentation](https://keylime.readthedocs.io/)
- [Rust Installation](https://rustup.rs/)
- [Go Installation](https://golang.org/doc/install)
- [TPM2 Tools Documentation](https://github.com/tpm2-software/tpm2-tools)
