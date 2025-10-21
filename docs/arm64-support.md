# ARM64 Support for AegisEdgeAI

This document provides comprehensive guidance for setting up and running AegisEdgeAI on ARM64 architecture systems.

## Overview

AegisEdgeAI now supports ARM64 (aarch64) architecture on Linux systems, enabling deployment on:
- ARM64 cloud instances (AWS Graviton, Google Tau T2A, Azure Ampere)
- Edge devices with ARM processors
- Raspberry Pi with TPM modules
- ARM-based development boards

## Prerequisites

### Hardware Requirements
- ARM64/aarch64 processor
- Minimum 2GB RAM (4GB+ recommended)
- Hardware TPM 2.0 chip (optional, software TPM will be used as fallback)
- Network connectivity for downloading dependencies

### Software Requirements
- Linux distribution with ARM64 support:
  - Ubuntu 20.04+ ARM64
  - RHEL 8+ ARM64
  - Fedora 35+ ARM64
  - Debian 11+ ARM64
- Python 3.8+
- Git
- Build tools (gcc, make, autotools)

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/lfedgeai/AegisEdgeAI.git
cd AegisEdgeAI
```

### 2. ARM64-Specific Setup

#### Option A: Automated Setup (Recommended)
```bash
# Run the ARM64-specific installer
sudo ./zero-trust/system-setup-arm64.sh

# Source the ARM64 environment
source /etc/profile.d/arm64-tpm-env.sh
```

#### Option B: Standard Setup with ARM64 Detection
```bash
# The standard setup script now detects ARM64 automatically
./zero-trust/system-setup.sh
```

### 3. Install Python Dependencies
```bash
pip install -r zero-trust/requirements.txt
```

### 4. Test TPM Functionality
```bash
# Start software TPM
./zero-trust/tpm/swtpm.sh

# Test TPM operations
./zero-trust/tpm/tpm-ek-ak-persist.sh
```

## Detailed Setup Instructions

### Architecture Detection

The system automatically detects ARM64 architecture using:
```bash
ARCH=$(uname -m)  # Returns 'aarch64' or 'arm64'
```

### Package Installation Strategy

1. **Try system packages first**: Attempts to install TPM stack from distribution packages
2. **Fallback to compilation**: If packages unavailable, compiles from source
3. **Custom paths**: Uses `/usr/local` prefix for compiled components

### TPM Stack Components

The following components are installed/compiled for ARM64:

#### libtpms
- **Source**: https://github.com/stefanberger/libtpms
- **Purpose**: TPM library implementation
- **ARM64 Status**: ✅ Fully supported

#### swtpm
- **Source**: https://github.com/stefanberger/swtpm
- **Purpose**: Software TPM emulator
- **ARM64 Status**: ✅ Fully supported

#### tpm2-tss
- **Source**: https://github.com/tpm2-software/tpm2-tss
- **Purpose**: TPM 2.0 System Software stack
- **ARM64 Status**: ✅ Fully supported

#### tpm2-tools
- **Source**: https://github.com/tpm2-software/tpm2-tools
- **Purpose**: Command-line tools for TPM 2.0
- **ARM64 Status**: ✅ Fully supported

## Testing Procedures

### Basic Functionality Test
```bash
# 1. Check architecture detection
uname -m
# Should output: aarch64 or arm64

# 2. Verify TPM tools installation
which swtpm
which tpm2_createprimary
tpm2_createprimary --version

# 3. Test software TPM
cd zero-trust/tpm
./swtpm.sh
# Should start TPM and show properties

# 4. Test key operations
./tpm-ek-ak-persist.sh
# Should create and persist EK/AK keys
```

### Compilation Test
```bash
# Test ARM64 compilation of C components
cd zero-trust/tpm
make clean
make
# Should compile successfully for ARM64

# Verify binary architecture
file tpm-app-persist
# Should show: ELF 64-bit LSB executable, ARM aarch64
```

### Full System Test
```bash
# Test complete zero-trust system
cd zero-trust

# Start services
./initall.sh

# Run end-to-end test
./test_end_to_end_flow.sh
```

## Hardware TPM Support

### Checking for Hardware TPM
```bash
# Check for TPM device
ls -la /dev/tpm*

# Check TPM status
dmesg | grep -i tpm

# Check loaded TPM modules
lsmod | grep tpm
```

### Common ARM64 TPM Devices
- **Raspberry Pi**: TPM modules available via GPIO
- **ARM64 servers**: Many include discrete TPM chips
- **Edge devices**: Various TPM implementations

### Configuring Hardware TPM
```bash
# Set TPM device for hardware TPM
export TPM2TOOLS_TCTI="device:/dev/tpm0"

# Test hardware TPM
tpm2 getcap properties-fixed
```

## Troubleshooting

### Common Issues

#### 1. Package Installation Failures
```bash
# Error: Package 'swtpm' not found
# Solution: Let the script compile from source
export COMPILE_SWTPM=1
./zero-trust/system-setup-arm64.sh
```

#### 2. Library Path Issues
```bash
# Error: libtss2-esys.so.0: cannot open shared object file
# Solution: Update library cache and paths
sudo ldconfig
export LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"
```

#### 3. Compilation Errors
```bash
# Error: No package 'tss2-esys' found
# Solution: Install development packages
sudo apt install -y libtss2-dev  # Ubuntu
sudo dnf install -y tpm2-tss-devel  # RHEL/Fedora
```

#### 4. Permission Issues
```bash
# Error: Permission denied accessing TPM device
# Solution: Add user to tss group
sudo usermod -a -G tss $USER
# Logout and login again
```

### Debug Mode
```bash
# Enable debug output
export TPM2_DEBUG=1
export SWTPM_DEBUG=1

# Run with verbose output
./zero-trust/tpm/swtpm.sh
```

### Log Locations
- **swtpm logs**: `~/.swtpm/ztpm/`
- **System logs**: `/var/log/syslog` or `journalctl -u swtpm`
- **Build logs**: `/tmp/aegis-arm64-build/`

## Performance Considerations

### ARM64 Optimization
- **Compiler flags**: `-march=armv8-a` for optimal performance
- **Memory usage**: ARM64 may use less memory than x86_64
- **Cryptographic operations**: Hardware acceleration available on many ARM64 chips

### Benchmarking
```bash
# Time TPM operations
time tpm2_createprimary -C e -c primary.ctx

# Benchmark key generation
time tpm2_create -C primary.ctx -u key.pub -r key.priv

# Test signature performance
time tpm2_sign -c signing_key.ctx -o signature.dat message.txt
```

## Cloud Deployment

### AWS Graviton
```bash
# Launch ARM64 instance
aws ec2 run-instances \
  --image-id ami-0xxxxx \  # ARM64 AMI
  --instance-type c7g.large \
  --architecture arm64

# Install and configure
sudo ./zero-trust/system-setup-arm64.sh
```

### Google Cloud T2A
```bash
# Create ARM64 VM
gcloud compute instances create aegis-arm64 \
  --machine-type=t2a-standard-2 \
  --image-family=ubuntu-2204-lts-arm64 \
  --image-project=ubuntu-os-cloud

# Setup AegisEdgeAI
./zero-trust/system-setup-arm64.sh
```

### Azure Ampere
```bash
# Create ARM64 VM
az vm create \
  --resource-group myResourceGroup \
  --name aegis-arm64 \
  --size Standard_D2ps_v5 \
  --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts-arm64:latest

# Configure system
./zero-trust/system-setup-arm64.sh
```

## Development Guidelines

### Building for ARM64
```bash
# Cross-compilation for ARM64
export CC=aarch64-linux-gnu-gcc
export ARCH=aarch64

# Build with ARM64 optimizations
make ARCH=aarch64
```

### Testing on Multiple Architectures
```bash
# Use Docker for multi-arch testing
docker buildx create --use
docker buildx build --platform linux/arm64,linux/amd64 -t aegis:latest .
```

### CI/CD Integration
```bash
# GitHub Actions ARM64 runner
runs-on: [self-hosted, linux, ARM64]

# Build and test
- name: Setup ARM64 Environment
  run: ./zero-trust/system-setup-arm64.sh

- name: Run Tests
  run: ./test_end_to_end_flow.sh
```

## Limitations and Known Issues

### Current Limitations
1. **Hardware TPM support**: Varies by ARM64 device manufacturer
2. **Performance**: May be slower than x86_64 for some cryptographic operations
3. **Package availability**: Some distributions may lack ARM64 TPM packages

### Known Issues
1. **Build time**: Compilation from source takes longer on ARM64
2. **Memory usage**: Some TPM operations may require more memory on certain ARM64 chips
3. **Network latency**: Edge devices may have higher latency affecting distributed operations

### Planned Improvements
- [ ] Pre-built ARM64 packages
- [ ] Hardware TPM auto-detection
- [ ] Performance optimizations
- [ ] Container images for ARM64
- [ ] Kubernetes Helm charts with ARM64 support

## Support and Contributing

### Getting Help
- **Issues**: Report ARM64-specific issues on GitHub
- **Discussions**: Join community discussions for ARM64 deployment
- **Documentation**: Contribute to ARM64 documentation improvements

### Contributing ARM64 Enhancements
1. Test on different ARM64 platforms
2. Submit patches for hardware-specific optimizations
3. Improve build system for cross-compilation
4. Add support for additional ARM64 distributions

## Appendix

### Environment Variables
```bash
# ARM64-specific environment variables
export PREFIX="/usr/local"
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"
export LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"
export PATH="/usr/local/bin:$PATH"
export TPM2TOOLS_TCTI="swtpm:host=127.0.0.1,port=2321"
```

### File Locations
```
/etc/profile.d/arm64-tpm-env.sh          # ARM64 environment setup
/usr/local/bin/swtpm                     # Software TPM binary
/usr/local/bin/tmp2_*                    # TPM2 tools
/usr/local/lib/libtss2-*.so              # TPM2 libraries
/var/lib/swtpm-localca/                  # TPM state directory
```

### Version Information
- **Minimum kernel version**: 4.19+ for TPM 2.0 support
- **Recommended kernel**: 5.4+ for optimal ARM64 performance
- **Python version**: 3.8+ (ARM64 wheels available)
- **GCC version**: 8.0+ for ARM64 compilation