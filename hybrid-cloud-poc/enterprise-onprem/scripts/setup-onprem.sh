#!/bin/bash
# Setup script for enterprise on-prem (10.1.0.10)
# Sets up: Envoy proxy, mTLS server, mobile location service, sensor ID extractor

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ONPREM_DIR="$REPO_ROOT/enterprise-onprem"

echo "=========================================="
echo "Enterprise On-Prem Setup (10.1.0.10)"
echo "=========================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}Warning: Not running as root. Some operations may require sudo.${NC}"
fi

# 1. Install dependencies
echo -e "\n${GREEN}[1/6] Installing dependencies...${NC}"
if command -v apt-get &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y \
        python3 python3-pip python3-venv \
        curl wget \
        docker.io docker-compose || true
elif command -v yum &> /dev/null; then
    sudo yum install -y \
        python3 python3-pip \
        curl wget \
        docker docker-compose || true
fi

# Install Envoy
if ! command -v envoy &> /dev/null; then
    echo -e "${YELLOW}Installing Envoy...${NC}"
    curl -sL 'https://getenvoy.io/gpg' | sudo apt-key add -
    curl -sL 'https://getenvoy.io/install.sh' | sudo bash -s -- -b /usr/local/bin
fi

# 2. Create directories
echo -e "\n${GREEN}[2/6] Creating directories...${NC}"
sudo mkdir -p /opt/envoy/{certs,plugins,logs}
sudo mkdir -p /opt/mobile-sensor-service
sudo mkdir -p /opt/sensor-id-extractor
sudo mkdir -p /opt/mtls-server

# 3. Setup certificates
echo -e "\n${GREEN}[3/6] Setting up certificates...${NC}"
echo -e "${YELLOW}Note: You need to copy the following files:${NC}"
echo "  - SPIRE CA bundle: /tmp/spire-bundle.pem -> /opt/envoy/certs/spire-bundle.pem"
echo "  - Server cert: ~/.mtls-demo/server-cert.pem -> /opt/envoy/certs/server-cert.pem"
echo "  - Server key: ~/.mtls-demo/server-key.pem -> /opt/envoy/certs/server-key.pem"
echo ""
read -p "Press Enter after copying certificates, or 's' to skip: " answer
if [ "$answer" != "s" ]; then
    if [ ! -f /opt/envoy/certs/spire-bundle.pem ]; then
        echo -e "${RED}Error: /opt/envoy/certs/spire-bundle.pem not found${NC}"
        exit 1
    fi
    if [ ! -f /opt/envoy/certs/server-cert.pem ]; then
        echo -e "${RED}Error: /opt/envoy/certs/server-cert.pem not found${NC}"
        exit 1
    fi
    if [ ! -f /opt/envoy/certs/server-key.pem ]; then
        echo -e "${RED}Error: /opt/envoy/certs/server-key.pem not found${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Certificates found${NC}"
fi

# 4. Setup mobile location service
echo -e "\n${GREEN}[4/6] Setting up mobile location service...${NC}"
cd "$REPO_ROOT/mobile-sensor-microservice"
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate
pip install -q -r requirements.txt

# Create systemd service
sudo tee /etc/systemd/system/mobile-sensor-service.service > /dev/null <<EOF
[Unit]
Description=Mobile Location Verification Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$REPO_ROOT/mobile-sensor-microservice
Environment="PATH=$REPO_ROOT/mobile-sensor-microservice/.venv/bin:$PATH"
ExecStart=$REPO_ROOT/mobile-sensor-microservice/.venv/bin/python3 service.py --port 5000 --host 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 5. Setup sensor ID extractor
echo -e "\n${GREEN}[5/6] Setting up sensor ID extractor...${NC}"
cd "$ONPREM_DIR/sensor-id-extractor"
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate
pip install -q flask cryptography

# Create systemd service
sudo tee /etc/systemd/system/sensor-id-extractor.service > /dev/null <<EOF
[Unit]
Description=Sensor ID Extractor Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$ONPREM_DIR/sensor-id-extractor
Environment="PATH=$ONPREM_DIR/sensor-id-extractor/.venv/bin:$PATH"
ExecStart=$ONPREM_DIR/sensor-id-extractor/.venv/bin/python3 extract_sensor_id.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 6. Setup Envoy
echo -e "\n${GREEN}[6/6] Setting up Envoy proxy...${NC}"
sudo cp "$ONPREM_DIR/envoy/envoy.yaml" /opt/envoy/envoy.yaml

# Create systemd service
sudo tee /etc/systemd/system/envoy-proxy.service > /dev/null <<EOF
[Unit]
Description=Envoy Proxy
After=network.target mobile-sensor-service.service sensor-id-extractor.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/envoy -c /opt/envoy/envoy.yaml --log-path /opt/envoy/logs/envoy.log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
echo -e "\n${GREEN}Enabling and starting services...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable mobile-sensor-service
sudo systemctl enable sensor-id-extractor
sudo systemctl enable envoy-proxy

echo -e "\n${GREEN}=========================================="
echo "Setup complete!"
echo "==========================================${NC}"
echo ""
echo "To start services:"
echo "  sudo systemctl start mobile-sensor-service"
echo "  sudo systemctl start sensor-id-extractor"
echo "  sudo systemctl start envoy-proxy"
echo ""
echo "To check status:"
echo "  sudo systemctl status mobile-sensor-service"
echo "  sudo systemctl status sensor-id-extractor"
echo "  sudo systemctl status envoy-proxy"
echo ""
echo "To view logs:"
echo "  sudo journalctl -u mobile-sensor-service -f"
echo "  sudo journalctl -u sensor-id-extractor -f"
echo "  sudo journalctl -u envoy-proxy -f"

