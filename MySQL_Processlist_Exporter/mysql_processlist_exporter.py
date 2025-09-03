#!/usr/bin/env python3


# Requirements:
# -------------------
#- $ python3 --version                                        /// Check Python Version 
#- $ pip3 install myloginpath                                 /// myloginpath (for reading MySQL login-path credentials)
#- $ dnf install python3-devel mariadb-connector-c-devel gcc  /// mysqlclient (MySQLdb) library and 'C' compiler    
#- $ pip3 install mysqlclient                                 /// mysqlclient (MySQLdb)     
#- $ pip3 install prometheus-client                           /// prometheus_client Module


# Description:
# -------------------
#- MySQL processlist exporter (Prometheus)
#- Exposes one metric: mysql_processlist_runtime_seconds
#- Labels: process_id, user, host, db, state, info (truncated), hostname
#- Uses a custom collector (GaugeMetricFamily) so metrics are rebuilt per scrape (no manual clearing)
#- Configurable filters at the top of the file 


import time
import socket
import myloginpath
import MySQLdb
from prometheus_client import start_http_server, REGISTRY
from prometheus_client.core import GaugeMetricFamily


#______________________________________________________________________________________________________________
# Exporter Configuration Variables: 
EXPORTER_PORT = 9105                     # Custom exporter port.
EXPORTER_SCRAPE_INTERVAL = 30            # Scrape Interval for the exporter in secs.  
LOGIN_PATH = 'local'                     # DB login-path. 
HOSTNAME = socket.gethostname()          # Fetch the hostname from the host and export it as label


# Processlist Scraping Filters: 
DATABASE_FILTER = "sbtest"              # Empty = all DBs
USER_FILTER = "admin|root"              # Regex for USER 
EXECUTION_TIME_WARNING_THRESHOLD = 10   # Secs
PROCESS_STATE_FILTER = ".*"             # Regex for STATE
INFO_TEXT_FILTER = ".*"                 # Regex for INFO
INFO_MAX_LEN = 30                       # Number of CHARS for INFO
#______________________________________________________________________________________________________________


# Metric name & labels
METRIC_NAME = "mysql_processlist_exporter_metrics"
METRIC_DESC = "Runtime (seconds) of MySQL processlist entries (truncated info)"


class ProcesslistCollector(object):
    def __init__(self, login_path=LOGIN_PATH):
        self.login_path = login_path

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
            # Could optionally expose an exporter_up metric; here we print and return empty metric.
            print(f"[collector] error parsing login path '{self.login_path}': {e}")
            yield metric
            return

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
                tid = str(row.get("ID") or "unknown")
                user = (row.get("USER") or "unknown")
                host = (row.get("HOST") or "unknown")
                db = (row.get("DB") or "unknown")
                state = (row.get("STATE") or "unknown")
                info_text = row.get("INFO") or "unknown"
                if len(info_text) > INFO_MAX_LEN:
                    info_text = info_text[:INFO_MAX_LEN] + "..."

                runtime = float(row.get("TIME") or 0.0)

                metric.add_metric(
                    [tid, user, host, db, state, info_text, HOSTNAME],
                    runtime,
                print(f"[Collector INFO] metrics collected successfully:")

                )
        except Exception as e:
            print(f"[Collector ERROR] error collecting processlist: {e}")

        finally:
            try:
                if cursor:
                    cursor.close()
                if conn:
                    conn.close()
            except Exception:
                pass

        # yield the metric (possibly empty)
        yield metric



# =============== MAIN SCRIPT LOGIC =============== # 
if __name__ == '__main__':
    # Register collector and start HTTP server on the specified port: 
    REGISTRY.register(ProcesslistCollector(LOGIN_PATH))
    start_http_server(EXPORTER_PORT)
    print(f"Custom MySQL Processlist Exporter started on :{EXPORTER_PORT}/metrics (hostname={HOSTNAME})")

    # Keep Process Alive - real collection occurs on Prometheus scrape. 
    while True:
        time.sleep(EXPORTER_SCRAPE_INTERVAL) # Scrape Interval


        