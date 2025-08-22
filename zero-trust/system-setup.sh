#!/bin/bash

# install swtpm
# install tpm2-tools

if [ -f /etc/redhat-release ]; then
  echo "RHEL system setup..."
  sudo dnf install -y swtpm
  sudo dnf install -y tpm2-tools
  sudo dnf install -y vim-common
elif [ -f /etc/lsb-release ]; then
  echo "Ubuntu system setup..."
  sudo apt update
  sudo apt install -y swtpm
  sudo apt install -y tpm2-tools
else
  echo "Unsupported or unknown Linux distribution."
  exit 1
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
