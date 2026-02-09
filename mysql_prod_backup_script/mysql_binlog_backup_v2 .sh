#!/bin/env bash

# The script will be used to backup MySQL binlog files to Google Cloud Storage.
# It needs check all MySQL logs active on the DB "SHOW BINARY LOGS"
# It needs to FLUSH LOGS; to create a new log file and avoid coping the currently active DB binlog file, which can be written to during the backup process.
# All binlog files checked by the SHOW BINARY LOGS commmand earlier need to be copied to GCS bucket.
# They shound look like this in the bucket: gs://delasport-mysql-backup/binlogs_backup/2024-06-01/mysql-bin.000001, mysql-bin.000002, etc.

# I think the GCP bucket can handle duplicate names like a failsafe part2 BUT ALSO: 
# The script needs to track the last backup log file, to avoid backup the same log file twice.

# It needs to write a metrics in /node_exporter/textfile_collector/mysql_binlog_backup.prom with the last backup log file name and the last succesfull backup age, to be scraped by Prometheus.
# The script is intended to be run as a cron job every 15-30 minutes.
