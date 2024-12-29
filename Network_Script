#!/bin/bash
set -uo pipefail

# Colors for output:
GREEN="\e[32m"
LGREEN="\e[92m"
BLUE="\e[34m"
LBLUE="\e[94m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"


# Inform the user that the script is running:
echo
echo -e "╰┈➤   ${YELLOW}Loading Information. Please wait... 🔧${RESET} - [${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${RESET}]"
echo


# Test connectivity to a specific host (Google's DNS: 8.8.8.8)
ping -c 4 8.8.8.8 > /dev/null
CONNECTION_STATUS=$?

# Test Firewall Status: 
command -v systemctl &>/dev/null && systemctl is-active firewalld > /dev/null
FIREWALL_STATUS=$?

# Test SELinux Status: 
SELINUX_STATUS=$(getenforce)



# Display summary of network status:
echo "==================================================="
echo "System Network Status:"
echo
echo -e "- Connectivity: $(if [[ $CONNECTION_STATUS -eq 0 ]]; then echo "${GREEN}Successful${RESET}"; else echo "${RED}Failed${RESET}"; fi)"
echo "- Interfaces: $(ip link | grep UP | awk '{print $2}' | paste -sd ' , ' -)"
echo "- Internal IP Address: $(ip -4 addr show | awk '/inet / && $2 !~ /^127/ {print $2}' | paste -sd ', ' -)"
echo "- External IP Address: $(curl -s ifconfig.me)"
echo "- Default Gateway:     $(ip route | awk '/default/ {print $3}')"
echo "- Public DNS Servers:  $(nslookup -type=NS google.com | awk '/Server:/ {print $2}')"
echo

# Display Network and Security Information:
echo "==================================================="
echo "Network and Security Information:"
echo
echo -e "- SELinux Status: $(if [[ $SELINUX_STATUS == "Enforcing" ]]; then echo "${GREEN}Enforcing${RESET}"; elif [[ $SELINUX_STATUS == "Permissive" ]]; then echo "${YELLOW}Permissive${RESET}"; else echo "${RED}Disabled${RESET}"; fi)"
echo -e "- Firewall Status (firewalld): $(if [[ $FIREWALL_STATUS -eq 0 ]]; then echo "${GREEN}Active${RESET}"; else echo "${RED}Inactive${RESET} --- ${YELLOW}(Security Groups Likely Used)${RESET}"; fi)"
echo -e "- Open Ports: $(if [[ $FIREWALL_STATUS -eq 0 ]]; then echo -e $(firewall-cmd --list-ports | tr ' ' '\n' | awk '{printf "[%s]  ", $1}'); else echo -e "${RED}N/A${RESET}"; fi)"
echo -e "- OpenSSH Version: $(ssh -V 2>&1 | cut -d' ' -f1-2)"
echo

# Display Listening Services and Ports: 
echo "==================================================="
echo -e "Listening Services: State [${LBLUE}LISTENING${RESET}]"
echo
echo -e "- Service Ports in Use: $(ss -tunlp | awk '/LISTEN/ && $5 ~ /:/ {split($5, a, ":"); print a[2]}' | sort -n | uniq | awk 'NF {printf "[%s] ", $0}')"
echo  
echo -e "$(ss -tunlp | awk '/LISTEN/ {
    split($7, service_info, "=");
    pid = service_info[2];
    sub(/[),].*/, "", pid);
    cmd = "ps -o user= -p " pid;
    cmd | getline user;
    close(cmd);
    print "  Service:", $7, "|| Port:", substr($5, match($5, /[^:]*$/)), "|| Protocol:", $1, "|| User:", user }' | column -t)"
    
echo 

# Display Established Services and Ports: 
echo "==================================================="
echo -e "Active Connections: State [${LBLUE}ESTABLISHED${RESET}]"
echo
echo -e "$(ss -tunlpa | awk '/ESTAB / { 
    split($7, service_info, "=");
    pid = service_info[2];
    sub(/[),].*/, "", pid);
    cmd = "ps -o user= -p " pid;
    cmd | getline user;
    close(cmd);
    print "  Service:", $7, "|| Port:", substr($5, match($5, /[^:]*$/)), "|| Protocol:", $1, "|| User:", user }' | column -t)"

echo
echo


# Display ARP Table: 
# echo "- ARP Table :"
# echo "$(ip neigh)"

