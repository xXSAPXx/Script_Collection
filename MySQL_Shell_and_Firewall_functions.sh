#!/usr/bin/env bash
set -uo pipefail 
#set -x


RED="\e[1;31m"
GREEN="\e[32m"
BLUE="\e[34m"
LGREEN="\e[92m"
LBLUE="\e[94m"
ENDCOLOR="\e[0m"

CROSS_MARK_COLOR=$(tput setaf 9;printf '\u2718';tput sgr0)
CHECK_MARK_COLOR=$(tput setaf 10;printf '\u2714';tput sgr0)
INFO_MARK_COLOR=$(tput setaf 12;printf '\u26ac';tput sgr0)



################### FIREWALLD PORTS VALIDATION FUNCTION ###################

function firewalld_ports_validation() {

command -v systemctl &>/dev/null && systemctl is-active firewalld > /dev/null
FIREWALLD_STATUS=$?

ports=$(firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | awk '{printf "%s  ", $1}' 2>/dev/null)

    if [[ $FIREWALLD_STATUS -eq 0 ]]; then

        if [[ "$ports" == *"9100/tcp"* && "$ports" == *"9104/tcp"* ]]; then
            printf '\t%b\n' "[${INFO_MARK_COLOR}] Firewalld Ports are configured correctly."
        else
            printf '\t%b\n' "[${CROSS_MARK_COLOR}] Firewalld Ports are Not configured."
        fi
    
    else
        printf '\t%b\n' "[${CROSS_MARK_COLOR}] Firewalld is Not Active."
    fi
}


################### FIREWALLD PORTS CONFIGURATION FUNCTION ###################

function firewalld_ports_configuration() {

command -v systemctl &>/dev/null && systemctl is-active firewalld > /dev/null
FIREWALLD_STATUS=$?

ports=$(firewall-cmd --list-ports 2>/dev/null | tr ' ' '\n' | awk '{printf "%s  ", $1}')

if [[ $FIREWALLD_STATUS -eq 0 ]]; then

        if [[ "$ports" == *"9100/tcp"* && "$ports" == *"9104/tcp"* ]]; then
            printf '\t%b\n' "[${INFO_MARK_COLOR}] Firewalld Ports are already configured."

        else
            sudo firewall-cmd --add-port={9100/tcp,9104/tcp} --permanent >/dev/null 2>&1
            sudo firewall-cmd --reload >/dev/null 2>&1
            printf '\t%b\n' "[${INFO_MARK_COLOR}] Firewalld Ports are configured successfully."
        fi
    
    else
        printf '\t%b\n' "[${CROSS_MARK_COLOR}] Firewalld is Not Active."
    fi
}




################### MySQL SHELL VALIDATION FUNCTION ###################

function mysqlsh_validation() {
    command -v mysqlsh >/dev/null 2>&1
    if [ $? -eq 0 ]; then
		printf '\t%b\n' "[${INFO_MARK_COLOR}] MySQL Shell Version: ${LGREEN}$(mysqlsh -V | awk -F'MySQL ' '{print $2 $3}')${ENDCOLOR} is installed."
    else
        printf '\t%b\n' "[${CROSS_MARK_COLOR}] MySQL Shell is not installed."
		
        check=$(rpm -q --all --queryformat '%{NAME}\n' "percona-release")
        if [[ -z "$check" ]]; then
            printf '\t%b\n' "[${CROSS_MARK_COLOR}] Percona REPO is not installed."
        else
            printf '\t%b\n' "[${INFO_MARK_COLOR}] You can install MySQL manually with \"${LGREEN}dnf install -y percona-mysql-shell${ENDCOLOR}\""    
	    fi
    fi
}



################### MySQL SHELL INSTALL FUNCTION ###################

function mysqlsh_installation() {
    command -v mysqlsh >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        printf '\t%b\n' "[${INFO_MARK_COLOR}] MySQL Shell Version: ${LGREEN}$(mysqlsh -V | awk -F'MySQL ' '{print $2 $3}')${ENDCOLOR} is installed."

    else
        check=$(rpm -q --all --queryformat '%{NAME}\n' "percona-release")
        if [[ -z "$check" ]]; then 
            printf '\t%b\n' "[${CROSS_MARK_COLOR}] Percona REPO is not installed."
        
        else
            printf '\t%b\n' "[${INFO_MARK_COLOR}] Installing Percona MySQL Shell."
            if sudo dnf install -y percona-mysql-shell >/dev/null 2>&1; then
		        printf '\t%b\n' "[${CHECK_MARK_COLOR}] MySQL Shell Version: ${LGREEN}$(mysqlsh -V | awk -F'MySQL ' '{print $2}')${ENDCOLOR} is installed successfully."
            
            else 
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Failed to install MySQL Shell. Please check your setup."
            fi
        fi
    fi       
}


function main() {
   
    option="$1"
    
    case "$option" in
      --check)
            mysqlsh_validation
            firewalld_ports_validation
            ;;

      --install)
            mysqlsh_installation
            firewalld_ports_configuration
            ;;
    esac
}

main "$1"
