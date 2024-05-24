#!/bin/bash

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root. Please run with sudo or as root user."
        exit 1
    fi
}

# Function to perform initial setup
initial_setup() {
    echo "Initial Setup"
    
    read -p "Do you want to update the system? (y/n): " update_confirm
    if [[ "${update_confirm:0:1}" =~ ^[Yy]$ ]]; then
        echo "Updating the system..."
        apt update && apt upgrade -y
        echo "System updated."
    fi

    read -p "Do you want to create a new user and add it to the sudo group? (y/n): " create_user_confirm
    if [[ "${create_user_confirm:0:1}" =~ ^[Yy]$ ]]; then
        read -p "Enter the new username: " username
        read -s -p "Enter the password for $username: " password
        echo
        useradd -m -s /bin/bash -G sudo $username
        echo "$username:$password" | chpasswd
        echo "User $username created and added to sudo group."

        read -p "Do you want to add a public key for $username? (y/n): " add_key_confirm
        if [[ "${add_key_confirm:0:1}" =~ ^[Yy]$ ]]; then
            read -p "Enter the public key for $username: " public_key
            mkdir -p /home/$username/.ssh
            echo "$public_key" > /home/$username/.ssh/authorized_keys
            chown -R $username:$username /home/$username/.ssh
            chmod 700 /home/$username/.ssh
            chmod 600 /home/$username/.ssh/authorized_keys
            echo "Public key added for $username."
        fi
    fi

    read -p "Do you want to change the SSH port? (y/n): " change_port_confirm
    if [[ "${change_port_confirm:0:1}" =~ ^[Yy]$ ]]; then
        read -p "Enter the new SSH port: " ssh_port
        echo "Port $ssh_port" >> /etc/ssh/sshd_config.d/00-userconfig.conf
        echo "SSH port set to $ssh_port."
    fi

    read -p "Do you want to disable PermitRootLogin? (y/n): " disable_root_confirm
    if [[ "${disable_root_confirm:0:1}" =~ ^[Yy]$ ]]; then
        echo "PermitRootLogin no" >> /etc/ssh/sshd_config.d/00-userconfig.conf
        echo "PermitRootLogin disabled."
    fi

    echo "Protocol 2" >> /etc/ssh/sshd_config.d/00-userconfig.conf
    echo "SSH protocol set to 2."

    if [[ "${add_key_confirm:0:1}" =~ ^[Yy]$ ]]; then
        read -p "Do you want to disable password authentication? (y/n): " disable_pass_auth_confirm
        if [[ "${disable_pass_auth_confirm:0:1}" =~ ^[Yy]$ ]]; then
            echo "PasswordAuthentication no" >> /etc/ssh/sshd_config.d/00-userconfig.conf
            echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config.d/00-userconfig.conf
            echo "Password authentication disabled."
        fi
    fi

    systemctl restart sshd
    echo "SSH service restarted with new configuration."
}

# Function to install Docker
install_docker() {
    echo "Installing Docker..."
    apt-get update
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "Docker installed."
    echo "Verifying Docker installation..."
    docker run hello-world

    if [[ $? -eq 0 ]]; then
        echo "Docker was installed and verified successfully."

        # Prompt to add a user to the docker group
        read -p "Do you want to add a user to the docker group? (y/n): " add_docker_group_confirm
        if [[ "${add_docker_group_confirm:0:1}" =~ ^[Yy]$ ]]; then
            echo "Users with UID >= 1000:"
            awk -F: '$3 >= 1000 {print $1}' /etc/passwd
            read -p "Enter the username to add to the docker group: " docker_user
            usermod -aG docker $docker_user
            echo "User $docker_user added to the docker group."
        fi
    else
        echo "Docker installation verification failed."
    fi
}

# Function to perform cleanup
cleanup() {
    echo "Performing cleanup..."

    echo "Clearing bash history..."
    cat /dev/null > ~/.bash_history && history -c
    for user in $(ls /home); do
        cat /dev/null > /home/$user/.bash_history && history -c
    done
    echo "Bash history cleared."

    echo "Clearing logs..."
    find /var/log -type f -exec truncate -s 0 {} \;
    find /var/log -type f -name '*.gz' -delete
    find /var/log -type f -name '*.old' -delete
    echo "Logs cleared."

    echo "Clearing temporary files..."
    rm -rf /tmp/*
    rm -rf /var/tmp/*
    echo "Temporary files cleared."

    echo "Clearing package cache..."
    apt clean
    echo "Package cache cleared."

    echo "Removing SSH host keys..."
    rm -f /etc/ssh/ssh_host_*
    echo "SSH host keys removed."

    echo "Removing user-specific data..."
    for user in $(ls /home); do
        rm -rf /home/$user/.cache/*
        rm -rf /home/$user/.config/*
        rm -rf /home/$user/.local/*
    done
    echo "User-specific data removed."

    echo "Removing persistent network interface names..."
    rm -f /etc/udev/rules.d/70-persistent-net.rules
    echo "Persistent network interface names removed."

    echo "Cleaning machine ID..."
    truncate -s 0 /etc/machine-id
    rm /var/lib/dbus/machine-id
    ln -s /etc/machine-id /var/lib/dbus/machine-id
    echo "Machine ID cleaned."

    echo "Resetting hostname configuration..."
    echo "" > /etc/hostname
    sed -i '/127.0.1.1/d' /etc/hosts
    echo "Hostname configuration reset."

    echo "Clearing SSH known hosts..."
    for user in $(ls /home); do
        rm -f /home/$user/.ssh/known_hosts
    done
    echo "SSH known hosts cleared."

    echo "Generating new SSH host keys..."
    ssh-keygen -A
    echo "New SSH host keys generated."

    echo "Resetting network configuration..."
    rm /etc/netplan/*.yaml
    echo "Network configuration reset."

    echo "Removing unneeded packages..."
    apt autoremove -y
    echo "Unneeded packages removed."

    echo "Cleanup complete. Ready to turn the container into a template."

    read -p "Do you want to shut down the container now? (y/n): " shutdown_confirm
    case ${shutdown_confirm:0:1} in
        y|Y )
            echo "Shutting down the container..."
            shutdown now
        ;;
        * )
            echo "Container not shut down. You can now convert it to a template."
        ;;
    esac
}

# Main menu
echo "Select an option:"
echo "1) Initial setup"
echo "2) Install Docker"
echo "3) Cleanup to prepare for turning into a template"
echo "x) Exit"
read -p "Enter your choice: " choice

check_root

case $choice in
    1)
        initial_setup
    ;;
    2)
        install_docker
    ;;
    3)
        cleanup
    ;;
    x)
        echo "Exiting script."
        exit 0
    ;;
    *)
        echo "Invalid choice."
        exit 1
    ;;
esac
