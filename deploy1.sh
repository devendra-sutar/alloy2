#!/bin/bash

# Prompt for input if variables are not passed as arguments
if [ -z "$1" ]; then
    read -p "Enter the remote server username: " linux_user
else
    linux_user=$1
fi

if [ -z "$2" ]; then
    read -p "Enter the remote server IP/hostname: " linux_host
else
    linux_host=$2
fi

if [ -z "$3" ]; then
    read -s -p "Enter the remote server password: " linux_password
    echo
else
    linux_password=$3
fi

# Ensure the arguments are provided
if [[ -z "$linux_user" || -z "$linux_host" || -z "$linux_password" ]]; then
    echo "Usage: $0 <user> <host> <password>"
    exit 1
fi

# Use these variables for deployment actions
echo "Connecting to $linux_user@$linux_host with password $linux_password"

# SSH into the remote server using sshpass (non-interactive password login)
sshpass -p "$linux_password" ssh -t -o StrictHostKeyChecking=no "$linux_user@$linux_host" << EOF
    # Update package lists
    echo "Updating package lists..."
    sudo apt-get update -y

    # Install GPG if not present
    echo "Installing gnupg..."
    sudo apt-get install -y gnupg

    # Create the directory for APT keyrings
    echo "Creating APT keyring directory..."
    sudo mkdir -p /etc/apt/keyrings
    sudo chmod 0755 /etc/apt/keyrings

    # Add Grafana GPG key if it doesn't exist
    echo "Adding Grafana GPG key..."
    if [ ! -f "/etc/apt/keyrings/grafana.gpg" ]; then
        wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
    fi

    # Add Grafana repository if not already added
    echo "Adding Grafana repository..."
    if [ ! -f "/etc/apt/sources.list.d/grafana.list" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
    fi

    # Install Alloy if not already installed
    echo "Installing Alloy..."
    if ! dpkg -l | grep -q alloy; then
        sudo apt-get install -y alloy
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
    sudo setfacl -m u:alloy:r /var/log
    sudo setfacl -d -m u:alloy:r /var/log

    # Copy the Alloy config file
    echo "Copying the Alloy config file..."
    sudo cp /home/ubuntu/config.alloy /etc/alloy/config.alloy

    # Enable and restart Alloy service
    echo "Enabling and restarting Alloy service..."
    sudo systemctl enable alloy
    sudo systemctl restart alloy

    # Check Alloy service status
    echo "Checking Alloy service status..."
    sudo systemctl status alloy
EOF

echo "Deployment completed on $linux_host."
