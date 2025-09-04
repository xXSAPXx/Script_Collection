#!/usr/bin/env python3


# Requirements:
# -------------------
#- $ python3 --version                                        /// Check Python Version 
#- $ pip3 install myloginpath                                 /// myloginpath (for reading MySQL login-path credentials)
#- $ dnf install python3-devel mariadb-connector-c-devel gcc  /// mysqlclient (MySQLdb) library and 'C' compiler    
#- $ pip3 install mysqlclient                                 /// mysqlclient (MySQLdb)     
#- $ pip3 install prometheus-client                           /// prometheus_client Module
#- $ /etc/systemd/system/mysql_processlist_exporter.service   /// Create systemd service file as needed


# Description:
# -------------------
#- MySQL Processlist Exporter with Prometheus Client: 
#- Exposes one metric: mysql_processlist_exporter_metrics
#- Labels: process_id, user, host, db, state, info (truncated), hostname
#- Uses a custom collector (GaugeMetricFamily) so metrics are rebuilt on every scrape (no manual clearing)
#- Configurable filters at the top of the file 


import time
import socket
import myloginpath
import MySQLdb
import logging
import signal
import sys
from prometheus_client import start_http_server, REGISTRY
from prometheus_client.core import GaugeMetricFamily


#______________________________________________________________________________________________________________
# Exporter Configuration Variables: 
EXPORTER_PORT = 9105                     # Custom exporter port.
LOGIN_PATH = 'local'                     # DB login-path. 
HOSTNAME = socket.gethostname()          # Fetch the hostname from the host and export it as label


# Processlist Scraping Filters: 
DATABASE_FILTER = "sbtest"              # Empty = all DBs
USER_FILTER = "admin|root"              # Regex for USER 
EXECUTION_TIME_WARNING_THRESHOLD = 10   # Secs
PROCESS_STATE_FILTER = ".*"             # Regex for STATE
INFO_TEXT_FILTER = ".*"                 # Regex for INFO
INFO_MAX_LEN = 30                       # Number of CHARS for INFO


# Metric Name & Labels:
METRIC_NAME = "mysql_processlist_exporter_metrics"
METRIC_DESC = "Runtime (seconds) of MySQL processlist entries (truncated info)"

#______________________________________________________________________________________________________________




class ProcesslistCollector(object):

    # ====== If no argument is passed to login_path if uses sys variable "LOGIN_PATH": ====== #  
    def __init__(self, login_path=LOGIN_PATH):
        self.login_path = login_path

    # ====== Every time Prometheus scrapes the endpoint this function is exected: ====== # 
    # ====== Scrape interval is managed in Prometheus yaml config, not in the exporter! ====== # 
    def collect(self): 
        """
        Called by Prometheus client when /metrics is scraped.
        We create a GaugeMetricFamily and fill it with current values.
        """
        metric = GaugeMetricFamily(
            METRIC_NAME,
            METRIC_DESC,
            labels=["process_id", "user", "host", "db", "state", "info", "hostname"],
        )

        try:
            conf = myloginpath.parse(self.login_path)
        except Exception as e:
            logging.error("Error Parsing Login Path '%s': %s", self.login_path, e)
            logging.info("MySQL Processlist Exporter Shutting Down...")
            sys.exit(0)

        conn = None
        cursor = None
        try:
            conn = MySQLdb.connect(**conf, db="information_schema")
            cursor = conn.cursor(MySQLdb.cursors.DictCursor)

            sql = """
                SELECT ID, USER, HOST, DB, STATE, TIME, INFO
                FROM performance_schema.processlist
                WHERE TIME > %s
                AND DB = %s
                AND USER REGEXP %s
                AND STATE REGEXP %s
                AND INFO REGEXP %s;
                """

            cursor.execute(
                    sql,
                    (
                        EXECUTION_TIME_WARNING_THRESHOLD,
                        DATABASE_FILTER,
                        USER_FILTER,
                        PROCESS_STATE_FILTER,
                        INFO_TEXT_FILTER,
                    ),
                )

            # Fetch Columns Metrics: 
            rows = cursor.fetchall()

            for row in rows:
                # Normalize and truncate fields: 
                id = str(row.get("ID") or "unknown")
                user = (row.get("USER") or "unknown")
                host = (row.get("HOST") or "unknown")
                db = (row.get("DB") or "unknown")
                state = (row.get("STATE") or "unknown")
                info_text = row.get("INFO") or "unknown"
                if len(info_text) > INFO_MAX_LEN:
                    info_text = info_text[:INFO_MAX_LEN] + "..."

                runtime = float(row.get("TIME") or 0.0)

                metric.add_metric(
                    [id, user, host, db, state, info_text, HOSTNAME],
                    runtime,
                )
                logging.info(
                    "Metrics Scraped: process_id=%s user=%s db=%s state=%s runtime=%s", 
                    id, user, db, state, runtime
                )
                
        except Exception as e:
            logging.error("Collecting Processlist Failed: %s", e)

        finally:
            try:
                if cursor:
                    cursor.close()
                if conn:
                    conn.close()
            except Exception:
                pass

        # Yield the metric (possibly empty)
        yield metric


# ==== Function for Journalctl Shutdown Message: ==== # 
def handle_sigterm(signum, frame):
    logging.info("MySQL Processlist Exporter Shutting Down...")
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)


# =============== MAIN SCRIPT LOGIC =============== # 

if __name__ == '__main__':

    # Start the systemd/journalctl message logger: 
    logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    )

    # Register collector and start HTTP server on the specified port: 
    REGISTRY.register(ProcesslistCollector(LOGIN_PATH))
    start_http_server(EXPORTER_PORT)
    logging.info("Custom MySQL Processlist Exporter started on :%s/metrics (hostname=%s)", EXPORTER_PORT, HOSTNAME)

    # Keep Process Alive --- # Real Collection Occurs on Prometheus Scrape! 
    while True:
        time.sleep(1) 


        