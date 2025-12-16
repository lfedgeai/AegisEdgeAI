#!/bin/bash
# Unified Identity - Stop All Services
# Usage: ./stop-unified-identity.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Stopping Unified Identity Services                            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${YELLOW}Stopping services...${NC}"

# Stop in reverse order
echo "  Stopping SPIRE Agent..."
pkill -f spire-agent 2>/dev/null && echo -e "  ${GREEN}✓${NC} SPIRE Agent stopped" || echo "  - SPIRE Agent not running"

echo "  Stopping SPIRE Server..."
pkill -f spire-server 2>/dev/null && echo -e "  ${GREEN}✓${NC} SPIRE Server stopped" || echo "  - SPIRE Server not running"

echo "  Stopping TPM Plugin Server..."
pkill -f tpm_plugin_server 2>/dev/null && echo -e "  ${GREEN}✓${NC} TPM Plugin Server stopped" || echo "  - TPM Plugin Server not running"

echo "  Stopping rust-keylime Agent..."
pkill -f keylime_agent 2>/dev/null && echo -e "  ${GREEN}✓${NC} rust-keylime Agent stopped" || echo "  - rust-keylime Agent not running"

echo "  Stopping Keylime Registrar..."
pkill -f "keylime.cmd.registrar" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Keylime Registrar stopped" || echo "  - Keylime Registrar not running"

echo "  Stopping Keylime Verifier..."
pkill -f "keylime.cmd.verifier" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Keylime Verifier stopped" || echo "  - Keylime Verifier not running"

sleep 2

# Verify all stopped
echo -e "\n${YELLOW}Verifying...${NC}"
REMAINING=$(ps aux | grep -E "spire|keylime|tpm_plugin" | grep -v grep | wc -l)
if [ "$REMAINING" -eq 0 ]; then
    echo -e "${GREEN}✓ All services stopped${NC}"
else
    echo -e "${YELLOW}⚠ Some processes may still be running:${NC}"
    ps aux | grep -E "spire|keylime|tpm_plugin" | grep -v grep
fi

echo -e "\n${CYAN}To restart: ./start-unified-identity.sh${NC}"
echo -e "${CYAN}To restart clean: ./start-unified-identity.sh --clean${NC}"
