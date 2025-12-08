# SPIRE TPM Plugin Binaries

This directory contains TPM application binaries that work with the SPIRE server for hardware-based attestation.

## Building

The Makefile in this directory supports building for both x86-64 and ARM64 (aarch64) architectures.

### Prerequisites

Install the required development libraries:

**For Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install -y build-essential
sudo apt install -y libtss2-dev
sudo apt install -y libssl-dev
```

**For RHEL/CentOS:**
```bash
sudo dnf install -y gcc make
sudo dnf install -y tpm2-tss-devel
sudo dnf install -y openssl-devel
```

### Build Commands

```bash
# Build all binaries
make

# Clean build artifacts
make clean
```

The Makefile automatically detects your system architecture and builds the appropriate binaries:
- On x86-64 systems: Builds x86-64 binaries
- On ARM64 (aarch64) systems: Builds ARM64 binaries

## Binaries

- **tpm-app-persist**: Persists TPM keys and contexts
- **tpm-app-evict**: Evicts TPM objects from persistent storage
- **tpm-app-sign**: Signs data using TPM keys
- **tpm-app-selftest**: Runs TPM self-tests

## Architecture Support

This project supports the following architectures:
- x86-64 (Intel/AMD 64-bit)
- ARM64/aarch64 (ARM 64-bit)

The build system automatically detects the target architecture and applies appropriate compiler flags.
