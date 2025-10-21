#!/bin/bash

# install swtpm
# install tpm2-tools

# Detect system architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Architecture-specific settings
case "$ARCH" in
  x86_64)
    echo "x86_64 architecture detected - using standard packages"
    ;;
  aarch64|arm64)
    echo "ARM64 architecture detected - checking package availability"
    export ARM64_DETECTED=1
    ;;
  *)
    echo "Warning: Unsupported architecture $ARCH - attempting standard installation"
    ;;
esac

if [ -f /etc/redhat-release ]; then
  echo "RHEL system setup..."
  if [ "$ARM64_DETECTED" = "1" ]; then
    echo "Installing ARM64 packages for RHEL/Fedora..."
    # Try ARM64 packages first, fall back to compilation if needed
    sudo dnf install -y swtpm || { echo "swtpm package not available, will compile from source"; export COMPILE_SWTPM=1; }
    sudo dnf install -y tpm2-tools || { echo "tpm2-tools package not available, will compile from source"; export COMPILE_TPM2_TOOLS=1; }
    sudo dnf install -y tpm2-tss-devel || { echo "tpm2-tss-devel package not available, will compile from source"; export COMPILE_TPM2_TSS=1; }
    sudo dnf install -y openssl-devel
    sudo dnf install -y vim-common
    sudo dnf install -y gcc make autoconf automake libtool pkg-config git cmake
  else
    sudo dnf install -y swtpm
    sudo dnf install -y tpm2-tools
    sudo dnf install -y tpm2-tss-devel
    sudo dnf install -y openssl-devel
    sudo dnf install -y vim-common
  fi
elif [ -f /etc/lsb-release ]; then
  echo "Ubuntu system setup..."
  sudo apt update
  if [ "$ARM64_DETECTED" = "1" ]; then
    echo "Installing ARM64 packages for Ubuntu..."
    # Try ARM64 packages first, fall back to compilation if needed
    sudo apt install -y swtpm || { echo "swtpm package not available, will compile from source"; export COMPILE_SWTPM=1; }
    sudo apt install -y tpm2-tools || { echo "tpm2-tools package not available, will compile from source"; export COMPILE_TPM2_TOOLS=1; }
    sudo apt install -y libtss2-dev || { echo "libtss2-dev package not available, will compile from source"; export COMPILE_TPM2_TSS=1; }
    sudo apt install -y libssl-dev
    sudo apt install -y build-essential autoconf automake libtool pkg-config git cmake
  else
    sudo apt install -y swtpm
    sudo apt install -y tpm2-tools
    sudo apt install -y libtss2-dev
    sudo apt install -y libssl-dev
  fi
else
  echo "Unsupported or unknown Linux distribution."
  exit 1
fi

# Handle ARM64 compilation if packages were not available
if [ "$ARM64_DETECTED" = "1" ] && [ "$COMPILE_SWTPM" = "1" -o "$COMPILE_TPM2_TOOLS" = "1" -o "$COMPILE_TPM2_TSS" = "1" ]; then
  echo "Compiling TPM stack from source for ARM64..."
  
  # Create build directory
  mkdir -p /tmp/tpm-build
  cd /tmp/tpm-build
  
  # Set ARM64-specific build variables
  export PREFIX="/usr/local"
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
  export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
  
  if [ "$COMPILE_TPM2_TSS" = "1" ]; then
    echo "Compiling tpm2-tss for ARM64..."
    git clone https://github.com/tpm2-software/tpm2-tss.git
    cd tpm2-tss
    ./bootstrap
    ./configure --prefix=$PREFIX
    make -j$(nproc)
    sudo make install
    sudo ldconfig
    cd ..
  fi
  
  if [ "$COMPILE_SWTPM" = "1" ]; then
    echo "Compiling libtpms and swtpm for ARM64..."
    # Build libtpms first
    git clone https://github.com/stefanberger/libtpms.git
    cd libtpms
    ./autogen.sh --with-tpm2 --with-openssl --prefix=$PREFIX
    make -j$(nproc)
    sudo make install
    cd ..
    
    # Build swtpm
    git clone https://github.com/stefanberger/swtpm.git
    cd swtpm
    ./autogen.sh --with-tpm2 --with-openssl --prefix=$PREFIX
    make -j$(nproc)
    sudo make install
    cd ..
  fi
  
  if [ "$COMPILE_TPM2_TOOLS" = "1" ]; then
    echo "Compiling tpm2-tools for ARM64..."
    git clone https://github.com/tpm2-software/tpm2-tools.git
    cd tpm2-tools
    ./bootstrap
    ./configure --prefix=$PREFIX
    make -j$(nproc)
    sudo make install
    cd ..
  fi
  
  # Update library cache
  sudo ldconfig
  
  echo "ARM64 TPM stack compilation completed"
  cd ~
fi

# install python packages
pip install -r requirements.txt

# WSL - working software versions 
# swtpm --version
# TPM emulator version 0.6.3, Copyright (c) 2014-2021 IBM Corp.
# tpm2 flushcontext --version
# tool="flushcontext" version="5.2" tctis="libtss2-tctildr" tcti-default=tcti-device
# python --version
# Python 3.10.12
