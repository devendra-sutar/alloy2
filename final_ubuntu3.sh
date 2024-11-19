#!/bin/bash

# Function to check if the ip_port is already used
check_ip_port_used() {
    local ip_port=$1
    # Send a GET request to check if the IP and port already exist (replace with actual API endpoint)
    response=$(curl -s -w "%{http_code}" -o /dev/null "http://10.0.34.138:8000/api/v1/agents/?ip_port=$ip_port")
    
    if [[ "$response" == "200" ]]; then
        echo "Port $ip_port is already in use."
        return 1
    else
        return 0
    fi
}

# Function to generate a new unique ip_port by incrementing the port number
generate_new_ip_port() {
    local base_ip="199.162.1.777"
    local port=8080
    local new_ip_port=""
    
    # Check if the port is already in use
    while true; do
        new_ip_port="${base_ip}:${port}"
        if check_ip_port_used "$new_ip_port"; then
            echo "Using new ip_port: $new_ip_port"
            break
        fi
        ((port++))  # Increment the port number if the current one is in use
    done
    
    echo "$new_ip_port"
}

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

# Generate a new unique ip_port
echo "Generating unique ip_port..."
new_ip_port=$(generate_new_ip_port)

# Send POST request to the provided URL with JSON data
echo "Sending POST request to create new agent..."

# Capture the full response body and status code
response=$(curl -s -w "%{http_code}" -o /dev/null -X POST http://10.0.34.138:8000/api/v1/create-agent/ \
    -H "Content-Type: application/json" \
    -d '{
        "host_name": "AAdmin-new1",
        "ip_port": "'$new_ip_port'",
        "keycloak_id": "a00e1a35-1550-4215-930a-1468298be901",
        "agent_name": "Linux123",
        "status": "Active"
    }')

# Capture the full response body (for debugging)
full_response=$(curl -s -X POST http://10.0.34.138:8000/api/v1/create-agent/ \
    -H "Content-Type: application/json" \
    -d '{
        "host_name": "AAdmin-new1",
        "ip_port": "'$new_ip_port'",
        "keycloak_id": "a00e1a35-1550-4215-930a-1468298be901",
        "agent_name": "Linux123",
        "status": "Active"
    }')

# Log the response code and full response body for debugging
echo "Response Code: $response"
echo "Full Response Body: $full_response"

# Check if the response is 201 (success, resource created)
if [[ "$response" == "201" ]]; then
    echo "Agent created successfully."
else
    # Handle the error response (for example, unique constraint failure)
    if [[ "$full_response" == *"UNIQUE constraint failed"* ]]; then
        echo "Agent creation failed due to unique constraint violation: $full_response"
    else
        echo "Agent creation failed. Response code: $response"
        echo "Full response body: $full_response"
    fi
fi
