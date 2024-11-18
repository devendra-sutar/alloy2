# Update package lists
    echo "Updating package lists..."
    sudo apt-get update -y
    # sudo apt-get install -y acl gnupg curl

    Install GPG if not present
    echo "Installing gnupg..."
    sudo apt-get install -y gnupg

    # Create the directory for APT keyrings
    echo "Creating APT keyring directory..."
    sudo mkdir -p /etc/apt/keyrings
    sudo chmod 0755 /etc/apt/keyrings

    # Add Grafana GPG key if it doesn't exist
    echo "Adding Grafana GPG key..."
    if [ ! -f "/etc/apt/keyrings/grafana.gpg" ]; then
       sudo curl -fsSL  https://apt.grafana.com/gpg.key -o /etc/apt/keyrings/grafana.gpg
    fi

    # Add Grafana repository if not already added
    echo "Adding Grafana repository..."
    if [ ! -f "/etc/apt/sources.list.d/grafana.list" ]; then
        echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
    fi

    # Install Alloy if not already installed
    echo "Installing Alloy..."
    if ! dpkg -l | grep -q alloy; then
        sudo apt-get install  alloy -y
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
    sudo usermod  -d -m alloy
    sudo setfacl -m u:alloy:r /var/log
    sudo setfacl -d -m  u:alloy:r /var/log

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
