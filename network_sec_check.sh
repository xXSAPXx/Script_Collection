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
echo -e "- Root SSH Access (Cloud_VM): $(grep -Eq '^#?PermitRootLogin (no|prohibit-password)' /etc/ssh/sshd_config && grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config.d/50-cloud-init.conf && echo -e "${GREEN}Disabled${RESET}" || echo -e "${RED}Enabled - Security Risk!${RESET}")"
echo -e "- Firewall Status (firewalld): $(if [[ $FIREWALL_STATUS -eq 0 ]]; then echo "${GREEN}Active${RESET}"; else echo "${RED}Inactive${RESET} --- ${YELLOW}(Security Groups Likely Used)${RESET}"; fi)"
echo -e "- Open Ports: $(if [[ $FIREWALL_STATUS -eq 0 ]]; then echo -e $(firewall-cmd --list-ports | tr ' ' '\n' | awk '{printf "[%s]  ", $1}'); else echo -e "${RED}N/A${RESET}"; fi)"
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

# Display Kernel Network Parameters: 
echo "==================================================="
echo "Kernel Network Parameters:"
echo
echo -e "- TCP Congestion Control Algorithm:              $(sysctl -n net.ipv4.tcp_congestion_control)"
echo -e "- Network Packet Scheduler (Queue Discipline):   $(sysctl -n net.core.default_qdisc)"
echo -e "- TCP Socket Receive/Send Buffers MAX Size:      $(sysctl -n net.core.rmem_max) || $(sysctl -n net.core.wmem_max)"
echo -e "- TCP Socket Receive/Send Buffers Tuning Limit:  $(sysctl -n net.ipv4.tcp_rmem) || $(sysctl -n net.ipv4.tcp_wmem)"

echo
echo

# Display ARP Table: 
# echo "- ARP Table :"
# echo "$(ip neigh)"
