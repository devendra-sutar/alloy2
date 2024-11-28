#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Detect operating system
log "Detecting the operating system..."
if grep -Ei 'ubuntu|debian' /etc/os-release > /dev/null; then
    OS="debian"
    PKG_MANAGER="apt-get"
    INSTALL_CMD="sudo apt-get install -y"
    UPDATE_CMD="sudo apt-get update -y"
elif grep -Ei 'suse' /etc/os-release > /dev/null; then
    OS="suse"
    PKG_MANAGER="zypper"
    INSTALL_CMD="sudo zypper install -y"
    UPDATE_CMD="sudo zypper refresh"
elif grep -Ei 'fedora|red hat|centos|rhel' /etc/os-release > /dev/null; then
    OS="redhat"
    PKG_MANAGER="yum"
    INSTALL_CMD="sudo yum install -y || sudo dnf install -y"
    UPDATE_CMD="sudo yum update -y || sudo dnf update -y"
else
    log "Unsupported operating system."
    exit 1
fi

log "Operating system detected: $OS"

# Variables
GITHUB_REPO="https://api.github.com/repos/example/alloy/releases/latest"
ALLOY_INSTALL_DIR="/usr/local/bin"
ALLOY_CONFIG_URL="http://10.0.34.144/config.alloy"
API_ENDPOINT="https://10.0.34.181:8000/api/v1/agents/"
HOST_IP=$(hostname -I | awk '{print $1}')
ALLOY_PORT=8080

# Function to install packages
install_package() {
    if [ "$OS" == "debian" ]; then
        if ! dpkg -l | grep -q "$1"; then
            log "Installing $1..."
            $INSTALL_CMD "$1"
        else
            log "$1 is already installed."
        fi
    elif [ "$OS" == "suse" ] || [ "$OS" == "redhat" ]; then
        if ! rpm -q "$1" > /dev/null; then
            log "Installing $1..."
            $INSTALL_CMD "$1"
        else
            log "$1 is already installed."
        fi
    fi
}

# Update and install prerequisites
log "Updating repositories..."
$UPDATE_CMD

install_package curl
install_package tar
install_package acl

# Download and install Alloy from GitHub
log "Downloading the latest release of Alloy from GitHub..."
response=$(curl -s "$GITHUB_REPO")
download_url=$(echo "$response" | grep "browser_download_url" | grep "linux" | cut -d '"' -f 4)

if [ -z "$download_url" ]; then
    log "Failed to find a download URL for the latest release."
    exit 1
fi

log "Download URL: $download_url"
temp_dir=$(mktemp -d)
curl -L -o "$temp_dir/alloy.tar.gz" "$download_url"

log "Extracting Alloy..."
sudo tar -xzf "$temp_dir/alloy.tar.gz" -C "$ALLOY_INSTALL_DIR"

log "Cleaning up..."
rm -rf "$temp_dir"

# Ensure Alloy binary is executable
sudo chmod +x "$ALLOY_INSTALL_DIR/alloy"

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
ExecStart=$ALLOY_INSTALL_DIR/alloy
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
