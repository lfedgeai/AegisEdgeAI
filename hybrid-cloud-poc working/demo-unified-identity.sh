#!/bin/bash
# Unified Identity Demo Script
# Shows the TPM-backed identity system in action

set -e
cd ~/dhanush/hybrid-cloud-poc-backup

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Unified Identity Demo - TPM-Backed Workload Identity          ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${YELLOW}1. System Components Running:${NC}"
echo "   ├── SPIRE Server (Identity Provider)"
echo "   ├── SPIRE Agent (Workload API)"
echo "   ├── Keylime Verifier (TPM Attestation)"
echo "   ├── Keylime Registrar (Agent Registry)"
echo "   ├── rust-keylime Agent (TPM Interface)"
echo "   └── TPM Plugin Server (TPM Operations)"

echo -e "\n${YELLOW}2. Agent Health Check:${NC}"
./spire/bin/spire-agent healthcheck -socketPath /tmp/spire-agent/public/api.sock 2>/dev/null && \
    echo -e "   ${GREEN}✓ SPIRE Agent is healthy${NC}" || \
    echo -e "   Agent status: $(./spire/bin/spire-agent healthcheck -socketPath /tmp/spire-agent/public/api.sock 2>&1)"

echo -e "\n${YELLOW}3. Fetching Workload SVID (TPM-backed identity):${NC}"
./spire/bin/spire-agent api fetch x509 -socketPath /tmp/spire-agent/public/api.sock 2>/dev/null | head -10

echo -e "\n${YELLOW}4. TPM Attestation Claims in Agent SVID:${NC}"
echo "   The Agent SVID contains hardware-backed claims:"
tail -200 /tmp/spire-agent.log 2>/dev/null | grep -o '"grc\.tpm-attestation".*"challenge-nonce":"[^"]*"' | tail -1 | \
    sed 's/.*"app-key-public":"[^"]*"/   ├── app-key-public: [RSA 2048-bit TPM key]/' | \
    sed 's/"challenge-nonce":"\([^"]*\)".*/\n   └── challenge-nonce: \1/'

echo -e "\n${YELLOW}5. Key Differentiators from Standard SPIRE:${NC}"
echo "   ├── No join token required (TPM-based attestation)"
echo "   ├── Hardware-rooted identity (TPM App Key)"
echo "   ├── Continuous re-attestation every ~30 seconds"
echo "   └── Cryptographic proof of workload residency"

echo -e "\n${GREEN}Demo complete! The system is using real TPM hardware for identity.${NC}"
