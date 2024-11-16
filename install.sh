#!/bin/bash

# Update package lists
echo "Updating package lists..."
sudo apt-get update -y

# Install GPG if not present
echo "Installing gnupg..."
sudo apt-get install -y gnupg

# Create directory for APT keyrings
echo "Creating APT keyring directory..."
sudo mkdir -p /etc/apt/keyrings
sudo chmod 0755 /etc/apt/keyrings

# Add Grafana GPG key
echo "Adding Grafana GPG key..."
if [ ! -f "/etc/apt/keyrings/grafana.gpg" ]; then
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
fi

# Add Grafana repository
echo "Adding Grafana repository..."
if [ ! -f "/etc/apt/sources.list.d/grafana.list" ]; then
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
fi

# Update package lists again
echo "Updating package lists after adding Grafana repository..."
sudo apt-get update -y

# Install Alloy if not already installed
echo "Installing Alloy..."
if ! dpkg -l | grep -q alloy; then
    sudo apt-get install -y alloy
fi

# Create Alloy directory if not exists
echo "Creating Alloy directory..."
sudo mkdir -p /etc/alloy
sudo chmod 0755 /etc/alloy

# Install acl if not installed
echo "Installing acl..."
sudo apt-get install -y acl

# Set ACL for alloy user on /var/log
echo "Setting ACL for alloy user on /var/log..."
sudo setfacl -m u:alloy:r /var/log
sudo setfacl -d -m u:alloy:r /var/log

# Enable and restart Alloy service
echo "Enabling and restarting Alloy service..."
sudo systemctl enable alloy
sudo systemctl restart alloy

# Check Alloy service status
echo "Checking Alloy service status..."
sudo systemctl status alloy

echo "Installation completed successfully!"
