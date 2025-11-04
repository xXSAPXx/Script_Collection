#!/usr/bin/env bash


function os_validation(){
      command -v dnf >/dev/null 2>&1
        if [ $? -eq 0 ]; then
                printf '\t%b\n' "Machine Information"
                printf '%b\n' "_________________________________________________________________________"
                printf '\n%b\n' "$(hostnamectl | grep -v 'ID')"
        else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Unsupported Operating System!"
                printf '%b\n' "_________________________________________________________________________"
          exit 1
        fi
}

function check_base_os_requirements(){
        command -v sudo >/dev/null 2>&1
               if [ $? -eq 0 ]; then
                echo -ne "\r"
        else
                printf '%b\n' "_________________________________________________________________________"
                printf '\n%b\n' "[${CROSS_MARK_COLOR}] Sudo package is ${RED}NOT${ENDCOLOR} installed. You can install it with \"${LGREEN}dnf install sudo -y${ENDCOLOR}\""
                printf '%b\n' "_________________________________________________________________________"
          exit 1
        fi
}

function dnf_optimization(){

        command -v dnf >/dev/null 2>&1
        if [ $? -eq 0 ]; then
        sudo dnf install -q -y --best dnf-utils >/dev/null 2>&1

        if [[ -f /etc/dnf/dnf.conf ]]; then

                local cpu_count=0;
                local location_code=US;

                grep -q '^installonly_limit' /etc/dnf/dnf.conf && sed -i 's/^installonly_limit.*/installonly_limit=2/' /etc/dnf/dnf.conf || echo 'installonly_limit=2' >> /etc/dnf/dnf.conf
                grep -q '^fastestmirror' /etc/dnf/dnf.conf && sed -i 's/^fastestmirror.*/fastestmirror=False/' /etc/dnf/dnf.conf || echo 'fastestmirror=False' >> /etc/dnf/dnf.conf
                grep -q '^deltarpm' /etc/dnf/dnf.conf && sed -i 's/^deltarpm.*/deltarpm=False/' /etc/dnf/dnf.conf || echo 'deltarpm=False' >> /etc/dnf/dnf.conf
                grep -q '^zchunk' /etc/dnf/dnf.conf && sed -i 's/^zchunk.*/zchunk=0/' /etc/dnf/dnf.conf || echo 'zchunk=0' >> /etc/dnf/dnf.conf
                grep -q '^bandwidth' /etc/dnf/dnf.conf && sed -i 's/^bandwidth.*/bandwidth=1M/' /etc/dnf/dnf.conf || echo 'bandwidth=1M' >> /etc/dnf/dnf.conf
                grep -q '^metadata_timer_sync' /etc/dnf/dnf.conf && sed -i 's/^metadata_timer_sync.*/metadata_timer_sync=3600/' /etc/dnf/dnf.conf || echo 'metadata_timer_sync=3600' >> /etc/dnf/dnf.conf

                if [ $(nproc --all) -ge 6 ]; then
                        cpu_count=5
                else
                        cpu_count=1
                fi

                grep -q '^max_parallel_downloads' /etc/dnf/dnf.conf && sed -i 's/^max_parallel_downloads.*/max_parallel_downloads='${cpu_count}'/' /etc/dnf/dnf.conf || echo 'max_parallel_downloads='${cpu_count}'' >> /etc/dnf/dnf.conf


                location_code=$(curl -s https://ipinfo.io/country)
                grep -q '^country' /etc/dnf/dnf.conf && sed -i 's/^country.*/country='${location_code}'/' /etc/dnf/dnf.conf || echo 'country='${location_code}'' >> /etc/dnf/dnf.conf


                printf '\t%b\n' "[${CHECK_MARK_COLOR}] DNF configuration was successfully installed."
        else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] The dnf.conf does not exist!"
        fi
        else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Unsupported Operating System!"
                printf '%b\n' "_____________________________________________________________________"
                exit 1
        fi____
}

function check_dnf_optimization(){

        if [[ $(awk -F'=' '/installonly_limit/{print $2}' /etc/dnf/dnf.conf) == 3 && $(wc -l /etc/dnf/dnf.conf | awk '{print $1}') == 7 ]]; then
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] DNF is using default configuration."
        else
                printf '\t%b\n' "[${INFO_MARK_COLOR}] DNF is using custom configuration."
        fi

}


function percona_repo_validation(){
    check=$(rpm -q --all --queryformat '%{NAME}\n' "percona-release")
    if [[ -z "$check" ]]; then
            printf '\t%b\n' "[${CROSS_MARK_COLOR}] Percona Repository is missing."
            sudo dnf install -q -y https://repo.percona.com/yum/percona-release-latest.noarch.rpm >/dev/null 2>&1
            sudo percona-release disable all -y >/dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        sudo percona-release enable ps-80 release -y >/dev/null 2>&1
                        sudo percona-release enable pxb-80 release -y >/dev/null 2>&1
                        sudo percona-release enable prel release -y >/dev/null 2>&1
                        sudo percona-release enable pmm2-clent release -y >/dev/null 2>&1
                        sudo percona-release enable pt release -y >/dev/null 2>&1
                        printf '\t%b\n' "[${CHECK_MARK_COLOR}] The package ${GREEN}percona-release${ENDCOLOR} was successfully installed."
                        else
                        printf '\t%b\n' "[${CROSS_MARK_COLOR}] The package ${RED}percona-release${ENDCOLOR} installation failed."
                        exit 1
                        fi
            else
            sudo percona-release enable ps-80 release -y >/dev/null 2>&1
            sudo percona-release enable pxb-80 release -y >/dev/null 2>&1
            sudo percona-release enable prel release -y >/dev/null 2>&1
            sudo percona-release enable pmm2-client release -y >/dev/null 2>&1
            sudo percona-release enable pt release -y >/dev/null 2>&1
            printf '\t%b\n' "[${CHECK_MARK_COLOR}] Percona Repository is installed and enabled."
    fi
}




function exporter_repo_validation(){
    check=$(dnf repolist enabled | awk '/prometheus-rpm/{print $1}')
        if [[ -z "$check" ]]; then
            printf '\t%b\n' "[${CROSS_MARK_COLOR}] Node Exporter Repository is missing."
cat <<EOT > /etc/yum.repos.d/prometheus-rhel.repo
[prometheus-rpm_release]
name=prometheus-rpm_release
baseurl=https://packagecloud.io/prometheus-rpm/release/el/\$releasever/\$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/prometheus-rpm/release/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOT
                    if [ $? -eq 0 ]; then
                        printf '\t%b\n' "[${CHECK_MARK_COLOR}] The Node Exporter Repository was successfully installed."
                        else
                        printf '\t%b\n' "[${CROSS_MARK_COLOR}] The Node Exporter Repository installation failed."
                        exit 1
                        fi
            else
            sudo dnf config-manager --set-enabled prometheus-rpm_release
            printf '\t%b\n' "[${CHECK_MARK_COLOR}] Node Exporter Repository is installed and enabled."
    fi

}




function disable_selinux(){
       local action="read"
       local selinux_status=""

        action="$1"
        selinux_status=$(getenforce)
   if [ "$action" == "read" ]; then
         if [ "$selinux_status" != "Disabled" ] ; then
           printf '\t%b\n' "[${INFO_MARK_COLOR}] SELinux is ${RED}NOT${ENDCOLOR} disabled."
   else
           printf '\t%b\n' "[${INFO_MARK_COLOR}] SELinux is disabled."
         fi
else
   if [ "$selinux_status" != "Disabled" ]; then
           sudo setenforce 0 >/dev/null 2>&1
           sudo grubby --update-kernel ALL --args selinux=0 >/dev/null 2>&1
           printf '\t%b\n' "[${INFO_MARK_COLOR}] SELinux has been disabled successfully."
   else
           printf '\t%b\n' "[${INFO_MARK_COLOR}] SELinux is disabled."
   fi
fi
}

function disable_anon_thp(){
	thp_status=$(awk '/nr_anon_transparent_hugepages/{print $NF}' /proc/vmstat)
   if [ "$thp_status" -ne 0 ]; then
           [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]] && echo never > /sys/kernel/mm/transparent_hugepage/enabled
           [[ -f /sys/kernel/mm/transparent_hugepage/defrag  ]] && echo never > /sys/kernel/mm/transparent_hugepage/defrag
           sudo grubby --update-kernel ALL --args transparent_hugepage=never >/dev/null 2>&1
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Transparent Hugepages have been disabled successfully."
   else
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Transparent Hugepages are disabled."
   fi
}

function validate_sar_collection(){
        if [[ -f /usr/lib/systemd/system/sysstat-collect.timer ]]; then
		sar_status=$(grep ^OnCalendar /usr/lib/systemd/system/sysstat-collect.timer | grep 01$)
                [[ -n  ${sar_status} ]] && printf '\t%b\n' "[${INFO_MARK_COLOR}] SAR collection interval is 1 minute." || printf '\t%b\n' "[${CROSS_MARK_COLOR}] SAR collection interval is ${RED}NOT${ENDCOLOR} 1 minute."
        else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] SAR is not installed."
        fi

}

function change_sar_collection(){
        [[ -f /usr/lib/systemd/system/sysstat-collect.timer ]] && sudo sed -i 's|00/10|00/01|g' /usr/lib/systemd/system/sysstat-collect.timer
        sudo systemctl daemon-reload
        printf '\t%b\n' "[${INFO_MARK_COLOR}] Set collection interval of SAR data(1 minute)."
}


function set_mysql_os_limits(){
cat <<EOT > /etc/security/limits.d/20-mysql.conf
mysql soft nofile 10240
mysql hard nofile 40960
mysql soft nproc  10240
mysql hard nproc  40960
mysql soft memlock unlimited
mysql hard memlock unlimited
EOT
        printf '\t%b\n' "[${INFO_MARK_COLOR}] Set OS limits for MySQL user."
}

function chg_tcp_cong_ctrl(){
cat <<EOT > /etc/sysctl.d/10-custom-kernel-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_notsent_lowat=262144
EOT
sysctl -p /etc/sysctl.d/10-custom-kernel-bbr.conf >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                printf '\t%b\n' "[${INFO_MARK_COLOR}] Change TCP Congestion control."
            else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Change TCP Congestion control failed."
            fi

}

function chg_tcp_socket_buffers(){
cat <<EOT > /etc/sysctl.d/10-tcp-socket-buffers.conf
net.ipv4.tcp_rmem = 4096 873814 8738140
net.ipv4.tcp_wmem = 4096 873814 8738140
net.core.rmem_max = 8738140
net.core.wmem_max = 8738140
# Increase number of incoming connections backlog
net.core.netdev_max_backlog = 8192
net.ipv4.tcp_max_syn_backlog = 4096
EOT
sysctl -p /etc/sysctl.d/10-tcp-socket-buffers.conf >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                printf '\t%b\n' "[${INFO_MARK_COLOR}] Change TCP Socket Buffers."
            else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Change TCP Socket Buffers failed."
            fi
}

function chg_net_keepalive(){
cat <<EOT > /etc/sysctl.d/50-net-keepalive.conf
net.ipv4.tcp_keepalive_time = 300     # 5 minutes
net.ipv4.tcp_keepalive_intvl = 60     # 1 minute
net.ipv4.tcp_keepalive_probes = 5
EOT
sysctl -p /etc/sysctl.d/50-net-keepalive.conf >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                printf '\t%b\n' "[${INFO_MARK_COLOR}] Change Network KeepAlive."
            else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Change Network KeepAlive failed."
            fi
}

function chg_aio_max_nr(){
       local action="read"
       local aio_max_status=""

        action="$1"
   if [ "$action" == "read" ]; then
	   aio_max_status=$(awk '{print $NF}' /proc/sys/fs/aio-max-nr)
                 if [ "$aio_max_status" == 1048576 ] ; then
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Minimum Number of Asynchronous requests are configured."
   else
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Minimum Number of Asynchronous requests are ${RED}NOT${ENDCOLOR} configured."
         fi
else
cat <<EOT > /etc/sysctl.d/60-aio-max-nr.conf
fs.aio-max-nr = 1048576
EOT
sysctl -p /etc/sysctl.d/60-aio-max-nr.conf >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                printf '\t%b\n' "[${INFO_MARK_COLOR}] Change Maximum Number of Asynchronous requests."
            else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Change Maximum Number of Asynchronous requests failed."
            fi
   fi
}

function number_free_kbytes_validation(){
        local total_mem=0
        local mfk_status=""

        total_mem=$(awk -F' ' '/^MemTotal/{print $2}' /proc/meminfo)
        mfk_status=$(awk '{print $NF}' /proc/sys/vm/min_free_kbytes)

        if [ "$total_mem" -ge 16111652 ]; then
                 if [ "$mfk_status" == 1048576 ] ; then
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Minimum Number of Free kilobytes are configured."
                 else
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Minimum Number of Free kilobytes are ${RED}NOT${ENDCOLOR} configured."
                 fi
        else
                 if [ "$mfk_status" == 131072 ] ; then
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Minimum Number of Free kilobytes are configured."
                 else
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Minimum Number of Free kilobytes are ${RED}NOT${ENDCOLOR} configured."
                 fi
        fi
}

function chg_number_free_kbytes(){
        local total_mem=0

        total_mem=$(awk -F' ' '/^MemTotal/{print $2}' /proc/meminfo)

        if [ "$total_mem" -ge 16111652 ]; then
cat <<EOT > /etc/sysctl.d/60-min-free-kb.conf
vm.min_free_kbytes = 1048576
EOT
       else
cat <<EOT > /etc/sysctl.d/60-min-free-kb.conf
vm.min_free_kbytes = 131072
EOT
        fi

        sysctl -p /etc/sysctl.d/60-min-free-kb.conf >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                printf '\t%b\n' "[${INFO_MARK_COLOR}] Change Minimum Number of Free kilobytes."
            else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Change Minimum Number of Free kilobytes failed."
            fi
}

function enable_delay_accounting(){
       local action="read"
       local da_status=""

        action="$1"
   if [ "$action" == "read" ]; then
	   da_status=$(awk '{print $NF}' /proc/sys/kernel/task_delayacct)
                 if [ "$da_status" -eq 1 ] ; then
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Delay Accounting is enabled.(Required by iotop)"
   else
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Delay Accounting is ${RED}NOT${ENDCOLOR} enabled.(Required by iotop)"
         fi
else
cat <<EOT > /etc/sysctl.d/70-delayacct.conf
kernel.task_delayacct = 1
EOT
sysctl -p /etc/sysctl.d/70-delayacct.conf >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] Enable Delay Accounting.(Required by iotop)"
            else
                    printf '\t%b\n' "[${CROSS_MARK_COLOR}] Enable Delay Accounting failed.(Required by iotop)"
            fi
fi
}

function chg_vm_dirty_ratio(){
cat <<EOT > /etc/sysctl.d/70-vm-dirty.conf
vm.dirty_expire_centisecs=500
vm.dirty_writeback_centisecs=100
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 134217728
EOT
sysctl -p /etc/sysctl.d/70-vm-dirty.conf >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] Change VM Dirty Ratio to improve disk cache performance."
            else
                    printf '\t%b\n' "[${CROSS_MARK_COLOR}] Change VM Dirty Ratio to improve disk cache performance failed."
            fi

}

function chg_vm_swappiness(){
        local action="read"
        local swp_status=""

        action="$1"
	swp_status=$(awk '{print $NF}' /proc/sys/vm/swappiness)
   if [ "$action" == "read" ]; then
                 if [ "$swp_status" -eq 1 ] ; then
           printf '\t%b\n' "[${INFO_MARK_COLOR}] VM Swappiness is 1."
   else
           printf '\t%b\n' "[${INFO_MARK_COLOR}] VM Swappiness is ${RED}NOT${ENDCOLOR} configured."
         fi
else
cat <<EOT > /etc/sysctl.d/80-swappiness.conf
vm.swappiness = 1
EOT
sysctl -p /etc/sysctl.d/80-swappiness.conf >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] Change VM Swappiness to 1."
            else
                    printf '\t%b\n' "[${CROSS_MARK_COLOR}] Change VM Swappiness failed."
            fi
fi
}

function enable_hugepages(){
        local action="read"
        local hp_status=""

        action="$1"
	hp_status=$(awk '{print $NF}' /proc/sys/vm/nr_hugepages)
   if [ "$action" == "read" ]; then
         if [ "$hp_status" -ne 0 ] ; then
                 printf '\t%b\n' "[${INFO_MARK_COLOR}] Hugepages are enabled - ${LGREEN}$(( 10#$hp_status / 512 ))G${ENDCOLOR} "
   else
           printf '\t%b\n' "[${INFO_MARK_COLOR}] Hugepages are ${RED}NOT${ENDCOLOR} enabled."
         fi
else
   if [ "$hp_status" -ne 0 ] ; then
                 printf '\t%b\n' "[${INFO_MARK_COLOR}] Hugepages are enabled - ${LGREEN}$(( 10#$hp_status / 512 ))G${ENDCOLOR} "
   else
           if [[ -f /etc/sysctl.d/80-hugepages.conf ]]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] A Hugepage configuration file already exists. Enable them manually if required."
            else
cat <<EOT > /etc/sysctl.d/80-hugepages.conf
#vm.nr_hugepages = 70656  # 138G
#vm.nr_hugepages = 104800 # 204G
vm.nr_hugepages = 0
vm.hugetlb_shm_group = 27
EOT
sysctl -p /etc/sysctl.d/80-hugepages.conf >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] Number of Hugepages must be enabled manually. Only MySQL GroupID has been set."
            else
                    printf '\t%b\n' "[${CROSS_MARK_COLOR}] Number of Hugepages must be enabled manually. MySQL GroupID has NOT been set."
            fi
           fi
   fi
   fi
}

function enable_disk_parameters(){
        if [[ -f /etc/udev/rules.d/90-read-ahead.rules ]]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] Udev Rules are already applied on MySQL disk."
            else

cat <<EOT > /etc/udev/rules.d/90-read-ahead.rules
# increase readahead for sd* devices
SUBSYSTEM=="block", ACTION=="add|change", KERNEL=="sd[a-z]", ENV{ID_SERIAL_SHORT}=="mysql", ATTR{queue/scheduler}="mq-deadline", ATTR{queue/iosched/front_merges}="0", ATTR{queue/iosched/read_expire}="1000", ATTR{queue/iosched/write_expire}="1000", ATTR{queue/iosched/writes_starved}="1", ATTR{bdi/read_ahead_kb}="4096", ATTR{queue/rotational}="0", ATTR{queue/rq_affinity}="0", ATTR{queue/nr_requests}="2048"
EOT
            if [ $? -eq 0 ]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] Udev Rules are enabled successfully for MySQL disk."
            else
                    printf '\t%b\n' "[${CROSS_MARK_COLOR}] Failed to enable Udev Rules for MySQL disk."
            fi
        fi

}

function enable_mysql_jemalloc(){
	if [[ -f /etc/sysconfig/mysql ]]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] Jemalloc is already enabled for MySQL database."
            else

cat <<EOT > /etc/sysconfig/mysql
LD_PRELOAD="/usr/lib64/libjemalloc.so.2"
EOT
            if [ $? -eq 0 ]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] Jemalloc is enabled successfully for MySQL database."
            else
                    printf '\t%b\n' "[${CROSS_MARK_COLOR}] Failed to enable Jemalloc for MySQL database."
            fi
	fi

}

function mount_point_validation(){
        check=$(grep -qs "/var/lib/mysql" /proc/mounts)
            if [ $? -eq 0 ]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] MySQL filesystem is mounted.(/var/lib/mysql)"
            else
                    printf '\t%b\n' "[${CROSS_MARK_COLOR}] MySQL filesystem is NOT mounted.(/var/lib/mysql)"
            fi
}

function dnf_auto_update_validation(){
            check=$(systemctl list-units --type timer | grep "dnf-automatic")
            if [ $? -ne 0 ]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] DNF Automatic updates are disabled."
            else
                    printf '\t%b\n' "[${CROSS_MARK_COLOR}] DNF Automatic updates are enabled."
            fi
}

function dnf_auto_update_disable(){
            check=$(systemctl list-units --type timer | grep "dnf-automatic")
            if [[ -z "$check" ]]; then
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] DNF Automatic updates are disabled."
            else
                    sudo systemctl stop dnf-automatic.timer && sudo systemctl disable dnf-automatic.timer >/dev/null 2>&1
                    printf '\t%b\n' "[${INFO_MARK_COLOR}] DNF Automatic updates are disabled successfully."
            fi
}

function avail_percona_versions(){
            printf '%b\n\n' "[${INFO_MARK_COLOR}] The following Percona MySQL versions are available for manual installation:"
            dnf -q list --available --showduplicates percona-server-server | awk '!/Packages/{print "dnf install " "percona-server-server-" $2 " percona-icu-data-files-" $2 " percona-server-client-" $2 " percona-server-shared-" $2 }'
            printf '\n%b\n\n' "Or you can install the latest version with \"${LGREEN}dnf install percona-server-server${ENDCOLOR}\""
}

function avail_xtrabackup_versions(){
            printf '%b\n\n' "[${INFO_MARK_COLOR}] The following Percona XtraBackup versions are available for manual installation:"
            dnf -q list --available --showduplicates percona-xtrabackup-80 | awk '!/Packages/{print "dnf install " "percona-xtrabackup-80-" $2 }'
            printf '\n%b\n\n' "Or you can install the latest version with \"${LGREEN}dnf install percona-xtrabackup-80${ENDCOLOR}\""
}

function dolphie_validation(){
      command -v dolphie >/dev/null 2>&1
        if [ $? -eq 0 ]; then
		printf '\t%b\n' "[${INFO_MARK_COLOR}] Dolphie ${LGREEN}$(dolphie -V)${ENDCOLOR} is installed."
        else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Dolphie for MySQL is not installed."
		command -v pip >/dev/null 2>&1
        if [ $? -eq 0 ]; then
                printf '\t%b\n' "[${INFO_MARK_COLOR}] You can install Dolphie manually with \"${LGREEN}python -m pip install -U dolphie${ENDCOLOR}\""
	else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Python PIP is not installed."
	fi
        fi
}

function dolphie_installation(){
      command -v dolphie >/dev/null 2>&1
        if [ $? -eq 0 ]; then
                printf '\t%b\n' "[${INFO_MARK_COLOR}] Dolphie ${LGREEN}$(dolphie -V)${ENDCOLOR} is installed."
        else
                command -v pip >/dev/null 2>&1
        if [ $? -eq 0 ]; then

                sudo python -m pip install -U pip --quiet >/dev/null 2>&1
                sudo python -m pip install -U dolphie --quiet >/dev/null 2>&1
		printf '\t%b\n' "[${CHECK_MARK_COLOR}] Dolphie ${LGREEN}$(dolphie -V)${ENDCOLOR} is installed successfully."
        else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Python PIP is not installed."
        fi
        fi
}

function update_additional_tools(){

        command -v pip >/dev/null 2>&1
        if [ $? -eq 0 ]; then

                sudo python -m pip install -U pip --quiet >/dev/null 2>&1
                sudo python -m pip install -U dolphie --quiet >/dev/null 2>&1
                printf '\t%b\n' "[${CHECK_MARK_COLOR}] Additional MySQL tools were updated successfully."
        else
                printf '\t%b\n' "[${CROSS_MARK_COLOR}] Python PIP is not installed."
        fi
}



function create_bash_profile(){

cat <<EOT > /etc/profile.d/bash_profile.sh
if [ \$(id -u) -eq 0 ];
then

        command -v bat >/dev/null 2>&1 && { alias cat='bat -pp'; }
        command -v zoxide >/dev/null 2>&1 && { eval "\$(zoxide init --cmd cd bash)"; }

env_type=\$(hostname -s | awk -F"-" '{print \$(NF-1)}')

case "\$env_type" in
      dev)
        export PS1="\[\e[1;32m\][\[\e[1;31m\]\u\[\e[1;32m\]@\h:\[\e[0;39m\] \w\[\e[1;32m\]]#\[\e[0m\] "
             ;;
      test)
        export PS1="\[\e[1;34m\][\[\e[1;31m\]\u\[\e[1;34m\]@\h:\[\e[0;39m\] \w\[\e[1;34m\]]#\[\e[0m\] "
             ;;
      stg)
        export PS1="\[\e[1;96m\][\[\e[1;31m\]\u\[\e[1;96m\]@\h:\[\e[0;39m\] \w\[\e[1;96m\]]#\[\e[0m\] "
             ;;
      prod)
	rpl_env_type=\$(hostname -s | awk -F"-" '{print \$(NF)}')
		case "\$rpl_env_type" in
			rpl??)
				export PS1="\[\e[0;33m\][\[\e[0;31m\]\u\[\e[0;33m\]@\h:\[\e[0;39m\] \w\[\e[0;33m\]]#\[\e[0m\] "
				;;
			*)
				export PS1="\[\e[0;31m\][\[\e[1;31m\]\u\[\e[1;31m\]@\h:\[\e[0;39m\] \w\[\e[0;31m\]]#\[\e[0m\] "
				;;
		esac
		;;
      tms)
        tms_env_type=\$(hostname -s | awk -F"-" '{print \$(NF)}')
                case "\$tms_env_type" in
			dev)
				export PS1="\[\e[1;32m\][\[\e[1;31m\]\u\[\e[1;32m\]@\h:\[\e[0;39m\] \w\[\e[1;32m\]]#\[\e[0m\] "
				;;
			test)
				export PS1="\[\e[1;34m\][\[\e[1;31m\]\u\[\e[1;34m\]@\h:\[\e[0;39m\] \w\[\e[1;34m\]]#\[\e[0m\] "
				;;
			stg)
				export PS1="\[\e[1;96m\][\[\e[1;31m\]\u\[\e[1;96m\]@\h:\[\e[0;39m\] \w\[\e[1;96m\]]#\[\e[0m\] "
				;;
			prod)
				export PS1="\[\e[0;31m\][\[\e[1;31m\]\u\[\e[1;31m\]@\h:\[\e[0;39m\] \w\[\e[0;31m\]]#\[\e[0m\] "
				;;
		esac
		;;
     *)
        export PS1="\[\e[1;32m\][\[\e[1;31m\]\u\[\e[1;32m\]@\h:\[\e[0;39m\] \w\[\e[1;32m\]]#\[\e[0m\] "
      return 1
      ;;
esac
fi
EOT
printf '\t%b\n' "[${INFO_MARK_COLOR}] Custom Bash profiles was created."
}

