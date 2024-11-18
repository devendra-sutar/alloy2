#!/bin/bash

# This script automates the installation and configuration of Alloy with Grafana integration.

# Exit on any error
set -e

# Step 1: Install GPG
echo "Installing GPG..."
sudo apt update && sudo apt install -y gpg

# Step 2: Import the GPG key and add the Grafana package repository
echo "Importing GPG key and adding Grafana repository..."
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# Step 3: Update repositories
echo "Updating repositories..."
sudo apt-get update

# Step 4: Install Alloy
echo "Installing Alloy..."
sudo apt-get install -y alloy

# Step 5: Start and enable the Alloy service
echo "Starting and enabling Alloy service..."
sudo systemctl start alloy.service
sudo systemctl enable alloy.service

# Step 6: Verify the Alloy service status
echo "Verifying the Alloy service status..."
sudo systemctl status alloy.service

# Alloy Configuration
echo "Configuring Alloy..."

# Step 7: Set ACL to allow Alloy user access to /var/log
echo "Setting ACL for Alloy user on /var/log..."
sudo setfacl -dR -m u:alloy:r /var/log/

# Step 8: Backup the default configuration file
echo "Backing up the default configuration file..."
sudo mv /etc/alloy/config.alloy /etc/alloy/config.alloy.backup

# Step 9: Create a new configuration file and add content
echo "Creating and editing the new Alloy configuration file..."
cat <<EOF | sudo tee /etc/alloy/config.alloy > /dev/null
# Grafana Alloy Configuration

# Prometheus Unix Exporter
exporters:
  - name: prometheus_unix_exporter
    enabled: true

# Log files to monitor
log_files:
  - /var/log/syslog
  - /var/log/auth.log
  - /var/log/kern.log

# Prometheus and Loki endpoints
prometheus_endpoint: "http://localhost:9090"
loki_endpoint: "http://localhost:3100"
EOF

# Step 10: Restart Alloy service and verify status
echo "Restarting Alloy service..."
sudo systemctl restart alloy.service
echo "Verifying Alloy service status..."
sudo systemctl status alloy.service

echo "Script completed successfully."
