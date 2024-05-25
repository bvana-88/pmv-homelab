#!/bin/bash

LOG_FILE="/var/log/setup-script.log"
USER_CONFIG_DIR="/etc/ssh/sshd_config.d"
USER_CONFIG_PREFIX="userconfig.conf"

# Function to check if the script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root. Please run with sudo or as root user."
        exit 1
    fi
}

# Function to log messages
log() {
    local message=$1
    local status=$2
    local color_reset="\e[0m"
    local green_tick="\e[32m✓\e[0m"
    local red_cross="\e[31m✗\e[0m"
    local sand_color="\e[38;5;222m"

    if [[ $status -eq 0 ]]; then
        echo -e "$(date +'%Y-%m-%d %H:%M:%S') - ${green_tick} $message" | tee -a $LOG_FILE
    else
        echo -e "$(date +'%Y-%m-%d %H:%M:%S') - ${red_cross} $message" | tee -a $LOG_FILE
        echo -e "$(date +'%Y-%m-%d %H:%M:%S') - \e[31mError:\e[0m $status" | tee -a $LOG_FILE
    fi
}

# Function to run commands and log their status
run_command() {
    local command="$1"
    local sand_color="\e[38;5;222m"
    local color_reset="\e[0m"
    echo -e "${sand_color}    $command${color_reset}" | tee -a $LOG_FILE
    eval $command
    local status=$?
    log "$command" $status
    return $status
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
    run_command "apt update && apt upgrade -y"
    return_to_main_menu
}

# Function to get the user config file path
get_user_config_file() {
    local existing_files=($USER_CONFIG_DIR/*-userconfig.conf)
    if [[ ${#existing_files[@]} -gt 0 ]]; then
        echo "${existing_files[0]}"
    else
        local highest=0
        for file in $USER_CONFIG_DIR/*; do
            if [[ $file =~ $USER_CONFIG_DIR/([0-9]+)-.* ]]; then
                number=${BASH_REMATCH[1]}
                if (( number > highest )); then
                    highest=$number
                fi
            fi
        done
        local next_number=$(printf "%02d" $((highest + 1)))
        echo "$USER_CONFIG_DIR/${next_number}-${USER_CONFIG_PREFIX}"
    fi
}

# Function to display current SSH settings
display_ssh_settings() {
    local ssh_status root_login protocol_version password_login ssh_port
    local user_config_file=$(get_user_config_file)

    if systemctl is-active --quiet ssh; then
        ssh_status="\e[32mEnabled\e[0m"
        ssh_port=$(grep "^Port " $USER_CONFIG_DIR/* 2>/dev/null | awk '{print $2}')
        ssh_port=${ssh_port:-22}
    else
        ssh_status="\e[31mDisabled\e[0m"
        ssh_port="\e[31m-\e[0m"
        root_login="\e[31m-\e[0m"
        protocol_version="\e[31m-\e[0m"
        password_login="\e[31m-\e[0m"
    fi

    if [[ $ssh_status == *"Enabled"* ]]; then
        if grep -q "^PermitRootLogin yes" $USER_CONFIG_DIR/* 2>/dev/null; then
            root_login="\e[32mEnabled\e[0m"
        else
            root_login="\e[31mDisabled\e[0m"
        fi

        if grep -q "^Protocol 2" $USER_CONFIG_DIR/* 2>/dev/null; then
            protocol_version="\e[32m2\e[0m"
        else
            protocol_version="\e[31mNot set\e[0m"
        fi

        if grep -q "^PasswordAuthentication yes" $USER_CONFIG_DIR/* 2>/dev/null; then
            password_login="\e[32mEnabled\e[0m"
        else
            password_login="\e[31mDisabled\e[0m"
        fi
    fi

    echo -e "||  SSH: $ssh_status  ||  Port: $ssh_port  ||  Root Login: $root_login  ||  Protocol: $protocol_version  ||  Password Login: $password_login  ||"
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
    local user_config_file=$(get_user_config_file)
    if [[ ! -f $user_config_file ]]; then
        echo -e "\e[31mConfig file not found, make a selection to create it.\e[0m"
    fi
    display_ssh_settings
    echo
    echo "Select an option:"
    echo "1) View Config - Displays the current SSH configuration and file location."
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
            view_ssh_config
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

# Function to view SSH config
view_ssh_config() {
    local user_config_file=$(get_user_config_file)
    clear
    echo "##############################################"
    echo "#                                            #"
    echo "#             SSH Configuration              #"
    echo "#                                            #"
    echo "##############################################"
    echo
    if [[ -f $user_config_file ]]; then
        echo "Configuration file location: $user_config_file"
        echo
        cat $user_config_file
    else
        echo "No configuration file found."
    fi
    echo
    return_to_ssh_menu
}

# Function to enable/disable SSH
enable_disable_ssh() {
    if systemctl is-active --quiet ssh; then
        run_command "systemctl stop ssh && systemctl stop ssh.socket && systemctl disable ssh.socket"
        log "SSH disabled." 0
    else
        run_command "systemctl start ssh && systemctl enable ssh.socket && systemctl start ssh.socket"
        log "SSH enabled." 0
    fi
    return_to_ssh_menu
}

# Function to enable/disable root login
enable_disable_root_login() {
    local user_config_file=$(get_user_config_file)
    if [[ ! -f $user_config_file ]]; then
        touch $user_config_file
        log "Created SSH user configuration file: $user_config_file" 0
    fi
    if grep -q "^PermitRootLogin yes" $user_config_file; then
        run_command "sed -i '/^PermitRootLogin /d' $user_config_file"
        echo "PermitRootLogin no" >> $user_config_file
        log "Root login disabled." 0
    else
        run_command "sed -i '/^PermitRootLogin /d' $user_config_file"
        echo "PermitRootLogin yes" >> $user_config_file
        log "Root login enabled." 0
    fi
    run_command "systemctl restart sshd"
    return_to_ssh_menu
}

# Function to change SSH port
change_ssh_port() {
    local user_config_file=$(get_user_config_file)
    if [[ ! -f $user_config_file ]]; then
        touch $user_config_file
        log "Created SSH user configuration file: $user_config_file" 0
    fi
    read -p "Enter the new SSH port: " ssh_port
    run_command "sed -i '/^Port /d' $user_config_file"
    echo "Port $ssh_port" >> $user_config_file
    log "SSH port set to $ssh_port." 0
    run_command "systemctl restart sshd"
    return_to_ssh_menu
}

# Function to set SSH protocol
set_ssh_protocol() {
    local user_config_file=$(get_user_config_file)
    if [[ ! -f $user_config_file ]]; then
        touch $user_config_file
        log "Created SSH user configuration file: $user_config_file" 0
    fi
    run_command "sed -i '/^Protocol /d' $user_config_file"
    echo "Protocol 2" >> $user_config_file
    log "SSH protocol set to 2." 0
    run_command "systemctl restart sshd"
    return_to_ssh_menu
}

# Function to enable/disable password login
enable_disable_password_login() {
    local user_config_file=$(get_user_config_file)
    if [[ ! -f $user_config_file ]]; then
        touch $user_config_file
        log "Created SSH user configuration file: $user_config_file" 0
    fi
    if grep -q "^PasswordAuthentication yes" $user_config_file; then
        run_command "sed -i '/^PasswordAuthentication /d' $user_config_file"
        echo "PasswordAuthentication no" >> $user_config_file
        echo "PubkeyAuthentication yes" >> $user_config_file
        log "Password login disabled." 0
    else
        run_command "sed -i '/^PasswordAuthentication /d' $user_config_file"
        echo "PasswordAuthentication yes" >> $user_config_file
        log "Password login enabled." 0
    fi
    run_command "systemctl restart sshd"
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
    run_command "useradd -m -s /bin/bash $username"
    echo "$username:$password" | chpasswd
    log "User $username created." 0

    read -p "Should the user be added to the sudo group? (y/n): " sudo_confirm
    if [[ "${sudo_confirm:0:1}" =~ ^[Yy]$ ]]; then
        run_command "usermod -aG sudo $username"
        log "User $username added to sudo group." 0
    fi
    return_to_user_menu
}

# Function to remove a user
remove_user() {
    read -p "Enter the username to remove: " username
    run_command "deluser --remove-home $username"
    log "User $username removed." 0
    return_to_user_menu
}

# Function to set nopassword for sudo group
set_nopassword_sudo() {
    run_command "echo '%sudo ALL=(ALL) NOPASSWD:ALL' | EDITOR='tee -a' visudo"
    log "Configured sudo group with NOPASSWD." 0
    return_to_user_menu
}

# Function to install Docker
install_docker() {
    run_command "apt-get update"
    run_command "apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release"
    log "Installed packages: apt-transport-https, ca-certificates, curl, gnupg, lsb-release." 0

    run_command "install -m 0755 -d /etc/apt/keyrings"
    log "Created directory /etc/apt/keyrings." 0

    run_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
    log "Downloaded and added Docker GPG key." 0

    run_command "echo 'deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable' | tee /etc/apt/sources.list.d/docker.list > /dev/null"
    log "Added Docker repository." 0

    run_command "apt-get update"
    run_command "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    log "Installed packages: docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin." 0

    log "Docker installed." 0
    run_command "docker run hello-world"
    if [[ $? -eq 0 ]]; then
        log "Docker was installed and verified successfully." 0
    else
        log "Docker installation verification failed." 1
    fi

    return_to_docker_menu
}

# Function to remove Docker
remove_docker() {
    run_command "apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    log "Purged packages: docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin." 0
    run_command "apt-get autoremove -y"
    log "Removed unused packages." 0
    run_command "rm -rf /var/lib/docker"
    log "Removed Docker data in /var/lib/docker." 0

    return_to_docker_menu
}

# Function to add a user to the Docker group
add_user_to_docker_group() {
    read -p "Enter the username to add to the Docker group: " docker_user
    run_command "usermod -aG docker $docker_user"
    log "User $docker_user added to the Docker group." 0

    return_to_docker_menu
}

# Function to remove a user from the Docker group
remove_user_from_docker_group() {
    read -p "Enter the username to remove from the Docker group: " docker_user
    run_command "gpasswd -d $docker_user docker"
    log "User $docker_user removed from the Docker group." 0

    return_to_docker_menu
}

# Function to install Dockge
install_dockge() {
    if ! command -v docker &> /dev/null || ! systemctl is-active --quiet docker; then
        log "Docker is not installed or not running. Please install and start Docker first." 1
        return_to_docker_menu
        return
    fi

    read -p "Where should Dockge be installed? (default /opt/dockge, press Enter for default): " dockge_dir
    dockge_dir=${dockge_dir:-/opt/dockge}
    read -p "Where should stacks be stored? (default /opt/stacks, press Enter for default): " stacks_dir
    stacks_dir=${stacks_dir:-/opt/stacks}
    read -p "Which port should Dockge use? (default 5001, press Enter for default): " dockge_port
    dockge_port=${dockge_port:-5001}

    run_command "mkdir -p '$dockge_dir' && cd '$dockge_dir'"
    log "Created directory $dockge_dir." 0
    run_command "curl 'https://dockge.kuma.pet/compose.yaml?port=$dockge_port&stacksPath=$stacks_dir' --output compose.yaml"
    log "Downloaded Dockge compose file." 0
    run_command "docker compose up -d"
    log "Dockge is running on http://$(hostname -I | awk '{print $1}'):$dockge_port" 0

    return_to_docker_menu
}

# Function to remove Dockge
remove_dockge() {
    read -p "Where is Dockge installed? (default /opt/dockge, press Enter for default): " dockge_dir
    dockge_dir=${dockge_dir:-/opt/dockge}

    run_command "cd '$dockge_dir'"
    run_command "docker compose down"
    log "Stopped Dockge with Docker Compose." 0
    run_command "rm -rf '$dockge_dir'"
    log "Removed Dockge directory $dockge_dir." 0

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

    if command -v docker &> /dev/null && docker ps | grep -q dockge; then
        dockge_status="\e[32m✓\e[0m"
    else
        dockge_status="\e[31m✗\e[0m"
    fi

    echo -e "||  Docker running: $docker_status  ||  Dockge running: $dockge_status  ||"
    if command -v getent &> /dev/null; then
        echo -e "|| Users in Docker group: $(getent group docker | awk -F: '{print $4}' | tr ',' ' ') ||"
    else
        echo -e "|| Users in Docker group: Unable to determine (getent not found) ||"
    fi
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
    echo "1) Update System"
    echo "2) SSH setup"
    echo "3) User setup"
    echo "4) Docker"
    echo "5) Cleanup to prepare for turning into a template"
    echo "L) View log"
    echo "x) Exit"
    read -p "Enter your choice: " choice

    check_root

    case $choice in
        1)
            update_system
        ;;
        2)
            ssh_menu
        ;;
        3)
            user_menu
        ;;
        4)
            docker_menu
        ;;
        5)
            cleanup
        ;;
        L|l)
            view_log
        ;;
        x)
            log "Exiting script." 0
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
