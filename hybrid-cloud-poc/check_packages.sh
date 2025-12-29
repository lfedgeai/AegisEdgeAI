#!/bin/bash

# Copyright 2025 AegisSovereignAI Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Script to check installed packages and versions
# Usage: ./check_packages.sh [host_ip]
# If host_ip is provided, will SSH to that host and check packages there
# Otherwise checks local system

set -e

HOST_IP="${1:-}"
SSH_USER="${SSH_USER:-$USER}"

if [ -n "$HOST_IP" ]; then
    echo "Checking packages on remote host: $HOST_IP"
    SSH_CMD="ssh ${SSH_USER}@${HOST_IP}"
else
    echo "Checking packages on local system"
    SSH_CMD=""
fi

run_cmd() {
    if [ -n "$SSH_CMD" ]; then
        $SSH_CMD "$1"
    else
        eval "$1"
    fi
}

echo "=========================================="
echo "System Information"
echo "=========================================="
run_cmd "cat /etc/os-release | grep -E '^PRETTY_NAME|^VERSION_ID|^ID='"

echo ""
echo "=========================================="
echo "Linux Packages (System)"
echo "=========================================="

# Check essential system packages
echo "--- Essential System Packages ---"
run_cmd "dpkg -l | grep -E '^ii.*(curl|wget|git|vim|net-tools|iproute2|iputils-ping|dnsutils|ca-certificates)' || echo 'Some packages not found'"

echo ""
echo "--- TPM2 Tools ---"
run_cmd "dpkg -l | grep -E '^ii.*tpm2' || echo 'TPM2 packages not found'"
run_cmd "which tpm2_getcap tpm2_create tpm2_load tpm2_sign tpm2_verifysignature 2>/dev/null | head -5 || echo 'TPM2 tools not in PATH'"

echo ""
echo "--- TPM2 Libraries ---"
run_cmd "dpkg -l | grep -E '^ii.*(libtss2|tpm2-tss)' || echo 'TPM2 libraries not found'"
run_cmd "pkg-config --modversion tss2-esys 2>/dev/null || echo 'tss2-esys pkg-config not found'"

echo ""
echo "--- Software TPM ---"
run_cmd "dpkg -l | grep -E '^ii.*swtpm' || echo 'swtpm not found'"
run_cmd "which swtpm 2>/dev/null || echo 'swtpm not in PATH'"
run_cmd "swtpm --version 2>/dev/null | head -1 || echo 'swtpm version check failed'"

echo ""
echo "--- OpenSSL ---"
run_cmd "dpkg -l | grep -E '^ii.*(libssl|openssl)' | head -3"
run_cmd "openssl version 2>/dev/null || echo 'openssl not found'"

echo ""
echo "--- Build Tools ---"
run_cmd "dpkg -l | grep -E '^ii.*(build-essential|gcc|g\+\+|make|cmake|pkg-config|libclang)' || echo 'Build tools not found'"
run_cmd "gcc --version | head -1 || echo 'gcc not found'"
run_cmd "g++ --version | head -1 || echo 'g++ not found'"
run_cmd "pkg-config --version 2>/dev/null || echo 'pkg-config not found'"

echo ""
echo "--- Rust Toolchain ---"
run_cmd "which rustc cargo 2>/dev/null || echo 'Rust not in PATH'"
run_cmd "rustc --version 2>/dev/null || echo 'rustc not found'"
run_cmd "cargo --version 2>/dev/null || echo 'cargo not found'"

echo ""
echo "--- Go Toolchain ---"
run_cmd "which go 2>/dev/null || echo 'Go not in PATH'"
run_cmd "go version 2>/dev/null || echo 'go not found'"

echo ""
echo "--- Network Tools ---"
run_cmd "which netstat ss lsof curl wget 2>/dev/null | head -5 || echo 'Some network tools not found'"
run_cmd "netstat --version 2>/dev/null | head -1 || echo 'netstat version check failed'"
run_cmd "ss -V 2>/dev/null | head -1 || echo 'ss version check failed'"

echo ""
echo "=========================================="
echo "Python Environment"
echo "=========================================="

echo "--- Python Version ---"
run_cmd "python3 --version 2>/dev/null || echo 'python3 not found'"
run_cmd "python3 -m pip --version 2>/dev/null || echo 'pip3 not found'"

echo ""
echo "--- Python System Packages ---"
run_cmd "dpkg -l | grep -E '^ii.*python3' | grep -E '(python3-dev|python3-pip|python3-venv|python3-distutils)' || echo 'Python dev packages not found'"

echo ""
echo "--- Python Installed Packages (pip) ---"
run_cmd "python3 -m pip list 2>/dev/null | grep -E '(spiffe|cryptography|grpcio|protobuf|requests|flask|opentelemetry)' || echo 'Key Python packages not found via pip'"

echo ""
echo "--- Python Package Versions (Key Packages) ---"
run_cmd "python3 -m pip show spiffe 2>/dev/null | grep -E '^Name|^Version' || echo 'spiffe not installed'"
run_cmd "python3 -m pip show cryptography 2>/dev/null | grep -E '^Name|^Version' || echo 'cryptography not installed'"
run_cmd "python3 -m pip show grpcio 2>/dev/null | grep -E '^Name|^Version' || echo 'grpcio not installed'"
run_cmd "python3 -m pip show protobuf 2>/dev/null | grep -E '^Name|^Version' || echo 'protobuf not installed'"

echo ""
echo "=========================================="
echo "SPIRE & Keylime Components"
echo "=========================================="

echo "--- SPIRE Server Binary ---"
run_cmd "test -f hybrid-cloud-poc/spire/bin/spire-server && echo 'SPIRE server binary found' || echo 'SPIRE server binary not found'"
run_cmd "test -f hybrid-cloud-poc/spire/bin/spire-agent && echo 'SPIRE agent binary found' || echo 'SPIRE agent binary not found'"

echo ""
echo "--- Keylime Components ---"
run_cmd "test -f hybrid-cloud-poc/keylime/keylime_verifier.py && echo 'Keylime verifier found' || echo 'Keylime verifier not found'"
run_cmd "test -f hybrid-cloud-poc/keylime/keylime_registrar.py && echo 'Keylime registrar found' || echo 'Keylime registrar not found'"
run_cmd "test -f hybrid-cloud-poc/rust-keylime/target/release/keylime_agent && echo 'rust-keylime agent binary found' || echo 'rust-keylime agent binary not found'"

echo ""
echo "=========================================="
echo "System Groups & Permissions"
echo "=========================================="

echo "--- TSS Group (for TPM access) ---"
run_cmd "getent group tss 2>/dev/null && echo 'TSS group exists' || echo 'TSS group not found'"
run_cmd "groups | grep -q tss && echo 'User is in tss group' || echo 'User is NOT in tss group'"

echo ""
echo "=========================================="
echo "Environment Variables"
echo "=========================================="
run_cmd "env | grep -E '(PATH|RUST|GO|PYTHON|TPM|SPIRE|KEYLIME)' | sort"

echo ""
echo "=========================================="
echo "Check Complete"
echo "=========================================="
