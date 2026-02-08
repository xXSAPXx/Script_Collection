#!/usr/bin/env python3


# Requirements:
# -------------------
#- $ python3 --version                                        /// Check Python Version 
#- $ pip3 install myloginpath                                 /// myloginpath (for reading MySQL login-path credentials)
#- $ dnf install python3-devel mariadb-connector-c-devel gcc  /// mysqlclient (MySQLdb) library and 'C' compiler    
#- $ pip3 install mysqlclient                                 /// mysqlclient (MySQLdb)                                       


# Description:
# -------------------
#- Connects to the MySQL database using a login path, scans all integer-based columns (tinyint, smallint, mediumint, int, bigint — both signed and unsigned) in a given schema, 
#- Calculates the current maximum value stored (WITH MULTITHREADING), and reports the fill ratio in 2 files - One full log - and one report with only the warning columns in a table format. 
#- Shows how close is the column to its maximum allowed value to avoid unexpected downtime due to column overflow.


import sys
import myloginpath
import MySQLdb
import time
import concurrent.futures
import threading
from datetime import datetime

# Configurable Variables: 
LOGIN_PATH='local'
DATABASE_TO_CHECK='sportsbook_updated'      # Set database to check
TABLE_TO_CHECK=''                           # Set optional table for check (leave empty '' if checking whole DB)
WARNING_THRESHOLD=70.0                      # Warn if column is more than 70% full
NUMBER_OF_THREADS=5                         # Set number of threads for column checking (Number of MySQL connections)

# Log File Names:
FULL_LOG_FILE = "mysql_max_int_value_full.log"
WARNING_REPORT_FILE = "mysql_max_int_value_table_report.log"

# Hardcoded Variables: 
start_time_final = time.time()              # Start time of the Script
lock = threading.Lock()                     # Lock Multithreading
COLUMNS_CHECKED = 0                         # Counter for columns checked, used for progress display (defined globally for thread access)
WARNINGS_FOUND = []                         # List to store data for the final table
TOTAL_COLUMNS_EXTRACTED = 0                 # Defined globally for thread access

def log_message(message):
    """Prints to console and appends to the full log file."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    formatted_msg = f"[{timestamp}] {message}"
    
    with lock:
        print(message)
        with open(FULL_LOG_FILE, "a") as f:
            f.write(formatted_msg + "\n")

def connect_and_fetch_columns():
    
    global TOTAL_COLUMNS_EXTRACTED

    # Parse the MySQL mysql_config_editor --login-path
    try:
        conf = myloginpath.parse((LOGIN_PATH))   # Login-path=local

    except Exception as e:
        log_message(f"Error reading login path: {e}")
        sys.exit(1)

    # Connect to database:
    try:
        connection = MySQLdb.connect(**conf, database=(DATABASE_TO_CHECK))
        log_message("Connected successfully to MySQL")
    except Exception as e:
        log_message(f"Error connecting to MySQL: {e}")
        sys.exit(1)

    # Build additional WHERE if table specified:
    TABLE_EXTRA_SQL = f"AND TABLE_NAME = '{TABLE_TO_CHECK}'" if TABLE_TO_CHECK else ""

    # Define query to check all tables for all INT data types:
    CHECK_COLUMNS_QUERY = f"""
    SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE,
           (CASE DATA_TYPE
              WHEN 'tinyint' THEN 255
              WHEN 'smallint' THEN 65535
              WHEN 'mediumint' THEN 16777215
              WHEN 'int' THEN 4294967295
              WHEN 'bigint' THEN 18446744073709551615
            END >> IF(LOCATE('unsigned', COLUMN_TYPE) > 0, 0, 1)
           ) AS MAX_VALUE
    FROM information_schema.columns
    WHERE TABLE_SCHEMA = '{DATABASE_TO_CHECK}'
    {TABLE_EXTRA_SQL}
    AND DATA_TYPE IN ('tinyint', 'smallint', 'mediumint', 'int', 'bigint');
    """

    # Execute query and store results: 
    try:
        cursor = connection.cursor()
        cursor.execute(CHECK_COLUMNS_QUERY)
        results = cursor.fetchall()
        TOTAL_COLUMNS_EXTRACTED = len(results)
        log_message(f"Total integer columns extracted: {TOTAL_COLUMNS_EXTRACTED}")
        return results, connection, conf
    except Exception as e:
        log_message(f"Error during fetching columns: {e}")
        sys.exit(1)


# ===== Fucntion to muntithread column MAX VALUE Scan: =====
def check_column_max(args_conf):
    global COLUMNS_CHECKED
    args, conf = args_conf
    table_name, column_name, column_type, max_value = args

    try:
        # Connect to the DB with a new thread (conn.cursor): 
        conn = MySQLdb.connect(**conf, database=DATABASE_TO_CHECK)
        cursor = conn.cursor()

        # Using backticks for all identifiers to prevent SQL errors on reserved words:
        MAX_VALUE_QUERY = f"SELECT MAX(`{column_name}`), ROUND((MAX(`{column_name}`)/{max_value})*100, 2) FROM `{DATABASE_TO_CHECK}`.`{table_name}`;"

        # Execute this block with multiple threads defined in main execution logic, and measure execution time for each column: 
        start_time = time.time()
        cursor.execute(MAX_VALUE_QUERY)
        current_value, ratio = cursor.fetchone()
        elapsed = time.time() - start_time

        # Check if ratio is above the warning threshold and log accordingly with thread lock to prevent mixed console output:
        with lock:
            COLUMNS_CHECKED += 1
            # Pre-calculating padding for clean progress display:
            padding = len(str(TOTAL_COLUMNS_EXTRACTED))
            progress = f"[{COLUMNS_CHECKED:>{padding}}/{TOTAL_COLUMNS_EXTRACTED}]"
            
            # If table is empty, ratio is None:
            if ratio is not None and ratio >= WARNING_THRESHOLD:
                msg = (f"{progress} 🚩 WARNING: '{table_name}'.'{column_name}' is {ratio}% full!\n"
                       f"    Type: {column_type} | Max: {max_value} | Current: {current_value} | Time: {elapsed:.2f}s")
                
                # Store data for the table report:
                WARNINGS_FOUND.append([table_name, column_name, column_type, current_value, ratio])
            else:
                msg = f"{progress} Checked '{table_name}'.'{column_name}'... OK ({elapsed:.2f}s)"
            
        # Write to console and full log
        log_message(msg)
        conn.close()

    # Handle errors: 
    except Exception as e:
        log_message(f"FAILED: {table_name}.{column_name}: {e}")

# ==================== MAIN EXECUTION =================== #

# Initialize to avoid UnboundLocalError in finally block
connection = None

try:
    results, connection, conf = connect_and_fetch_columns()
    
    # Initialize the log file with a header
    with open(FULL_LOG_FILE, "a") as f:
        f.write(f"\n--- Starting Scan: {datetime.now()} ---\n")

    with concurrent.futures.ThreadPoolExecutor(max_workers=NUMBER_OF_THREADS) as executor:
        executor.map(check_column_max, [(r, conf) for r in results])

except Exception as e:
    log_message(f"Error during processing: {e}")
finally:
    elapsed_final = time.time() - start_time_final
    summary = f"\nFinished checking. {COLUMNS_CHECKED}/{TOTAL_COLUMNS_EXTRACTED} columns evaluated in {elapsed_final:.2f} sec."
    log_message(summary)
    
    # --- GENERATE THE WARNING TABLE REPORT ---
    if WARNINGS_FOUND:
        with open(WARNING_REPORT_FILE, "w") as wf:
            wf.write(f"CRITICAL COLUMN FILL RATIO REPORT - {DATABASE_TO_CHECK}\n")
            wf.write(f"Generated: {datetime.now()} | Threshold: > {WARNING_THRESHOLD}%\n\n")
            
            header = f"{'Table':<40} | {'Column':<55} | {'Type':<25} | {'Current Val':<20} | {'Ratio':<10}"
            wf.write(header + "\n" + "-" * len(header) + "\n")
            
            # (Table Rows) Sort by ratio descending
            WARNINGS_FOUND.sort(key=lambda x: x[4], reverse=True)
            for row in WARNINGS_FOUND:
                wf.write(f"{row[0]:<40} | {row[1]:<55} | {row[2]:<25} | {row[3]:<20} | {row[4]:>8}%\n")
        
        log_message(f"\n[!] ALERT: {len(WARNINGS_FOUND)} columns exceeded threshold. See '{WARNING_REPORT_FILE}'")
    
    else:
        # Clear the warning file if no issues found to avoid reading old data:
        with open(WARNING_REPORT_FILE, "w") as wf:
            wf.write(f"Scan completed at {datetime.now()}\n")
            wf.write("No columns exceeded the warning threshold. All systems nominal.")

    if connection:
        connection.close()