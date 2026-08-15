#!/usr/bin/env python3


# Requirements:
# -------------------
#- $ python3 --version                  /// Check Python Version
#- $ pip3 install myloginpath           /// myloginpath (for reading MySQL login-path credentials)
#- $ pip3 install PyMySQL               /// PyMySQL - pure Python MySQL driver, no gcc / C headers required
#- The 'mysql' CLI client must be on PATH - used via subprocess to dump raw, unformatted evidence output during a LAGGING episode


# Description:
# -------------------
#- Connects locally to a MySQL 8.4 replica (via login-path / local socket) and continuously polls replication lag.
#- While lag stays below the threshold, appends a one-line heartbeat to the log.
#- When lag crosses the threshold, switches into LAGGING state:
#-   - captures a full evidence snapshot (replica status, per-worker applier state, InnoDB transactions,
#-     metadata locks, data lock waits, processlist) immediately, and again every HEAVY_EVIDENCE_INTERVAL_SECONDS
#-     while lag remains high.
#-   - between heavy snapshots, logs a lightweight per-poll line with a worker state breakdown
#-     (idle / applying / waiting on lock / waiting on commit order) to show a stall cascading across workers.
#- When lag drops back below the threshold, captures one final RECOVERED evidence snapshot.
#- Everything is appended to a single timestamped log file.


# Deployment (Rocky Linux 9.x, run as root - matches the 'local' login-path owner):
# -------------------
#- 1. Confirm Python/pip:                       $ python3 --version   /// $ python3 -m pip --version || sudo dnf install -y python3-pip
#- 2. Install dependencies:                     $ sudo python3 -m pip install myloginpath PyMySQL
#-    (pure Python - no gcc / python3-devel / mariadb-connector-c-devel needed)
#- 3. Confirm the mysql CLI exists:             $ which mysql   /// if missing: $ sudo dnf install -y mysql
#- 4. Confirm the login-path:                   $ sudo mysql_config_editor print --all   /// expect a 'local' entry
#- 5. Copy the script:                          $ sudo mkdir -p /opt/mysql_replication_lag_investigation_script
#-                                              $ sudo cp mysql_check_replication_lag.py /opt/mysql_replication_lag_investigation_script/
#- 6. Test manually before wiring up systemd:
#-                                              $ cd /opt/mysql_replication_lag_investigation_script && sudo python3 mysql_check_replication_lag.py
#-
#-    Confirm OK lines appear on screen and in mysql_replication_lag_investigation.log, then Ctrl+C and confirm the
#-    "Stopping replication lag monitor" line appears. Also sanity-check: $ mysql --login-path=local -t -e "SELECT 1"
#-
#- 7. Install the systemd unit:                 $ sudo cp mysql_replication_lag.service.example /etc/systemd/system/mysql_replication_lag.service
#-                                              $ sudo systemctl daemon-reload
#-                                              $ sudo systemctl enable --now mysql_replication_lag.service
#- 8. Verify it's running:                      $ systemctl status mysql_replication_lag.service
#-                                              $ journalctl -u mysql_replication_lag.service -f
#-                                              $ tail -f /opt/mysql_replication_lag_investigation_script/mysql_replication_lag_investigation.log
#- 9. Install log rotation (caps the log at ~50MB - 10MB x 5 files, compressed):
#-                                              $ sudo cp mysql_replication_lag.logrotate.example /etc/logrotate.d/mysql_replication_lag
#-    logrotate itself runs automatically on Rocky (daily cron/timer) - no extra scheduling needed.
#- 10. Repeat on each replica.
#- SELinux (enforcing by default on Rocky): generic systemd units usually run unconfined, but if the service fails
#-    silently or hits unexplained permission errors, check before assuming it's a script bug: $ sudo ausearch -m avc -ts recent


import time
import signal
import subprocess
import textwrap
import myloginpath
import pymysql
import pymysql.cursors
from datetime import datetime

# ==================== Configurable Variables ==================== #
LOGIN_PATH = 'local'
CHANNEL_NAME = ''                           # Replication channel name ('' = default channel)
POLL_INTERVAL_SECONDS = 5                   # How often to check Seconds_Behind_Source
LAG_THRESHOLD_SECONDS = 15                  # Lag at/above this triggers LAGGING state + evidence capture
HEAVY_EVIDENCE_INTERVAL_SECONDS = 10        # While LAGGING, re-capture full evidence this often
RECONNECT_DELAY_SECONDS = 10                # Wait time between reconnect attempts after a connection error

OK_LOG_INTERVAL_SECONDS = 60                # Only write an OK heartbeat line this often (polling stays at POLL_INTERVAL_SECONDS)

MYSQL_CLI_TIMEOUT_SECONDS = 5               # Kill a hung 'mysql' CLI evidence query after this long
MYSQL_CLI_RETRIES = 1                       # Retries on top of the first attempt before giving up on that query
MYSQL_CLI_RETRY_DELAY_SECONDS = 2           # Wait between 'mysql' CLI retries

LOG_FILE = "mysql_replication_lag_investigation.log"

# ==================== Runtime State ==================== #
_shutdown_requested = False


def handle_shutdown(signum, frame):
    global _shutdown_requested
    _shutdown_requested = True


signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)


def log(line):
    """Appends a line (or multi-line block) to the log file and prints it."""
    print(line)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


def timestamp():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


# ==================== Connection Handling ==================== #
def connect():
    conf = myloginpath.parse(LOGIN_PATH)
    connection = pymysql.connect(
        **conf,
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=True,
    )
    return connection


def ensure_connection(connection):
    """Returns a live connection, reconnecting (with retries) if needed."""
    if connection is not None:
        try:
            connection.ping(reconnect=False)
            return connection
        except Exception:
            try:
                connection.close()
            except Exception:
                pass

    while not _shutdown_requested:
        try:
            connection = connect()
            log(f"{timestamp()} | INFO | Connected to MySQL")
            return connection
        except Exception as e:
            log(f"{timestamp()} | ERROR | Could not connect: {e}. Retrying in {RECONNECT_DELAY_SECONDS}s...")
            time.sleep(RECONNECT_DELAY_SECONDS)

    return None


# ==================== Queries ==================== #
def get_replica_status(cursor):
    cursor.execute("SHOW REPLICA STATUS")
    return cursor.fetchone()  # None if this server isn't a replica / channel doesn't exist


def get_worker_rows(cursor):
    cursor.execute(
        """
        SELECT
            w.WORKER_ID,
            w.THREAD_ID,
            w.SERVICE_STATE,
            t.PROCESSLIST_ID,
            t.PROCESSLIST_USER,
            t.PROCESSLIST_HOST,
            t.PROCESSLIST_DB,
            t.PROCESSLIST_COMMAND,
            t.PROCESSLIST_TIME,
            t.PROCESSLIST_STATE,
            w.APPLYING_TRANSACTION
        FROM performance_schema.replication_applier_status_by_worker w
        LEFT JOIN performance_schema.threads t ON t.THREAD_ID = w.THREAD_ID
        WHERE w.CHANNEL_NAME = %s
        ORDER BY w.WORKER_ID
        """,
        (CHANNEL_NAME,),
    )
    return cursor.fetchall()


def classify_worker_state(processlist_state):
    state = (processlist_state or "").lower()
    if not state or "waiting for more updates" in state or "read all relay log" in state:
        return "idle"
    if "metadata lock" in state or "lock wait" in state:
        return "waiting_lock"
    if "preceding transaction" in state or "handler commit" in state or "commit order" in state:
        return "waiting_commit"
    return "applying"


def get_worker_state_counts(cursor):
    rows = get_worker_rows(cursor)
    counts = {"idle": 0, "applying": 0, "waiting_lock": 0, "waiting_commit": 0}
    for row in rows:
        counts[classify_worker_state(row["PROCESSLIST_STATE"])] += 1
    return counts


# ==================== Raw mysql CLI Evidence Queries ==================== #
EVIDENCE_QUERIES = {
    "APPLIER WORKERS": """
        SELECT w.WORKER_ID, w.THREAD_ID, w.SERVICE_STATE, t.PROCESSLIST_ID, t.PROCESSLIST_USER,
               t.PROCESSLIST_HOST, t.PROCESSLIST_DB, t.PROCESSLIST_COMMAND, t.PROCESSLIST_TIME,
               t.PROCESSLIST_STATE, w.APPLYING_TRANSACTION
        FROM performance_schema.replication_applier_status_by_worker w
        LEFT JOIN performance_schema.threads t ON t.THREAD_ID = w.THREAD_ID
        WHERE w.CHANNEL_NAME = '{channel}'
        ORDER BY w.WORKER_ID;
    """,
    "INNODB_TRX": """
        SELECT trx.trx_id, trx.trx_mysql_thread_id, t.PROCESSLIST_USER, t.PROCESSLIST_HOST,
               trx.trx_state, trx.trx_started,
               TIMESTAMPDIFF(SECOND, trx.trx_started, NOW()) AS trx_age_seconds,
               LEFT(COALESCE(t.PROCESSLIST_INFO, (
                   SELECT SQL_TEXT FROM performance_schema.events_statements_history h
                   WHERE h.THREAD_ID = t.THREAD_ID ORDER BY h.EVENT_ID DESC LIMIT 1
               )), 20) AS trx_query_preview
        FROM information_schema.innodb_trx trx
        LEFT JOIN performance_schema.threads t ON t.PROCESSLIST_ID = trx.trx_mysql_thread_id
        ORDER BY trx_age_seconds DESC;
    """,
    "METADATA_LOCKS": """
        SELECT ml.OWNER_THREAD_ID, ml.OBJECT_TYPE, ml.OBJECT_SCHEMA, ml.OBJECT_NAME, ml.LOCK_TYPE,
               ml.LOCK_DURATION, ml.LOCK_STATUS, t.PROCESSLIST_ID, t.PROCESSLIST_USER,
               t.PROCESSLIST_HOST, t.PROCESSLIST_DB, t.PROCESSLIST_TIME, t.PROCESSLIST_STATE
        FROM performance_schema.metadata_locks ml
        LEFT JOIN performance_schema.threads t ON t.THREAD_ID = ml.OWNER_THREAD_ID
        WHERE ml.OBJECT_SCHEMA NOT IN ('performance_schema', 'mysql')
          AND ml.LOCK_STATUS IN ('PENDING', 'GRANTED')
        ORDER BY ml.OBJECT_SCHEMA, ml.OBJECT_NAME, ml.LOCK_STATUS;
    """,
    "PROCESSLIST": """
        SELECT ID, USER, HOST, DB, COMMAND, TIME, STATE
        FROM information_schema.processlist
        WHERE COMMAND != 'Sleep'
        ORDER BY TIME DESC;
    """,
    "DATA_LOCK_WAITS": """
        SELECT dlr.THREAD_ID AS WAITING_THREAD_ID, dlb.THREAD_ID AS BLOCKING_THREAD_ID,
               r.PROCESSLIST_USER AS WAITING_USER, r.PROCESSLIST_HOST AS WAITING_HOST,
               b.PROCESSLIST_USER AS BLOCKING_USER, b.PROCESSLIST_HOST AS BLOCKING_HOST,
               dlr.OBJECT_SCHEMA, dlr.OBJECT_NAME, dlr.INDEX_NAME, dlr.LOCK_TYPE, dlr.LOCK_MODE,
               r.PROCESSLIST_TIME AS WAITING_TIME, b.PROCESSLIST_TIME AS BLOCKING_TIME,
               COALESCE(r.PROCESSLIST_INFO, (
                   SELECT SQL_TEXT FROM performance_schema.events_statements_history h
                   WHERE h.THREAD_ID = dlr.THREAD_ID ORDER BY h.EVENT_ID DESC LIMIT 1
               )) AS WAITING_SQL,
               COALESCE(b.PROCESSLIST_INFO, (
                   SELECT SQL_TEXT FROM performance_schema.events_statements_history h
                   WHERE h.THREAD_ID = dlb.THREAD_ID ORDER BY h.EVENT_ID DESC LIMIT 1
               )) AS BLOCKING_SQL
        FROM performance_schema.data_lock_waits lw
        JOIN performance_schema.data_locks dlr ON dlr.ENGINE_LOCK_ID = lw.REQUESTING_ENGINE_LOCK_ID
        JOIN performance_schema.data_locks dlb ON dlb.ENGINE_LOCK_ID = lw.BLOCKING_ENGINE_LOCK_ID
        LEFT JOIN performance_schema.threads r ON r.THREAD_ID = dlr.THREAD_ID
        LEFT JOIN performance_schema.threads b ON b.THREAD_ID = dlb.THREAD_ID;
    """,
}


def run_mysql_cli(sql, vertical=False):
    """Runs a query through the real mysql CLI (same login-path) and returns its own raw output, indented.
    Retries on failure/hang so one bad invocation can't crash or freeze the whole monitor."""
    if vertical:
        args = ["mysql", f"--login-path={LOGIN_PATH}", "-e", sql.rstrip(";\n ") + "\\G"]
    else:
        args = ["mysql", f"--login-path={LOGIN_PATH}", "-t", "-e", sql]

    last_error = None
    for attempt in range(1, MYSQL_CLI_RETRIES + 2):
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=MYSQL_CLI_TIMEOUT_SECONDS)
            output = result.stderr.strip() if result.returncode != 0 else result.stdout.rstrip("\n")
            return textwrap.indent(output, "    ") if output else "    (no rows)"
        except (OSError, subprocess.TimeoutExpired) as e:
            last_error = e
            if attempt <= MYSQL_CLI_RETRIES:
                time.sleep(MYSQL_CLI_RETRY_DELAY_SECONDS)

    return textwrap.indent(f"(mysql CLI failed after {MYSQL_CLI_RETRIES + 1} attempts: {last_error})", "    ")


# ==================== Evidence Capture ==================== #
def capture_evidence():
    """Dumps the raw mysql CLI output for each diagnostic query and returns it as one text block."""
    blocks = ["    [REPLICA STATUS]", run_mysql_cli("SHOW REPLICA STATUS", vertical=True)]

    for label, sql in EVIDENCE_QUERIES.items():
        blocks.append(f"    [{label}]")
        blocks.append(run_mysql_cli(sql.format(channel=CHANNEL_NAME)))

    return "\n".join(blocks)


# ==================== Main Loop ==================== #
def main():
    connection = None
    state = "OK"
    entering_time = None
    peak_lag = 0
    last_heavy_capture_time = 0
    last_ok_log_time = 0

    log(f"\n--- Starting replication lag monitor: {timestamp()} ---")

    while not _shutdown_requested:
        connection = ensure_connection(connection)
        if connection is None:
            break  # shutdown requested while reconnecting

        try:
            cursor = connection.cursor()
            replica_status = get_replica_status(cursor)

            if replica_status is None:
                log(f"{timestamp()} | ERROR | SHOW REPLICA STATUS returned no rows - is this a replica? Retrying in {RECONNECT_DELAY_SECONDS}s...")
                time.sleep(RECONNECT_DELAY_SECONDS)
                continue

            lag = replica_status.get("Seconds_Behind_Source")
            now = time.time()

            if lag is None:
                log(f"{timestamp()} | ERROR | Seconds_Behind_Source is NULL (IO/SQL thread stopped?) - Last_SQL_Error: {replica_status.get('Last_SQL_Error') or '(none)'}")

            elif lag >= LAG_THRESHOLD_SECONDS:
                if state == "OK":
                    state = "LAGGING"
                    entering_time = now
                    peak_lag = lag
                    evidence_text = capture_evidence()
                    log(f"{timestamp()} | LAGGING (entering) | lag={lag}s\n    --- evidence snapshot ---\n{evidence_text}")
                    last_heavy_capture_time = now
                else:
                    peak_lag = max(peak_lag, lag)
                    if now - last_heavy_capture_time >= HEAVY_EVIDENCE_INTERVAL_SECONDS:
                        evidence_text = capture_evidence()
                        log(f"{timestamp()} | LAGGING (ongoing) | lag={lag}s\n    --- evidence snapshot ---\n{evidence_text}")
                        last_heavy_capture_time = now
                    else:
                        counts = get_worker_state_counts(cursor)
                        log(
                            f"{timestamp()} | LAGGING (ongoing) | lag={lag}s | "
                            f"workers: {counts['idle']} idle, {counts['applying']} applying, "
                            f"{counts['waiting_lock']} waiting_lock, {counts['waiting_commit']} waiting_commit"
                        )

            else:
                if state == "LAGGING":
                    duration = int(now - entering_time)
                    evidence_text = capture_evidence()
                    log(
                        f"{timestamp()} | RECOVERED | lag={lag}s | duration={duration}s | peak_lag={peak_lag}s\n"
                        f"    --- recovered snapshot ---\n"
                        f"{evidence_text}"
                    )
                    state = "OK"
                    last_ok_log_time = now
                elif now - last_ok_log_time >= OK_LOG_INTERVAL_SECONDS:
                    log(f"{timestamp()} | OK | lag={lag}s")
                    last_ok_log_time = now

        except pymysql.err.Error as e:
            log(f"{timestamp()} | ERROR | MySQL error during poll: {e}")
            try:
                connection.close()
            except Exception:
                pass
            connection = None
            time.sleep(RECONNECT_DELAY_SECONDS)
            continue

        time.sleep(POLL_INTERVAL_SECONDS)

    log(f"--- Stopping replication lag monitor: {timestamp()} ---")
    if connection is not None:
        try:
            connection.close()
        except Exception:
            pass


if __name__ == "__main__":
    main()
