#!/bin/bash

# Update package lists
echo "Updating package lists..."
sudo apt-get update -y

# Install GPG if not present
echo "Installing gnupg..."
#sudo apt-get install -y gnupg
sudo apt install -y gpg 

# Create the directory for APT keyrings
echo "Creating APT keyring directory..."
sudo mkdir -p /etc/apt/keyrings
sudo chmod 0755 /etc/apt/keyrings

# Add Grafana GPG key if it doesn't exist
echo "Adding Grafana GPG key..."
if [ ! -f "/etc/apt/keyrings/grafana.gpg" ]; then
    curl -fsSL https://apt.grafana.com/gpg.key | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
fi

# Add Grafana repository if not already added
echo "Adding Grafana repository..."
if [ ! -f "/etc/apt/sources.list.d/grafana.list" ]; then
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null
fi

# Install Alloy (skip if not available in repos)
echo "Installing Alloy..."
if ! dpkg -l | grep -q alloy; then
    echo "Alloy package not found in repositories. Please install it manually or provide a .deb file."
    exit 1
fi

# Create /etc/alloy directory if not exists
echo "Creating Alloy directory..."
sudo mkdir -p /etc/alloy
sudo chmod 0755 /etc/alloy

# Backup config.alloy if it exists
echo "Backing up config.alloy..."
if [ -f "/etc/alloy/config.alloy" ]; then
    sudo cp /etc/alloy/config.alloy /etc/alloy/config.alloy.backup
fi

# Install acl if not installed
echo "Installing acl..."
sudo apt-get install -y acl

# Set ACL for alloy user on /var/log
echo "Setting ACL for alloy user on /var/log..."
#sudo usermod -d /home/alloy -m alloy
#sudo setfacl -m u:alloy:r /var/log
#sudo setfacl -d -m u:alloy:r /var/log
sudo  setfacl -dR -m u:alloy:r /var/log/

# Copy the Alloy config file
echo "Copying the Alloy config file..."
sudo cp /home/ubuntu/config.alloy /etc/alloy/config.alloy

# Create a basic systemd service file for Alloy (if necessary)
echo "Creating Alloy service..."
sudo tee /etc/systemd/system/alloy.service > /dev/null <<EOF
[Unit]
Description=Alloy Service
After=network.target

[Service]
ExecStart=/usr/bin/alloy
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and restart Alloy service
echo "Enabling and restarting Alloy service..."
sudo systemctl daemon-reload
sudo systemctl enable alloy
sudo systemctl start alloy

# Check Alloy service status
echo "Checking Alloy service status..."
sudo systemctl status alloy

# Send POST request to the provided URL with JSON data
echo "Sending POST request to create new agent..."

# Capture the full response body and status code
response=$(curl -s -w "%{http_code}" -o /dev/null -X POST http://10.0.34.138:8000/api/v1/create-agent/ \
    -H "Content-Type: application/json" \
    -d '{
        "host_name": "AAdmin-new1",
        "ip_port": "199.162.1.777:8080",
        "keycloak_id": "a00e1a35-1550-4215-930a-1468298be901",
        "agent_name": "Linux123",
        "status": "Active"
    }')

# Capture the full response body (for debugging)
full_response=$(curl -s -X POST http://10.0.34.138:8000/api/v1/create-agent/ \
    -H "Content-Type: application/json" \
    -d '{
        "host_name": "AAdmin-new1",
        "ip_port": "199.162.1.777:8080",
        "keycloak_id": "a00e1a35-1550-4215-930a-1468298be901",
        "agent_name": "Linux123",
        "status": "Active"
    }')

# Log the response code and full response body for debugging
echo "Response Code: $response"
echo "Full Response Body: $full_response"

# Check if the response is 200 (success)
if [[ "$response" == "200" ]]; then
    echo "Agent created successfully."
else
    echo "Agent creation failed. Response code: $response"
    echo "Full response body: $full_response"
fi
