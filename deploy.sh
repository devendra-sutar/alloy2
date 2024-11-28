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

    # Grafana setup for Ubuntu/Debian
    log "Setting up Grafana repository (Ubuntu/Debian)..."
    sudo mkdir -p /etc/apt/keyrings
    sudo chmod 0755 /etc/apt/keyrings

    if [ ! -f "/etc/apt/keyrings/grafana.gpg" ]; then
        curl -fsSL https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
    fi

    if [ ! -f "/etc/apt/sources.list.d/grafana.list" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null
    fi

    log "Updating repositories..."
    sudo apt-get update -y

elif grep -Ei 'suse' /etc/os-release > /dev/null; then
    OS="suse"
    PKG_MANAGER="zypper"
    INSTALL_CMD="sudo zypper install -y"
    UPDATE_CMD="sudo zypper refresh"

    # Grafana setup for SUSE
    log "Setting up Grafana repository (SUSE)..."
    wget -q -O gpg.key https://rpm.grafana.com/gpg.key
    rpm --import gpg.key
    zypper addrepo https://rpm.grafana.com grafana

    log "Updating repositories..."
    sudo zypper update

elif grep -Ei 'fedora|red hat|centos|rhel' /etc/os-release > /dev/null; then
    OS="redhat"
    PKG_MANAGER="yum"
    INSTALL_CMD="sudo yum install -y || sudo dnf install -y"
    UPDATE_CMD="sudo yum update -y || sudo dnf update -y"

    # Grafana setup for RedHat/CentOS/Fedora
    log "Setting up Grafana repository (RedHat/CentOS/Fedora)..."
    wget -q -O gpg.key https://rpm.grafana.com/gpg.key
    rpm --import gpg.key
    echo -e '[grafana]\nname=grafana\nbaseurl=https://rpm.grafana.com\nrepo_gpgcheck=1\nenabled=1\ngpgcheck=1\ngpgkey=https://rpm.grafana.com/gpg.key\nsslverify=1\nsslcacert=/etc/pki/tls/certs/ca-bundle.crt' | sudo tee /etc/yum.repos.d/grafana.repo

    log "Updating repositories..."
    sudo yum update -y || sudo dnf update -y

else
    log "Unsupported operating system."
    exit 1
fi

log "Operating system detected: $OS"

# Variables
# GITHUB_REPO="https://api.github.com/repos/alloyproject/alloy/releases/latest"
# ALLOY_INSTALL_DIR="/usr/local/bin"
ALLOY_CONFIG_URL="http://10.0.34.144/config.alloy"
API_ENDPOINT="https://10.0.34.181:8000/api/v1/agents/"
HOST_IP=$(hostname -I | awk '{print $1}')
ALLOY_PORT=8080

# Update and install prerequisites
log "Updating repositories..."
$UPDATE_CMD

log "Installing required packages..."
install_packages() {
    case $OS in
        debian)
            $INSTALL_CMD curl tar acl gpg
            ;;
        suse)
            $INSTALL_CMD curl tar acl gpg2
            ;;
        redhat)
            $INSTALL_CMD curl tar acl gpg
            ;;
    esac
}
install_packages

# Download and install Alloy from GitHub
# log "Fetching the latest release information from GitHub..."
# response=$(curl -s "$GITHUB_REPO")

# if [ -z "$response" ]; then
#     log "Failed to fetch release information from GitHub."
#     exit 1
# fi

# # Extract the download URL for Linux
# log "Parsing release information..."
# download_url=$(echo "$response" | grep -oP '"browser_download_url":\s*"\K.*linux.*(?=")')

# if [ -z "$download_url" ]; then
#     log "Failed to find a suitable download URL for Linux in the latest release."
#     log "Available assets in the latest release:"
#     echo "$response" | grep -oP '"name":\s*"\K.*(?=")'
#     exit 1
# fi

# log "Download URL: $download_url"

# temp_dir=$(mktemp -d)
# log "Downloading Alloy from $download_url..."
# curl -L -o "$temp_dir/alloy.tar.gz" "$download_url"

# log "Extracting Alloy..."
# sudo tar -xzf "$temp_dir/alloy.tar.gz" -C "$ALLOY_INSTALL_DIR"

# log "Cleaning up temporary files..."
# rm -rf "$temp_dir"

# # Ensure Alloy binary is executable
# sudo chmod +x "$ALLOY_INSTALL_DIR/alloy"

# Setup Alloy
log "Installing Alloy..."
install_package alloy || { log "Alloy package not found. Please check the repository setup."; exit 1; }
sudo apt install alloy -y

log "Setting up Alloy..."
sudo mkdir -p /etc/alloy
sudo chmod 0755 /etc/alloy

# Make the config setup OS specific
case $OS in
    debian)
        [ -f "/etc/alloy/config.alloy" ] && sudo cp /etc/alloy/config.alloy /etc/alloy/config.alloy.backup
        sudo apt-get install -y acl
        log "Setting ACL for alloy user on /var/log..."
        sudo setfacl -dR -m u:alloy:r /var/log/
        sudo curl -fsSL -o /etc/alloy/config.alloy "$ALLOY_CONFIG_URL" || { log "Failed to download config file"; exit 1; }
        ;;
    suse)
        [ -f "/etc/alloy/config.alloy" ] && sudo cp /etc/alloy/config.alloy /etc/alloy/config.alloy.backup
        sudo zypper install -y acl
        log "Setting ACL for alloy user on /var/log..."
        sudo setfacl -dR -m u:alloy:r /var/log/
        sudo curl -fsSL -o /etc/alloy/config.alloy "$ALLOY_CONFIG_URL" || { log "Failed to download config file"; exit 1; }
        ;;
    redhat)
        [ -f "/etc/alloy/config.alloy" ] && sudo cp /etc/alloy/config.alloy /etc/alloy/config.alloy.backup
        sudo yum install -y acl || sudo dnf install -y acl
        log "Setting ACL for alloy user on /var/log..."
        sudo setfacl -dR -m u:alloy:r /var/log/
        sudo curl -fsSL -o /etc/alloy/config.alloy "$ALLOY_CONFIG_URL" || { log "Failed to download config file"; exit 1; }
        ;;
esac

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
