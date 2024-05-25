#!/bin/bash

LOG_FILE="/var/log/script.log"

log() {
    echo "$(date +"%Y-%m-%d %T") : $1" | tee -a $LOG_FILE
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "This script must be run as root. Please run with sudo or as root user."
        exit 1
    fi
}

return_to_main_menu() {
    echo -e "\nReturning to main menu..."
    main_menu
}

return_to_docker_menu() {
    echo -e "\nReturning to Docker menu..."
    docker_menu
}

# Function to perform initial setup
initial_setup() {
    log "Initial Setup"
    
    read -p "Do you want to update the system? (y/n): " update_confirm
    if [[ "${update_confirm:0:1}" =~ ^[Yy]$ ]]; then
        log "Updating the system..."
        apt update && apt upgrade -y || { log "System update failed."; return_to_main_menu; return; }
        log "System updated."
    fi

    read -p "Do you want to create a new user and add it to the sudo group? (y/n): " create_user_confirm
    if [[ "${create_user_confirm:0:1}" =~ ^[Yy]$ ]]; then
        read -p "Enter the new username: " username
        if id -u "$username" >/dev/null 2>&1; then
            log "User $username already exists."
        else
            read -s -p "Enter the password for $username: " password
            echo
            useradd -m -s /bin/bash -G sudo $username || { log "Failed to create user $username."; return_to_main_menu; return; }
            echo "$username:$password" | chpasswd || { log "Failed to set password for $username."; return_to_main_menu; return; }
            log "User $username created and added to sudo group."
        fi

        read -p "Do you want to add a public key for $username? (y/n): " add_key_confirm
        if [[ "${add_key_confirm:0:1}" =~ ^[Yy]$ ]]; then
            read -p "Enter the public key for $username: " public_key
            mkdir -p /home/$username/.ssh || { log "Failed to create .ssh directory for $username."; return_to_main_menu; return; }
            echo "$public_key" > /home/$username/.ssh/authorized_keys || { log "Failed to add public key for $username."; return_to_main_menu; return; }
            chown -R $username:$username /home/$username/.ssh || { log "Failed to set ownership for .ssh directory of $username."; return_to_main_menu; return; }
            chmod 700 /home/$username/.ssh || { log "Failed to set permissions for .ssh directory of $username."; return_to_main_menu; return; }
            chmod 600 /home/$username/.ssh/authorized_keys || { log "Failed to set permissions for authorized_keys of $username."; return_to_main_menu; return; }
            log "Public key added for $username."
        fi
    fi

    read -p "Do you want to change the SSH port? (y/n): " change_port_confirm
    if [[ "${change_port_confirm:0:1}" =~ ^[Yy]$ ]]; then
        read -p "Enter the new SSH port: " ssh_port
        echo "Port $ssh_port" >> /etc/ssh/sshd_config.d/00-userconfig.conf || { log "Failed to set SSH port to $ssh_port."; return_to_main_menu; return; }
        log "SSH port set to $ssh_port."
    fi

    read -p "Do you want to disable PermitRootLogin? (y/n): " disable_root_confirm
    if [[ "${disable_root_confirm:0:1}" =~ ^[Yy]$ ]]; then
        echo "PermitRootLogin no" >> /etc/ssh/sshd_config.d/00-userconfig.conf || { log "Failed to disable PermitRootLogin."; return_to_main_menu; return; }
        log "PermitRootLogin disabled."
    fi

    echo "Protocol 2" >> /etc/ssh/sshd_config.d/00-userconfig.conf || { log "Failed to set SSH protocol to 2."; return_to_main_menu; return; }
    log "SSH protocol set to 2."

    if [[ "${add_key_confirm:0:1}" =~ ^[Yy]$ ]]; then
        read -p "Do you want to disable password authentication? (y/n): " disable_pass_auth_confirm
        if [[ "${disable_pass_auth_confirm:0:1}" =~ ^[Yy]$ ]]; then
            echo "PasswordAuthentication no" >> /etc/ssh/sshd_config.d/00-userconfig.conf || { log "Failed to disable password authentication."; return_to_main_menu; return; }
            echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config.d/00-userconfig.conf || { log "Failed to enable public key authentication."; return_to_main_menu; return; }
            log "Password authentication disabled."
        fi
    fi

    log "Generating new SSH host keys..."
    ssh-keygen -A || { log "Failed to generate new SSH host keys."; return_to_main_menu; return; }
    log "New SSH host keys generated."

    systemctl restart sshd || { log "Failed to restart SSH service."; return_to_main_menu; return; }
    log "SSH service restarted with new configuration."

    return_to_main_menu
}

# Function to install Docker
install_docker() {
    log "Installing Docker..."
    apt-get update || { log "Failed to update package list."; return_to_docker_menu; return; }
    apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release || { log "Failed to install Docker dependencies."; return_to_docker_menu; return; }

    install -m 0755 -d /etc/apt/keyrings || { log "Failed to create keyrings directory."; return_to_docker_menu; return; }

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || { log "Failed to download Docker GPG key."; return_to_docker_menu; return; }

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null || { log "Failed to add Docker repository."; return_to_docker_menu; return; }

    apt-get update || { log "Failed to update package list after adding Docker repository."; return_to_docker_menu; return; }
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { log "Failed to install Docker."; return_to_docker_menu; return; }

    log "Docker installed."
    log "Verifying Docker installation..."
    docker run hello-world

    if [[ $? -eq 0 ]]; then
        log "Docker was installed and verified successfully."
    else
        log "Docker installation verification failed."
    fi

    return_to_docker_menu
}

# Function to remove Docker
remove_docker() {
    log "Removing Docker..."
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { log "Failed to remove Docker."; return_to_docker_menu; return; }
    apt-get autoremove -y || { log "Failed to autoremove packages."; return_to_docker_menu; return; }
    rm -rf /var/lib/docker || { log "Failed to remove Docker data."; return_to_docker_menu; return; }
    rm -rf /etc/docker || { log "Failed to remove Docker configuration."; return_to_docker_menu; return; }
    rm /etc/apt/sources.list.d/docker.list || { log "Failed to remove Docker repository."; return_to_docker_menu; return; }
    rm /usr/share/keyrings/docker-archive-keyring.gpg || { log "Failed to remove Docker GPG key."; return_to_docker_menu; return; }
    log "Docker removed."

    return_to_docker_menu
}

# Function to add a user to the docker group
add_user_to_docker_group() {
    read -p "Enter the username to add to the docker group: " docker_user
    usermod -aG docker $docker_user || { log "Failed to add $docker_user to the docker group."; return_to_docker_menu; return; }
    log "User $docker_user added to the docker group."

    return_to_docker_menu
}

# Function to remove a user from the docker group
remove_user_from_docker_group() {
    read -p "Enter the username to remove from the docker group: " docker_user
    gpasswd -d $docker_user docker || { log "Failed to remove $docker_user from the docker group."; return_to_docker_menu; return; }
    log "User $docker_user removed from the docker group."

    return_to_docker_menu
}

# Function to install Dockge
install_dockge() {
    if ! command -v docker &> /dev/null || ! systemctl is-active --quiet docker; then
        log "Docker is not installed or not running. Please install and start Docker first."
        return_to_docker_menu
        return
    fi

    read -p "Where should Dockge be installed? (default /opt/dockge): " dockge_dir
    dockge_dir=${dockge_dir:-/opt/dockge}
    read -p "Where should stacks be stored? (default /opt/stacks): " stacks_dir
    stacks_dir=${stacks_dir:-/opt/stacks}
    read -p "Which port should Dockge use?: " dockge_port

    log "Installing Dockge..."
    mkdir -p "$dockge_dir" && cd "$dockge_dir" || { log "Failed to create and navigate to $dockge_dir."; return_to_docker_menu; return; }
    curl "https://dockge.kuma.pet/compose.yaml?port=$dockge_port&stacksPath=$stacks_dir" --output compose.yaml || { log "Failed to download Dockge compose file."; return_to_docker_menu; return; }
    docker compose up -d || { log "Failed to start Dockge with Docker Compose."; return_to_docker_menu; return; }

    log "Dockge is running on http://$(hostname -I | awk '{print $1}'):$dockge_port"

    return_to_docker_menu
}

# Function to remove Dockge
remove_dockge() {
    read -p "Where is Dockge installed? (default /opt/dockge): " dockge_dir
    dockge_dir=${dockge_dir:-/opt/dockge}

    log "Removing Dockge..."
    cd "$dockge_dir" || { log "Failed to navigate to $dockge_dir."; return_to_docker_menu; return; }
    docker compose down || { log "Failed to stop Dockge with Docker Compose."; return_to_docker_menu; return; }
    rm -rf "$dockge_dir" || { log "Failed to remove Dockge directory."; return_to_docker_menu; return; }

    log "Dockge removed."

    return_to_docker_menu
}

# Function to check Docker status and users in docker group
check_docker_status() {
    if command -v docker &> /dev/null && systemctl is-active --quiet docker; then
        log "Docker is installed and running."
    else
        log "Docker is not installed or not running."
    fi

    log "Users in the docker group:"
    getent group docker | awk -F: '{print $4}'

    return_to_docker_menu
}

docker_menu() {
    echo "Select a Docker option:"
    echo "1) Check Docker status"
    echo "2) Install Docker"
    echo "3) Remove Docker"
    echo "4) Add user to Docker group"
    echo "5) Remove user from Docker group"
    echo "6) Install Dockge"
    echo "7) Remove Dockge"
    echo "x) Back to main menu"
    read -p "Enter your choice: " docker_choice

    case $docker_choice in
        1)
            check_docker_status
        ;;
        2)
            install_docker
        ;;
        3)
            remove_docker
        ;;
        4)
            add_user_to_docker_group
        ;;
        5)
            remove_user_from_docker_group
        ;;
        6)
            install_dockge
        ;;
        7)
            remove_dockge
        ;;
        x)
            return_to_main_menu
        ;;
        *)
            log "Invalid choice."
            docker_menu
        ;;
    esac
}

main_menu() {
    echo "Select an option:"
    echo "1) Initial setup"
    echo "2) Docker"
    echo "3) Cleanup to prepare for turning into a template"
    echo "x) Exit"
    read -p "Enter your choice: " choice

    check_root

    case $choice in
        1)
            initial_setup
        ;;
        2)
            docker_menu
        ;;
        3)
            cleanup
        ;;
        x)
            log "Exiting script."
            exit 0
        ;;
        *)
            log "Invalid choice."
            main_menu
        ;;
    esac
}

main_menu
