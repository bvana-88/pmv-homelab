#!/bin/bash

LOG_FILE="/var/log/setup-script.log"

# Function to check if the script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root. Please run with sudo or as root user."
        exit 1
    fi
}

# Function to log messages
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Function to return to the main menu
return_to_main_menu() {
    echo
    echo "Press Enter to return to the main menu..."
    read
    main_menu
}

# Function to return to the Docker menu
return_to_docker_menu() {
    echo
    echo "Press Enter to return to the Docker menu..."
    read
    docker_menu
}

# Function to perform SSH & User setup
ssh_user_setup() {
    log "SSH & User Setup"
    echo "SSH & User Setup"

    read -p "Do you want to update the system? (y/n): " update_confirm
    if [[ "${update_confirm:0:1}" =~ ^[Yy]$ ]]; then
        log "Updating the system..."
        apt update && apt upgrade -y
        log "System updated."
    fi

    read -p "Do you want to create a new user and add it to the sudo group? (y/n): " create_user_confirm
    if [[ "${create_user_confirm:0:1}" =~ ^[Yy]$ ]]; then
        read -p "Enter the new username: " username
        read -s -p "Enter the password for $username: " password
        echo
        useradd -m -s /bin/bash -G sudo $username
        echo "$username:$password" | chpasswd
        log "User $username created and added to sudo group."

        read -p "Do you want to add a public key for $username? (y/n): " add_key_confirm
        if [[ "${add_key_confirm:0:1}" =~ ^[Yy]$ ]]; then
            read -p "Enter the public key for $username: " public_key
            mkdir -p /home/$username/.ssh
            echo "$public_key" > /home/$username/.ssh/authorized_keys
            chown -R $username:$username /home/$username/.ssh
            chmod 700 /home/$username/.ssh
            chmod 600 /home/$username/.ssh/authorized_keys
            log "Public key added for $username."
        fi
    fi

    read -p "Do you want to change the SSH port? (y/n): " change_port_confirm
    if [[ "${change_port_confirm:0:1}" =~ ^[Yy]$ ]]; then
        read -p "Enter the new SSH port: " ssh_port
        echo "Port $ssh_port" >> /etc/ssh/sshd_config.d/00-userconfig.conf
        log "SSH port set to $ssh_port."
    fi

    read -p "Do you want to disable PermitRootLogin? (y/n): " disable_root_confirm
    if [[ "${disable_root_confirm:0:1}" =~ ^[Yy]$ ]]; then
        echo "PermitRootLogin no" >> /etc/ssh/sshd_config.d/00-userconfig.conf
        log "PermitRootLogin disabled."
    fi

    echo "Protocol 2" >> /etc/ssh/sshd_config.d/00-userconfig.conf
    log "SSH protocol set to 2."

    if [[ "${add_key_confirm:0:1}" =~ ^[Yy]$ ]]; then
        read -p "Do you want to disable password authentication? (y/n): " disable_pass_auth_confirm
        if [[ "${disable_pass_auth_confirm:0:1}" =~ ^[Yy]$ ]]; then
            echo "PasswordAuthentication no" >> /etc/ssh/sshd_config.d/00-userconfig.conf
            echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config.d/00-userconfig.conf
            log "Password authentication disabled."
        fi
    fi

    log "Generating new SSH host keys..."
    ssh-keygen -A
    log "New SSH host keys generated."

    systemctl restart sshd
    log "SSH service restarted with new configuration."

    return_to_main_menu
}

# Function to install Docker
install_docker() {
    log "Installing Docker..."
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
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    apt-get autoremove -y
    rm -rf /var/lib/docker
    log "Docker removed."

    return_to_docker_menu
}

# Function to add a user to the Docker group
add_user_to_docker_group() {
    read -p "Enter the username to add to the Docker group: " docker_user
    usermod -aG docker $docker_user
    log "User $docker_user added to the Docker group."

    return_to_docker_menu
}

# Function to remove a user from the Docker group
remove_user_from_docker_group() {
    read -p "Enter the username to remove from the Docker group: " docker_user
    gpasswd -d $docker_user docker
    log "User $docker_user removed from the Docker group."

    return_to_docker_menu
}

# Function to install Dockge
install_dockge() {
    if ! command -v docker &> /dev/null || ! systemctl is-active --quiet docker; then
        log "Docker is not installed or not running. Please install and start Docker first."
        return_to_docker_menu
        return
    fi

    read -p "Where should Dockge be installed? (default /opt/dockge, press Enter for default): " dockge_dir
    dockge_dir=${dockge_dir:-/opt/dockge}
    read -p "Where should stacks be stored? (default /opt/stacks, press Enter for default): " stacks_dir
    stacks_dir=${stacks_dir:-/opt/stacks}
    read -p "Which port should Dockge use? (default 5001, press Enter for default): " dockge_port
    dockge_port=${dockge_port:-5001}

    log "Installing Dockge..."
    mkdir -p "$dockge_dir" && cd "$dockge_dir" || { log "Failed to create and navigate to $dockge_dir."; return_to_docker_menu; return; }
    curl "https://dockge.kuma.pet/compose.yaml?port=$dockge_port&stacksPath=$stacks_dir" --output compose.yaml || { log "Failed to download Dockge compose file."; return_to_docker_menu; return; }
    docker compose up -d || { log "Failed to start Dockge with Docker Compose."; return_to_docker_menu; return; }

    log "Dockge is running on http://$(hostname -I | awk '{print $1}'):$dockge_port"

    return_to_docker_menu
}

# Function to remove Dockge
remove_dockge() {
    read -p "Where is Dockge installed? (default /opt/dockge, press Enter for default): " dockge_dir
    dockge_dir=${dockge_dir:-/opt/dockge}

    log "Removing Dockge..."
    cd "$dockge_dir" || { log "Failed to navigate to $dockge_dir."; return_to_docker_menu; return; }
    docker compose down || { log "Failed to stop Dockge with Docker Compose."; return_to_docker_menu; return; }
    rm -rf "$dockge_dir" || { log "Failed to remove Dockge directory."; return_to_docker_menu; return; }

    log "Dockge removed."

    return_to_docker_menu
}

# Function to check Docker and Dockge status
check_docker_status() {
    local docker_status dockge_status

    if command -v docker &> /dev/null && systemctl is-active --quiet docker; then
        docker_status="\e[32m✓\e[0m"
    else
        docker_status="\e[31m✗\e[0m"
    fi

    if docker ps | grep -q dockge; then
        dockge_status="\e[32m✓\e[0m"
    else
        dockge_status="\e[31m✗\e[0m"
    fi

    echo -e "||  Docker running: $docker_status  ||  Dockge running: $dockge_status  ||"
    echo -e "|| Users in Docker group: $(getent group docker | awk -F: '{print $4}' | tr ',' ' ') ||"
}

# Function to view the log
view_log() {
    clear
    echo "##############################################"
    echo "#                                            #"
    echo "#                View Log                    #"
    echo "#                                            #"
    echo "##############################################"
    echo
    tail -n 100  $LOG_FILE
    return_to_main_menu
}

# Main menu
main_menu() {
    clear
    echo "##############################################"
    echo "#                                            #"
    echo "#             Server Setup Script            #"
    echo "#                                            #"
    echo "##############################################"
    echo
    echo "Select an option:"
    echo "1) SSH & User setup"
    echo "2) Docker"
    echo "3) Cleanup to prepare for turning into a template"
    echo "L) View log"
    echo "x) Exit"
    read -p "Enter your choice: " choice

    check_root

    case $choice in
        1)
            ssh_user_setup
        ;;
        2)
            docker_menu
        ;;
        3)
            cleanup
        ;;
        L|l)
            view_log
        ;;
        x)
            log "Exiting script."
            exit 0
        ;;
        *)
            echo "Invalid choice."
            return_to_main_menu
        ;;
    esac
}

# Docker submenu
docker_menu() {
    clear
    echo "##############################################"
    echo "#                                            #"
    echo "#               Docker Menu                  #"
    echo "#                                            #"
    echo "##############################################"
    echo
    check_docker_status
    echo
    echo "Select an option:"
    echo "1) Install Docker"
    echo "2) Remove Docker"
    echo "3) Add a user to the Docker group"
    echo "4) Remove a user from the Docker group"
    echo "5) Install Dockge"
    echo "6) Remove Dockge"
    echo "b) Back to main menu"
    read -p "Enter your choice: " docker_choice

    case $docker_choice in
        1)
            install_docker
        ;;
        2)
            remove_docker
        ;;
        3)
            add_user_to_docker_group
        ;;
        4)
            remove_user_from_docker_group
        ;;
        5)
            install_dockge
        ;;
        6)
            remove_dockge
        ;;
        b)
            main_menu
        ;;
        *)
            echo "Invalid choice."
            return_to_docker_menu
        ;;
    esac
}

# Start the script with the main menu
main_menu
