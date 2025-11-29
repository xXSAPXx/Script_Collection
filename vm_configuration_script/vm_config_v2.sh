#!/bin/bash
set -uo pipefail


# Colors for output:
GREEN="\e[32m"
LGREEN="\e[92m"
BLUE="\e[34m"
CYAN="\e[36m"
LBLUE="\e[94m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

# List of DNF Packages to check for and then install:
package_list=("htop" "btop" "atop" "iotop" "sysstat" "lsof" "curl" "wget" "bind-utils" "iproute" "iperf3" "telnet" "tcpdump" "traceroute" "vim-enhanced" "bat" "bash-completion" "git" "tmux" "python3-dnf-plugin-versionlock")

# List of functions for system checks and system configurations to be performed:
func_list_sys_checks=("bash_profile_check" "bash_history_check" "time_format_check" "swappiness_check" "dnf_check")
func_list_sys_config=("bash_profile_config" "bash_history_config" "time_format_config" "swappiness_config" "dnf_config")



# Function to display help:
function show_help() {
    echo "===================================================================================================================="
    echo
    echo -e "${GREEN}Possible Options For Execution:${RESET} 🔧"
    echo
    echo -e "  ${CYAN}--report${RESET}          | Show VM details / Check installed packages / Check for OS Updates."
    echo -e "  ${CYAN}--fix${RESET}             | Check if required packages and repositories are installed - if not, install them."
    echo -e "  ${CYAN}--system_report${RESET}   | Show VM System Configuration -- Prompt / History / Time / etc..."
    echo -e "  ${CYAN}--system_configure${RESET}| Configure Prompt / History / Time / etc..."
    echo -e "  ${CYAN}--update${RESET}          | Check If System Packages are updated - if not, update the system."
    echo -e "  ${CYAN}--help${RESET}            | Display this help message."
    echo
    echo "===================================================================================================================="

}



# Function to print VM details
function print_vm_details() {
    echo -e "_________________________________________________________________________________"
    echo
    echo -e "System Information:"
    echo -e "---------------------"
    echo -e "Static Hostname:        $(hostnamectl --static)"
    echo -e "Operating System:       $(uname -o)"
    echo -e "Distribution:           $(grep PRETTY_NAME /etc/os-release | cut -d '=' -f 2 | tr -d '\"')"
    echo -e "Kernel Version:         $(uname -r)"
    echo -e "Architecture:           $(uname -m)"
    echo
    echo
    echo -e "Hardware Information:"
    echo -e "---------------------"
    echo -e "CPU:                   $(grep -m 1 'model name' /proc/cpuinfo | cut -d ':' -f 2 | xargs)"
    echo -e "Hardware Vendor:       $(dmidecode -s system-manufacturer)"
    echo -e "Firmware Version:      $(dmidecode -s bios-version)"
    echo
    echo
    echo -e "Additional Details:"
    echo -e "---------------------"
    echo -e "Support End Date:      $(grep SUPPORT_END /etc/os-release | cut -d '=' -f 2 | tr -d '\"')"
    echo -e "Bug Report URL:        $(grep BUG_REPORT_URL /etc/os-release | cut -d '=' -f 2 | tr -d '\"')"
    echo
}




# Function to check for system updates
function check_system_updates() {
    echo -e "_________________________________________________________________________________"
    echo
    echo -e "Checking for System Updates:"

    if command -v dnf &>/dev/null; then
        echo
        echo -e "✅  ${GREEN}dnf package manager is available.${RESET}"
        echo

        # Run check-update and store the exit code immediately
        sudo dnf check-update &>/dev/null
        CHECK_UPDATE_EXIT_CODE=$?

        if [ $CHECK_UPDATE_EXIT_CODE -eq 100 ]; then
            echo
            echo -e "╰┈➤   ${YELLOW}Updates are available.${RESET}"
            echo
            echo

        elif [ $CHECK_UPDATE_EXIT_CODE -eq 0 ]; then
            echo -e "✅  ${GREEN}No updates available. Your system is up to date.${RESET}"
            echo

        else
            echo -e "❌  ${RED}Failed to check for updates. Please check your connection or configuration.${RESET}"
            echo
            return 1
        fi

        return 0
    else
        echo
        printf '\u274c  ' && echo -e "${RED}dnf package manager is not installed or not available.${RESET}"
        echo
        return 1
    fi
}



# Function to update system packages
function update_system() {
    echo -e "_________________________________________________________________________________"
    echo
    
    # Check if the user is root
    if [ "$(id -u)" -ne 0 ]; then
        echo
        echo -e "❌  ${RED}Must Be ROOT to run System Update!${RESET}"
        echo
        return 1  # Exit the function with a failure code
    fi
    
    echo -e "Checking for System Updates:"

    if command -v dnf &>/dev/null; then
        echo
        echo -e "✅  ${GREEN}dnf package manager is available.${RESET}"
        echo

        # Run check-update and store the exit code immediately
        sudo dnf check-update &>/dev/null
        CHECK_UPDATE_EXIT_CODE=$?

        if [ $CHECK_UPDATE_EXIT_CODE -eq 100 ]; then
            echo
            echo -e "╰┈➤   ${YELLOW}Updates are available. Installing Updates.... ${RESET}"
            echo
            echo
            sudo dnf upgrade -y
            echo
            echo
            echo -e "╰┈➤   ${GREEN}System updated successfully.${RESET}"
            echo
            echo -e "╰┈➤   ${YELLOW}Reboot is a good practice after OS Update${RESET}"
            echo
            read -p "╰┈➤   Would you like to reboot now? (Y/N): " REBOOT_ANSWER
                	if [[ "$REBOOT_ANSWER" =~ ^[Yy]$ ]]; then
                        	echo
                        	echo -e "🔄  ${YELLOW}Rebooting now...${RESET}"
                        	echo
                        	sudo reboot
                	else
                        	echo
                        	echo -e "╰┈➤   ${YELLOW}Reboot skipped. Please remember to reboot later if required.${RESET}"
                        	echo
                	fi
        elif [ $CHECK_UPDATE_EXIT_CODE -eq 0 ]; then
            echo -e "✅  ${GREEN}No updates available. Your system is up to date.${RESET}"
            echo
        else
            echo -e "❌  ${RED}Failed to check for updates. Please check your connection or configuration.${RESET}"
            echo
            return 1
        fi

        return 0
    else
        echo
        printf '\u274c  ' && echo -e "${RED}dnf package manager is not installed or not available.${RESET}"
        echo
        return 1
    fi
}



#  Function to check if EPEL Repo is installed
function check_epel_repo() {
    echo -e "_________________________________________________________________________________"
    echo
    echo -e "Checking Installed Repositories:"
    echo
    if rpm -q epel-release &>/dev/null; then
        echo -e "✅  ${GREEN}EPEL repository is installed.${RESET}"
        echo
        return 0
    else
        printf '\u274c  ' && echo -e "${RED}EPEL repository is not installed.${RESET}"
        echo
        return 1
    fi
}



#  Function to install EPEL Repo
function install_epel_repo() {
    echo -e "_________________________________________________________________________________"
    echo
    echo -e "Checking Installed Repositories:"
    echo
    if rpm -q epel-release &>/dev/null; then
        echo -e "${GREEN}EPEL repository is already installed.${RESET}"
        echo
        return 0
    else
        echo -e "${YELLOW}Installing EPEL repository...${RESET}"
        sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm &>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}EPEL repository successfully installed.${RESET}"
            echo
            return 0
        else
            echo -e "${RED}Failed to install EPEL repository.${RESET}"
            echo
            return 1
        fi
    fi
}



# Function to check installed packages:
function check_installed_packages() {
    echo -e "_________________________________________________________________________________"
    echo
    echo -e "Checking Installed Packages:"
    echo
    for package in "${package_list[@]}"; do
        if rpm -qa | grep "^${package}-" &>/dev/null; then
            echo
            echo -e "✅  ${GREEN}$package is installed.${RESET}"
        else
            echo
            echo -e "❌  ${RED}$package is not installed.${RESET}"
            echo
        fi
    done
}



# Function to install missing packages:
function install_missing_packages() {
    echo -e "_________________________________________________________________________________"
    echo
    echo -e "Installing Missing Packages:"
    for package in "${package_list[@]}"; do
        if rpm -qa | grep "^${package}-" &>/dev/null; then
            echo
            echo -e "✅  ${GREEN}$package is installed.${RESET}"
        else
            echo
            echo "Installing $package..."
            if sudo dnf install -y "$package" &>/dev/null; then
                echo
                echo -e "${GREEN}$package has been successfully installed.${RESET}"
                echo
            else
                echo
                echo -e "${RED}Failed to install $package.${RESET}"
                echo
            fi
        fi
    done
}



# Function to initiate all check functions in (func_list_sys_checks):
function check_system_config() {
    echo -e "_________________________________________________________________________________"
    echo
    echo -e "Checking System Configuration:"
    echo
    for func in "${func_list_sys_checks[@]}"; do
        if declare -f "$func" > /dev/null; then

            "$func"   # Call the function

        else
            echo -e "${RED}Function $func NOT FOUND!${RESET}"
        fi
    done
}

# Function to initiate all system configure functions in (func_list_sys_config):
function fix_system_config() {
    echo -e "_________________________________________________________________________________"
    echo
    
    # Check if the user is root: 
    if [ "$(id -u)" -ne 0 ]; then
        echo
        echo -e "❌  ${RED}Must Be ROOT to alter System Configuration!${RESET}"
        echo
        return 1  # Exit the function with a failure code
    fi

    echo -e "Checking System Configuration:"
    echo
    
    for func in "${func_list_sys_config[@]}"; do
        if declare -f "$func" > /dev/null; then
            "$func"   # Call the function
        else
            echo -e "${RED}Function $func NOT FOUND!${RESET}"
        fi
    done
}



########################################################## SYSTEM CHECK / CONFIG FUNCTIONS ##########################################################
########################################################## SYSTEM CHECK / CONFIG FUNCTIONS ##########################################################
# Function for checking prompt_configuration:
function bash_profile_check() {

    BASH_PROMPT_SH_FILE=/etc/profile.d/bash_profile.sh

    # Check if prompt is already configured:
    if [[ -f "$BASH_PROMPT_SH_FILE" ]]; then
        if grep -qE '^\s*# Custom Bash Profile Settings:' "$BASH_PROMPT_SH_FILE"; then
            echo
            echo -e "✅  ${GREEN}Bash profile is already configured.${RESET}"
        else
            echo
            echo -e "❌  ${RED}Bash profile is not configured.${RESET}"
        fi
    else
        echo
        echo -e "❌  ${RED}Bash profile is not configured.${RESET}"
    fi
}


# Function for installing prompt_configuration:
function bash_profile_config() {

    BASH_PROMPT_SH_FILE=/etc/profile.d/bash_profile.sh
    ENV_TYPE=$(hostname -s | tr '[:upper:]' '[:lower:]')
    
    # Check if the prompt is already configured:
    if grep -qE '^\s*# Custom Bash Profile Settings:' "$BASH_PROMPT_SH_FILE" &>/dev/null; then
	    echo
	    echo -e "✅  ${GREEN}Bash profile is already configured.${RESET}"
    else
	    echo -e "${YELLOW}Bash profile is not configured. Setting it now...${RESET}"

	    # Append the prompt configuration to file:
	    cat <<EOF > "$BASH_PROMPT_SH_FILE"
# Custom Bash Profile Settings:

# If user ID = 1(ROOT) then set red color for the prompt:
if [ "\$(id -u)" -eq 0 ]; then

    # Aliases: 
    command -v bat >/dev/null 2>&1 && { alias cat='bat -pp'; }
    command -v zoxide >/dev/null 2>&1 && { eval "\$(zoxide init --cmd cd bash)"; }

 case "$ENV_TYPE" in
   *prod*rpl*)
     PS1="\[\e[0;33m\][\[\e[0;31m\]\u\[\e[0;33m\]@\h:\[\e[0;39m\] \w\[\e[0;33m\]]#\[\e[0m\] "
     ;;
   *prod*)
     PS1="\[\e[0;31m\][\[\e[1;31m\]\u\[\e[1;31m\]@\h:\[\e[0;39m\] \w\[\e[0;31m\]]#\[\e[0m\] "
     ;;
   *stg*)
     PS1="\[\e[1;96m\][\[\e[1;31m\]\u\[\e[1;96m\]@\h:\[\e[0;39m\] \w\[\e[1;96m\]]#\[\e[0m\] "
     ;;
   *test*)
     PS1="\[\e[1;34m\][\[\e[1;31m\]\u\[\e[1;34m\]@\h:\[\e[0;39m\] \w\[\e[1;34m\]]#\[\e[0m\] "
     ;;
   *dev*)
     PS1="\[\e[1;32m\][\[\e[1;31m\]\u\[\e[1;32m\]@\h:\[\e[0;39m\] \w\[\e[1;32m\]]#\[\e[0m\] "
     ;;
   *)
    PS1="\[\e[1;32m\][\[\e[1;31m\]\u\[\e[1;32m\]@\h:\[\e[0;39m\] \w\[\e[1;32m\]]#\[\e[0m\] "
     ;;
 esac
fi
EOF
    
	    echo -e "╰┈➤   ✅  ${GREEN}Bash profile successfully configured!${RESET}"
    fi
}



# Function to check if bash history is configured:
function bash_history_check() {

    BASH_HISTORY_SH_FILE=/etc/profile.d/bash_history.sh
	
    if [[ -f "$BASH_HISTORY_SH_FILE" ]]; then 
	if grep -qE '^\s*# ROOT User Bash History Configuration:' "$BASH_HISTORY_SH_FILE"; then
		echo
		echo -e "✅  ${GREEN}Bash history is already configured.${RESET}"
	else
		echo
		echo -e "❌  ${RED}Bash history is not configured.${RESET}"
	fi
    else
	    echo
        echo -e "❌  ${RED}Bash history is not configured.${RESET}"
    fi
}



# Function to configure bash history:
function bash_history_config() {
    
    touch /etc/profile.d/bash_history.sh &>/dev/null
    BASH_HISTORY_SH_FILE=/etc/profile.d/bash_history.sh

    if grep -qE '^\s*# ROOT User Bash History Configuration:' "$BASH_HISTORY_SH_FILE"; then
        echo
        echo -e "✅  ${GREEN}Bash history is already configured.${RESET}"
    else
        echo
        echo -e "${YELLOW}Configuring Bash history settings...${RESET}"

        # Add history config settings:
        cat <<'EOF' > "$BASH_HISTORY_SH_FILE"
# ROOT User Bash History Configuration:

BLUE="\e[34m"
YELLOW="\e[33m"
GREEN="\e[32m"
RESET="\e[0m"

# RAM History Buffer and Disk file size: 
HISTSIZE=1000
HISTFILESIZE=2000

# No bash commands are gonna be ignored (Only duplicate commands executed consecutively) 
HISTIGNORE=''
HISTCONTROL='ignoredups'

# Persist command history immediately:
PROMPT_COMMAND='history -a'

# Command Timestamps:
HISTTIMEFORMAT=`echo -e ${GREEN}[${RESET}%F %T ${YELLOW}UTC${RESET}${GREEN}] $RESET`
EOF

        echo -e "╰┈➤   ✅  ${GREEN}Bash history settings added successfully!${RESET}"
    fi
}



# Function to check VM time format:
function time_format_check() {
	
    TIME_FORMAT_CONFIG_FILE="/etc/locale.conf"
	
    if grep -qE '^\s*LC_TIME=' "$TIME_FORMAT_CONFIG_FILE"; then
	    echo
	    echo -e "✅  ${GREEN}Time Format is already configured.${RESET}"
    else
	    echo
	    echo -e "❌  ${RED}Time Format is not configured.${RESET}"
    fi
}



# Function to configure VM time format:
function time_format_config() {
	
    TIME_FORMAT_CONFIG_FILE="/etc/locale.conf"
    	
    if grep -qE '^\s*LC_TIME=' "$TIME_FORMAT_CONFIG_FILE"; then
	    echo
	    echo -e "✅  ${GREEN}Time Format is already configured.${RESET}"
    else
	    echo
	    echo -e "${YELLOW}Time Format is not configured. Setting it now...${RESET}"
			
	    # Apply the changes using localectl
	    echo "LC_TIME=C.UTF-8" | tee -a "$TIME_FORMAT_CONFIG_FILE" > /dev/null
			
	    echo -e "╰┈➤   ✅  ${GREEN}Time Format set successfully!${RESET}"
    fi	
}



# Function to check VM swappiness:
function swappiness_check() {

    SWAPPINESS_VALUE=$(cat /proc/sys/vm/swappiness)

    if [[ "$SWAPPINESS_VALUE" -eq 1 ]]; then
        echo
        echo -e "✅  ${GREEN}Swappiness is set to 1.${RESET}"
    else
        echo
        echo -e "❌  ${YELLOW}Swappiness is set to $SWAPPINESS_VALUE.${RESET}"
    fi
}



# Function to configure VM swappiness:
function swappiness_config() {

    SWAPPINESS_SYSTEM_FILE="/proc/sys/vm/swappiness"
    SWAPPINESS_VALUE=$(cat $SWAPPINESS_SYSTEM_FILE)
    SWAPPINESS_CONFIG_FILE="/etc/sysctl.d/99-swappiness.conf"
    touch $SWAPPINESS_CONFIG_FILE &>/dev/null
    
    if [[ "$SWAPPINESS_VALUE" -eq 1 ]]; then
        echo
        echo -e "✅  ${GREEN}Swappiness is already configured to ${SWAPPINESS_VALUE}.${RESET}"
    else 
        echo
        echo -e "${YELLOW}VM Swappiness is set to ${SWAPPINESS_VALUE}. Fixing it now...${RESET}"

        # Set swappiness for the current session / Sysctl SWAPPINESS_CONFIG_FILE to persist on reboot
        echo 1 | sudo tee $SWAPPINESS_SYSTEM_FILE > /dev/null
        echo "vm.swappiness=1" | sudo tee "$SWAPPINESS_CONFIG_FILE" > /dev/null
        
        # Apply the SWAPPINESS_CONFIG_FILE
        sysctl -p $SWAPPINESS_CONFIG_FILE > /dev/null
        
        echo -e "╰┈➤   ✅  ${GREEN}Swappiness has been configured to 1.${RESET}"
    fi    
}



# Function to check DNF settings:
function dnf_check() {

    DNF_CONF_FILE="/etc/dnf/dnf.conf"

    if [[ -f "$DNF_CONF_FILE" ]]; then
        if grep -qE '^\s*# DNF Custom Configuration Settings:' "$DNF_CONF_FILE"; then
            echo
            echo -e "✅  ${GREEN}DNF settings are already configured. ${RESET}"
        else
            echo
            echo -e "❌  ${RED}DNF settings are not configured.${RESET}"
        fi
    else
        echo
        echo -e "❌  ${RED}DNF configuration file not found.${RESET}"
    fi
}



# Function to configure DNF settings:
function dnf_config() {

    DNF_CONF_FILE="/etc/dnf/dnf.conf"
    LOCATION_CODE=$(curl -s https://ipinfo.io/country)
    if [[ -z "$LOCATION_CODE" ]]; then
        LOCATION_CODE="US"
    fi

    CPU_COUNT=$(nproc --all) 
    if [ "$CPU_COUNT" -ge 8 ]; then 
        CPU_COUNT=4 
    else 
        CPU_COUNT=1 
    fi


    if [[ -f "$DNF_CONF_FILE" ]]; then
        if grep -qE '^\s*# DNF Custom Configuration Settings:' "$DNF_CONF_FILE"; then
            echo
            echo -e "✅  ${GREEN}DNF settings are already configured.${RESET}"
        else
            echo
            echo -e "${YELLOW}Configuring DNF settings...${RESET}"
            
            # Backup existing dnf.conf file:
            cp "$DNF_CONF_FILE" "${DNF_CONF_FILE}_orginal_backup_$(date +%F_%T)"
            
            # Append the configuration to the file:
            cat <<EOF > "$DNF_CONF_FILE"
# DNF Custom Configuration Settings:
[main]

gpgcheck=1
fastestmirror=True
best=True
deltarpm=True
clean_requirements_on_remove=True
installonly_limit=3
install_weak_deps=True
skip_if_unavailable=False

metadata_timer_sync=3600
bandwidth=1M
max_parallel_downloads=${CPU_COUNT}
country=${LOCATION_CODE}

EOF

            echo -e "╰┈➤   ✅  ${GREEN}DNF settings configured successfully!${RESET}"
        fi
    else
        echo
        echo -e "❌  ${RED}DNF configuration file not found.${RESET}"
    fi
}


# Function to disable SELINUX:

# Function to desable THP / enable MHP:



# TO DO LIST: 
#### CHECK / CONFIGURE TCP Socket Buffers 
#### CHECK NETWORK keepalive()
#### CHANGE AIO MAX Number 
#### KERNEL FREE KB CHECK AND CONF / DIRTY VM RATIO 
#### DELAY ACCOUNTING / for iotop
#### UDEV RULES 
#### Jemmaloc if needed
#### Available packages for installation (show commands for installation)






##########################################################################################################################################################
#                     Main script logic                           Main script logic                               Main script logic                      #
##########################################################################################################################################################

# Main Script Logic Function:
function main() {
    if [ -z "$1" ]; then
        echo
        echo -e "╰┈➤   ${RED}Error: Exactly one argument is required.${RESET}"
        show_help
        exit 1
    fi

# Main Script Logic Based on the Argument Provided:
    case "$1" in
        --report)
            print_vm_details
            check_epel_repo
            check_installed_packages
            check_system_updates
            ;;
        --fix)
            install_epel_repo
            install_missing_packages
            check_system_updates
            ;;
        --system_report)
            check_system_config
            ;;
        --system_configure)
            fix_system_config
            ;;
        --update)
            update_system
            ;;
        --help)
            show_help
            ;;
        *)
            echo 
            echo -e "╰┈➤   ${RED}Error: Invalid argument '$1'.${RESET}"
            show_help
            exit 1
            ;;
    esac
}

# Call the main function with the provided arguments:
main "${1:-}"




