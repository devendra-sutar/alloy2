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

    # Step 1: Enable Remote Write Receiver in Prometheus
    echo "Enabling remote write receiver in Prometheus..."
    
    # Modify the Prometheus service file to include remote-write-receiver feature
    PROMETHEUS_SERVICE_FILE="/etc/systemd/system/prometheus.service"
    
    if ! grep -q -- "--enable-feature=remote-write-receiver" "$PROMETHEUS_SERVICE_FILE"; then
        echo "Adding --enable-feature=remote-write-receiver to Prometheus service..."
        sudo sed -i '/ExecStart=\/usr\/bin\/prometheus/s/$/ --enable-feature=remote-write-receiver/' "$PROMETHEUS_SERVICE_FILE"
    else
        echo "Remote write receiver feature already enabled in Prometheus service."
    fi

    # Reload systemd to apply the changes to the service file
    echo "Reloading systemd daemon..."
    sudo systemctl daemon-reload

    # Restart Prometheus service
    echo "Restarting Prometheus service..."
    sudo systemctl restart prometheus.service

    # Check Prometheus service status
    echo "Checking Prometheus service status..."
    sudo systemctl status prometheus.service --no-pager

    # Step 2: Grafana Alloy Installation and Configuration

    echo "Starting Grafana Alloy Installation..."

    # Install necessary tools and import GPG key
    echo "Installing GPG and adding Grafana package repository..."
    sudo apt-get update -y
    sudo apt-get install -y gpg wget

    # Step 3: Add Grafana GPG key and repository
    echo "Adding Grafana GPG key..."
    sudo mkdir -p /etc/apt/keyrings/
    sudo wget -q -O - https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

    # Step 4: Update apt repositories
    echo "Updating repositories..."
    sudo apt-get update -y

    # Step 5: Install Alloy
    echo "Installing Alloy..."
    if ! dpkg -l | grep -q alloy; then
        sudo apt-get install -y alloy
    fi

    # Step 6: Create Alloy directory if it doesn't exist
    echo "Creating Alloy directory..."
    sudo mkdir -p /etc/alloy
    sudo chmod 0755 /etc/alloy

    # Step 7: Backup the default Alloy configuration file
    echo "Backing up default Alloy config file..."
    if [ -f "/etc/alloy/config.alloy" ]; then
        sudo cp /etc/alloy/config.alloy /etc/alloy/config.alloy.backup
    fi

    # Step 8: Install ACL package
    echo "Installing acl..."
    sudo apt-get install -y acl

    # Step 9: Set ACL permissions for the Alloy user on /var/log
    echo "Setting ACL permissions for Alloy user on /var/log..."
    sudo setfacl -m u:alloy:r /var/log
    sudo setfacl -d -m u:alloy:r /var/log

    # Step 10: Copy the Alloy config file from local path
    echo "Copying the Alloy config file..."
    if [ -f "/home/$linux_user/config.alloy" ]; then
        sudo cp /home/$linux_user/config.alloy /etc/alloy/config.alloy
    else
        echo "ERROR: config.alloy file not found at /home/$linux_user/config.alloy"
        exit 1
    fi

    # Step 11: Enable and restart Alloy service
    echo "Enabling and restarting Alloy service..."
    sudo systemctl enable alloy
    sudo systemctl restart alloy

    # Step 12: Check Alloy service status
    echo "Checking Alloy service status..."
    sudo systemctl status alloy --no-pager

EOF

echo "Deployment completed on $linux_host."
