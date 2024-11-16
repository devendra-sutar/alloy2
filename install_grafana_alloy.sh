#!/bin/bash

# Function to install Grafana and related packages for Ubuntu
install_ubuntu() {
    echo "Ubuntu detected: Installing Grafana..."

    # Update package lists
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

    # Install Grafana, Alloy, and ACL
    echo "Installing Grafana, Alloy, and ACL..."
    sudo apt-get install -y grafana alloy acl

    # Create Alloy directory if not exists
    echo "Creating Alloy directory..."
    sudo mkdir -p /etc/alloy
    sudo chmod 0755 /etc/alloy

    # Backup the default Alloy config file (if exists)
    echo "Backing up default Alloy config file..."
    if [ -f "/etc/alloy/config.alloy" ]; then
        sudo cp /etc/alloy/config.alloy /etc/alloy/config.alloy.backup
    fi

    # Copy the custom Alloy config file (if exists)
    echo "Copying the Alloy config file..."
    if [ -f "/home/$USER/config.alloy" ]; then
        sudo cp /home/$USER/config.alloy /etc/alloy/config.alloy
    else
        echo "ERROR: config.alloy file not found at /home/$USER/config.alloy"
        exit 1
    fi

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
}

# Function to install Grafana and related packages for SUSE
install_suse() {
    echo "SUSE detected: Installing Grafana..."

    # Install GPG key for Grafana
    wget -q -O gpg.key https://rpm.grafana.com/gpg.key
    rpm --import gpg.key

    # Add Grafana repository
    sudo zypper addrepo https://rpm.grafana.com grafana

    # Install Grafana, Alloy, and ACL
    sudo zypper install -y grafana alloy acl

    # Create Alloy directory if not exists
    echo "Creating Alloy directory..."
    sudo mkdir -p /etc/alloy
    sudo chmod 0755 /etc/alloy

    # Backup the default Alloy config file (if exists)
    echo "Backing up default Alloy config file..."
    if [ -f "/etc/alloy/config.alloy" ]; then
        sudo cp /etc/alloy/config.alloy /etc/alloy/config.alloy.backup
    fi

    # Copy the custom Alloy config file (if exists)
    echo "Copying the Alloy config file..."
    if [ -f "/home/$USER/config.alloy" ]; then
        sudo cp /home/$USER/config.alloy /etc/alloy/config.alloy
    else
        echo "ERROR: config.alloy file not found at /home/$USER/config.alloy"
        exit 1
    fi

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
}

# Function to install Grafana and related packages for RedHat/CentOS/RHEL
install_redhat() {
    echo "RedHat/CentOS/RHEL detected: Installing Grafana..."

    # Update package lists
    sudo yum check-update

    # Install GPG if not present
    echo "Installing GPG..."
    sudo yum install -y gnupg

    # Add Grafana GPG key
    echo "Adding Grafana GPG key..."
    wget -q -O gpg.key https://rpm.grafana.com/gpg.key
    rpm --import gpg.key

    # Add Grafana repository
    echo "Adding Grafana repository..."
    if ! grep -q "grafana" /etc/yum.repos.d/grafana.repo; then
        echo -e "[grafana]\nname=grafana\nbaseurl=https://rpm.grafana.com\nrepo_gpgcheck=1\nenabled=1\ngpgcheck=1\ngpgkey=https://rpm.grafana.com/gpg.key\nsslverify=1\nsslcacert=/etc/pki/tls/certs/ca-bundle.crt" | sudo tee /etc/yum.repos.d/grafana.repo
    fi

    # Install Grafana, Alloy, and ACL
    sudo yum install -y grafana alloy acl

    # Create Alloy directory if not exists
    echo "Creating Alloy directory..."
    sudo mkdir -p /etc/alloy
    sudo chmod 0755 /etc/alloy

    # Backup the default Alloy config file (if exists)
    echo "Backing up default Alloy config file..."
    if [ -f "/etc/alloy/config.alloy" ]; then
        sudo cp /etc/alloy/config.alloy /etc/alloy/config.alloy.backup
    fi

    # Copy the custom Alloy config file (if exists)
    echo "Copying the Alloy config file..."
    if [ -f "/home/$USER/config.alloy" ]; then
        sudo cp /home/$USER/config.alloy /etc/alloy/config.alloy
    else
        echo "ERROR: config.alloy file not found at /home/$USER/config.alloy"
        exit 1
    fi

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
}

# Determine OS and call the appropriate function
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$NAME
    OS_ID=$ID
else
    echo "Could not determine OS."
    exit 1
fi

# Determine the OS and install accordingly
case "$OS_ID" in
    ubuntu)
        install_ubuntu
        ;;
    opensuse|sles)
        install_suse
        ;;
    rhel|centos|fedora)
        install_redhat
        ;;
    *)
        echo "Unsupported OS: $OS_NAME"
        exit 1
        ;;
esac

# Sending POST request to create agent (API call)
echo "Sending request to create agent..."

curl -X POST http://10.0.34.138:8000/api/v1/create-agent/ \
-H "Content-Type: application/json" \
-d '{
    "host_name": "AAdmin-new",
    "ip_port": "192.162.1.12:8080",
    "keycloak_id": "a00e1a35-1550-4215-930a-1468298be901",
    "agent_name": "Gitlab",
    "status": "Active"
}'

echo "Agent creation request sent successfully."
