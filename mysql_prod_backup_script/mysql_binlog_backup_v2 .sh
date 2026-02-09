#!/bin/env bash

set -euo pipefail

# The script is used to backup MySQL binlog files to Google Cloud Storage: 
# The script is intended to be run as a cron job every 15-30 minutes.
# It writes binlog backup metrics in /node_exporter/textfile_collector/ to be scraped by Prometheus.


# =================================================================================================================================
# It needs check all MySQL logs active on the DB "SHOW BINARY LOGS"
# It needs to FLUSH LOGS; to create a new log file and avoid coping the currently active DB binlog file, which can be written to during the backup process.
# All binlog files checked by the SHOW BINARY LOGS commmand earlier need to be copied to GCS bucket.
# They shound look like this in the bucket: gs://delasport-mysql-backup/binlogs_backup/2024-06-01/mysql-bin.000001, mysql-bin.000002, etc.
# Then on the following day gs://delasport-mysql-backup/binlogs_backup/2024-06-02/mysql-bin.000003, mysql-bin.000004, etc.  
# I think the GCP bucket can handle duplicate names like a failsafe BUT ALSO: 
# The script needs to track the last backup log file, to avoid backup the same log file twice.
# =================================================================================================================================


# Colors for output:
WHITE="\e[1m"
GREEN="\e[32m"
CYAN="\e[36m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

DATA_DIR="/var/lib/mysql"
GCP_BINARY_PATH=$(which gcloud) || { echo -e "${RED}Error: gcloud CLI is not installed or not in PATH. Please install Google Cloud SDK.${RESET}"; }
GCS_BUCKET="gs://delasport-mysql-backup/binlogs_backup"
TEXTFILE_COLLECTOR_DIR="/var/lib/node_exporter/textfile_collector/"
BACKUP_TIMESTAMP=$(($(date +%s) * 1000))

# Function to check if machine host is (src) or (rpl):
check_host(){

        rpl_env_type=`hostname -s | awk -F"-" '{print $(NF)}'`
          case "$rpl_env_type" in
                  rpl??|src)
                          SERVER_NAME=$(hostname -s)
                          ;;
                  *)
                          SERVER_NAME=$(hostname -s | cut -d"-" -f1-4)
                          ;;              
          esac
}

mysql_binlog_backup(){

BINLOG_LIST=$(cat /var/lib/mysql/mysql-bin.index | grep -E "mysql-bin.[0-9]+$" | awk -F "/" '{print $NF}')
BINLOG_LIST=(mysql --login-path=local -e "SHOW BINARY LOGS;" | awk 'NR>1 {print $1}')
}








# Function to save BINLOG_BACKUP monitoring metrics in case of SUCCESS:
save_binlog_backup_metrics_success() {
    # Add Success Binlog_Backup Stats to Node_Exporter file: 
    printf "node_mysql_binlog_backup_status{instance=\"$SERVER_NAME\"} 0\n" > "$TEXTFILE_COLLECTOR_DIR/mysql_binlog_backup_status.prom.$$"
    printf "node_mysql_binlog_backup_duration_seconds{instance=\"$SERVER_NAME\"} $DURATION_BINLOG_BACKUP\n" >> "$TEXTFILE_COLLECTOR_DIR/mysql_binlog_backup_status.prom.$$"
    printf "node_mysql_last_successful_binlog_backup_date{instance=\"$SERVER_NAME\"} $BACKUP_TIMESTAMP\n" > "$TEXTFILE_COLLECTOR_DIR/mysql_binlog_backup_age.prom"
    
    # Rename the temporary file atomically.
    # This avoids the node exporter seeing half a file.
    mv "$TEXTFILE_COLLECTOR_DIR/mysql_binlog_backup_status.prom.$$" \
       "$TEXTFILE_COLLECTOR_DIR/mysql_binlog_backup_status.prom"
}


# Function to save BINLOG_BACKUP monitoring metrics in case of FAILURE:
save_binlog_backup_metrics_failure() {
    printf "node_mysql_binlog_backup_status{instance=\"$SERVER_NAME\"} 1\n" > "$TEXTFILE_COLLECTOR_DIR/mysql_binlog_backup_status.prom.$$"
    printf "node_mysql_binlog_backup_duration_seconds{instance=\"$SERVER_NAME\"} 1\n" >> "$TEXTFILE_COLLECTOR_DIR/mysql_binlog_backup_status.prom.$$"

    # Rename the temporary file atomically.
    # This avoids the node exporter seeing half a file.
    mv "$TEXTFILE_COLLECTOR_DIR/mysql_binlog_backup_status.prom.$$" \
       "$TEXTFILE_COLLECTOR_DIR/mysql_binlog_backup_status.prom"
}

