#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Variables
HOST_IP=$(hostname -I | awk '{print $1}')
ALLOY_PORT=8080 
ALLOY_CONFIG_URL="http://10.0.34.144/config.alloy"
API_ENDPOINT="https://10.0.34.181:8000/api/v1/agents/"

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to install packages
install_package() {
    if ! dpkg -l | grep -q "$1"; then
        log "Installing $1..."
        sudo apt-get install -y "$1"
    else
        log "$1 is already installed."
    fi
}

# Update and install packages
log "Updating package lists..."
sudo apt-get update -y

install_package gpg
install_package acl
# install_package alloy || { log "Alloy package not found. Please install manually."; exit 1; }

# Setup Grafana repository
log "Setting up Grafana repository..."
sudo mkdir -p /etc/apt/keyrings
sudo chmod 0755 /etc/apt/keyrings

if [ ! -f "/etc/apt/keyrings/grafana.gpg" ]; then
    curl -fsSL https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
fi

if [ ! -f "/etc/apt/sources.list.d/grafana.list" ]; then
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null
fi

# Update package lists again to include the new repository
log "Updating package lists with new repository..."
sudo apt-get update -y

# Now install Alloy
log "Installing Alloy..."
install_package alloy || { log "Alloy package not found. Please check the repository setup."; exit 1; }

# Setup Alloy
log "Setting up Alloy..."
sudo mkdir -p /etc/alloy
sudo chmod 0755 /etc/alloy

[ -f "/etc/alloy/config.alloy" ] && sudo cp /etc/alloy/config.alloy /etc/alloy/config.alloy.backup

log "Setting ACL for alloy user on /var/log..."
sudo setfacl -dR -m u:alloy:r /var/log/

log "Downloading the Alloy config file..."
sudo curl -fsSL -o /etc/alloy/config.alloy "$ALLOY_CONFIG_URL" || { log "Failed to download config file"; exit 1; }

# Setup Alloy service
log "Setting up Alloy service..."
cat << EOF | sudo tee /etc/systemd/system/alloy.service > /dev/null
[Unit]
Description=Alloy Service
After=network.target

[Service]
ExecStart=/usr/bin/alloy
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable alloy
sudo systemctl start alloy

log "Alloy service status:"
sudo systemctl status alloy

# Create new agent
log "Creating new agent..."
response=$(curl -s -w "\n%{http_code}" -X POST "$API_ENDPOINT" \
    -H "Content-Type: application/json" \
    -d '{
        "host_name": "'"$HOSTNAME"'",
        "ip_port": "'"$HOST_IP:$ALLOY_PORT"'",
        "keycloak_id": "'"$OMEGA_UID"'",
        "agent_name": "'"$AGENT_NAME"'",
        "status": "Active"
    }')

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

log "Response Code: $http_code"
log "Response Body: $body"

if [[ "$http_code" == "201" ]]; then
    log "Agent created successfully."
elif [[ "$body" == *"UNIQUE constraint failed"* ]]; then
    log "ERROR: IP:PORT combination already exists"
else
    log "Agent creation failed. Response code: $http_code"
    log "Full response body: $body"
fi
