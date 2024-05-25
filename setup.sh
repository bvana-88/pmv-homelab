#!/bin/bash

LOG_FILE="/var/log/setup-script.log"
USER_CONFIG_FILE="/etc/ssh/sshd_config.d/00-userconfig.conf"

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

# Function to return to the SSH menu
return_to_ssh_menu() {
    echo
    echo "Press Enter to return to the SSH menu..."
    read
    ssh_menu
}

# Function to return to the User menu
return_to_user_menu() {
    echo
    echo "Press Enter to return to the User menu..."
    read
    user_menu
}

# Function to return to the Docker menu
return_to_docker_menu() {
    echo
    echo "Press Enter to return to the Docker menu..."
    read
    docker_menu
}

# Function to update system
update_system() {
    log "Updating the system..."
    apt update && apt upgrade -y
    log "System updated."
    return_to_ssh_menu
}

# Function to ensure SSH config file exists
ensure_ssh_config_file() {
    if [[ ! -f $USER_CONFIG_FILE ]]; then
        touch $USER_CONFIG_FILE
        log "Created SSH user configuration file: $USER_CONFIG_FILE"
    fi
}

# Function to display current SSH settings
display_ssh_settings() {
    ensure_ssh_config_file
    local ssh_status root_login protocol_version password_login

    if systemctl is-active --quiet ssh; then
        ssh_status="\e[32mEnabled\e[0m"
    else
        ssh_status="\e[31mDisabled\e[0m"
    fi

    if grep -q "^PermitRootLogin yes" $USER_CONFIG_FILE; then
        root_login="\e[32mEnabled\e[0m"
    else
        root_login="\e[31mDisabled\e[0m"
    fi

    if grep -q "^Protocol 2" $USER_CONFIG_FILE; then
        protocol_version="\e[32m2\e[0m"
    else
        protocol_version="\e[31mNot set\e[0m"
    fi

    if grep -q "^PasswordAuthentication yes" $USER_CONFIG_FILE; then
        password_login="\e[32mEnabled\e[0m"
    else
        password_login="\e[31mDisabled\e[0m"
    fi

    echo -e "||  SSH: $ssh_status  ||  Root Login: $root_login  ||  Protocol: $protocol_version  ||  Password Login: $password_login  ||"
}

# Function to display current user settings
display_user_settings() {
    local user_list users

    users=$(ls /home)
    for user in $users; do
        if id -nG "$user" | grep -qw sudo; then
            sudo_status="\e[32m✓\e[0m"
        else
            sudo_status="\e[31m✗\e[0m"
        fi
        user_list+="||  $user  ||  sudo: $sudo_status  ||\n"
    done

    echo -e "$user_list"
}

# SSH setup menu
ssh_menu() {
    clear
    echo "##############################################"
    echo "#                                            #"
    echo "#                SSH Menu                    #"
    echo "#                                            #"
    echo "##############################################"
    echo
    display_ssh_settings
    echo
    echo "Select an option:"
    echo "1) Update System - Ensures your system is up to date with the latest security patches and software."
    echo "2) Enable/Disable SSH - Allows remote login to your server. It's essential for remote management."
    if systemctl is-active --quiet ssh; then
        echo "3) Enable/Disable Root Login - Allows or disallows root user to login via SSH. Disabling root login enhances security."
        echo "4) Change SSH Port - Changes the default SSH port from 22 to another port to avoid common attacks."
        echo "5) Set Protocol to 2 - Ensures SSH uses protocol version 2, which is more secure."
        echo "6) Enable/Disable Password Login - Allows or disallows password-based login. Disabling it and using keys increases security."
    fi
    echo "b) Back to main menu"
    read -p "Enter your choice: " ssh_choice

    case $ssh_choice in
        1)
            update_system
        ;;
        2)
            enable_disable_ssh
        ;;
        3)
            if systemctl is-active --quiet ssh; then
                enable_disable_root_login
            else
                ssh_menu
            fi
        ;;
        4)
            if systemctl is-active --quiet ssh; then
                change_ssh_port
            else
                ssh_menu
            fi
        ;;
        5)
            if systemctl is-active --quiet ssh; then
                set_ssh_protocol
            else
                ssh_menu
            fi
        ;;
        6)
            if systemctl is-active --quiet ssh; then
                enable_disable_password_login
            else
                ssh_menu
            fi
        ;;
        b)
            main_menu
        ;;
        *)
            echo "Invalid choice."
            return_to_ssh_menu
        ;;
    esac
}

# Function to enable/disable SSH
enable_disable_ssh() {
    if systemctl is-active --quiet ssh; then
        log "Disabling SSH..."
        systemctl stop ssh
        log "SSH disabled."
    else
        log "Enabling SSH..."
        systemctl start ssh
        log "SSH enabled."
    fi
    return_to_ssh_menu
}

# Function to enable/disable root login
enable_disable_root_login() {
    ensure_ssh_config_file
    if grep -q "^PermitRootLogin yes" $USER_CONFIG_FILE; then
        sed -i "/^PermitRootLogin /d" $USER_CONFIG_FILE
        echo "PermitRootLogin no" >> $USER_CONFIG_FILE
        log "Root login disabled."
    else
        sed -i "/^PermitRootLogin /d" $USER_CONFIG_FILE
        echo "PermitRootLogin yes" >> $USER_CONFIG_FILE
        log "Root login enabled."
    fi
    systemctl restart sshd
    return_to_ssh_menu
}

# Function to change SSH port
change_ssh_port() {
    ensure_ssh_config_file
    read -p "Enter the new SSH port: " ssh_port
    sed -i "/^Port /d" $USER_CONFIG_FILE
    echo "Port $ssh_port" >> $USER_CONFIG_FILE
    log "SSH port set to $ssh_port."
    systemctl restart sshd
    return_to_ssh_menu
}

# Function to set SSH protocol
set_ssh_protocol() {
    ensure_ssh_config_file
    sed -i "/^Protocol /d" $USER_CONFIG_FILE
    echo "Protocol 2" >> $USER_CONFIG_FILE
    log "SSH protocol set to 2."
    systemctl restart sshd
    return_to_ssh_menu
}

# Function to enable/disable password login
enable_disable_password_login() {
    ensure_ssh_config_file
    if grep -q "^PasswordAuthentication yes" $USER_CONFIG_FILE; then
        sed -i "/^PasswordAuthentication /d" $USER_CONFIG_FILE
        echo "PasswordAuthentication no" >> $USER_CONFIG_FILE
        echo "PubkeyAuthentication yes" >> $USER_CONFIG_FILE
        log "Password login disabled."
    else
        sed -i "/^PasswordAuthentication /d" $USER_CONFIG_FILE
        echo "PasswordAuthentication yes" >> $USER_CONFIG_FILE
        log "Password login enabled."
    fi
    systemctl restart sshd
    return_to_ssh_menu
}

# User setup menu
user_menu() {
    clear
    echo "##############################################"
    echo "#                                            #"
    echo "#                User Menu                   #"
    echo "#                                            #"
    echo "##############################################"
    echo
    display_user_settings
    echo
    echo "Select an option:"
    echo "1) Add User - Creates a new user account."
    echo "2) Remove User - Removes an existing user account."
    echo "3) Sudo: Set Nopassword - Configures sudo group to not require a password."
    echo "b) Back to main menu"
    read -p "Enter your choice: " user_choice

    case $user_choice in
        1)
            add_user
        ;;
        2)
            remove_user
        ;;
        3)
            set_nopassword_sudo
        ;;
        b)
            main_menu
        ;;
        *)
            echo "Invalid choice."
            return_to_user_menu
        ;;
    esac
}

# Function to add a user
add_user() {
    read -p "Enter the new username: " username
    read -s -p "Enter the password for $username: " password
    echo
    useradd -m -s /bin/bash $username
    echo "$username:$password" | chpasswd
    log "User $username created."

    read -p "Should the user be added to the sudo group? (y/n): " sudo_confirm
    if [[ "${sudo_confirm:0:1}" =~ ^[Yy]$ ]]; then
        usermod -aG sudo $username
        log "User $username added to sudo group."
    fi
    return_to_user_menu
}

# Function to remove a user
remove_user() {
    read -p "Enter the username to remove: " username
    deluser --remove-home $username
    log "User $username removed."
    return_to_user_menu
}

# Function to set nopassword for sudo group
set_nopassword_sudo() {
    echo "%sudo ALL=(ALL) NOPASSWD:ALL" | EDITOR='tee -a' visudo
    log "Configured sudo group with NOPASSWD."
    return_to_user_menu
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
    log "Installed packages: apt-transport-https, ca-certificates, curl, gnupg, lsb-release."

    install -m 0755 -d /etc/apt/keyrings
    log "Created directory /etc/apt/keyrings."

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    log "Downloaded and added Docker GPG key."

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    log "Added Docker repository."

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    log "Installed packages: docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin."

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
    log "Purged packages: docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin."
    apt-get autoremove -y
    log "Removed unused packages."
    rm -rf /var/lib/docker
    log "Removed Docker data in /var/lib/docker."

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
    log "Created directory $dockge_dir."
    curl "https://dockge.kuma.pet/compose.yaml?port=$dockge_port&stacksPath=$stacks_dir" --output compose.yaml || { log "Failed to download Dockge compose file."; return_to_docker_menu; return; }
    log "Downloaded Dockge compose file."
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
    log "Stopped Dockge with Docker Compose."
    rm -rf "$dockge_dir" || { log "Failed to remove Dockge directory."; return_to_docker_menu; return; }
    log "Removed Dockge directory $dockge_dir."

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
    tail -n 100 $LOG_FILE
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
    echo "1) SSH setup"
    echo "2) User setup"
    echo "3) Docker"
    echo "4) Cleanup to prepare for turning into a template"
    echo "L) View log"
    echo "x) Exit"
    read -p "Enter your choice: " choice

    check_root

    case $choice in
        1)
            ssh_menu
        ;;
        2)
            user_menu
        ;;
        3)
            docker_menu
        ;;
        4)
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
