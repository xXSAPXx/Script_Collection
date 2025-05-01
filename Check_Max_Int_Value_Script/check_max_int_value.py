#!/usr/bin/env python3


# Requirements:
# -------------------
#- $ python3 --version                                       /// Check Python Version 
#- $ pip install myloginpath                                 /// myloginpath (for reading MySQL login-path credentials)
#- $ dnf install python3-devel mariadb-connector-c-devel gcc /// mysqlclient (MySQLdb) library and 'C' compiler    
#- $ pip3 install mysqlclient                                /// mysqlclient (MySQLdb)                                       


# Description:
# -------------------
#- Connects to the MySQL database using a login path, scans all integer-based columns (tinyint, smallint, mediumint, int, bigint — both signed and unsigned) in a given schema, 
#- calculates the current maximum value stored (WITH MULTITHREADING), and reports the fill ratio: 
#- (How close the column is to its maximum allowed value).


import sys
import myloginpath
import MySQLdb
import time
import concurrent.futures
import threading


# Configurable Variables: 
DATABASE_TO_CHECK='sportsbook_updated'      # Set database to check
TABLE_TO_CHECK = ''                         # Set optional table for check (leave empty '' if checking whole DB)
WARNING_THRESHOLD = 70.0                    # Warn if column is more than 70% full
NUMBER_OF_THREADS=5                         # Set number of threads for column checking (Number of MySQL connections)


# Hardcoded Variables: 
start_time_final = time.time()              # Start time of the Script
lock = threading.Lock()                     # Lock Multithreading 
COLUMNS_CHECKED = 0


# ===== Function to connect to DB and extract all columns =====
def connect_and_fetch_columns():

    # Parse the MySQL mysql_config_editor --login-path
    try:
        conf = myloginpath.parse('local')   # Login-path=local

    except Exception as e:
        print(f"Error reading login path: {e}")
        sys.exit(1)

    # Connect to database:
    try:
        connection = MySQLdb.connect(**conf, database=(DATABASE_TO_CHECK))
        print("\nConnected successfully to MySQL")

    except Exception as e:
        print(f"Error connecting to MySQL: {e}")
        sys.exit(1)


    # Build additional WHERE if table specified:
    TABLE_EXTRA_SQL = ""
    if TABLE_TO_CHECK:
        TABLE_EXTRA_SQL = f"AND TABLE_NAME = '{TABLE_TO_CHECK}'"

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
        print(f"\nTotal integer columns extracted from schema '{DATABASE_TO_CHECK}': {TOTAL_COLUMNS_EXTRACTED}")
        print("Checking columns...\n")
        return results, TOTAL_COLUMNS_EXTRACTED, connection, conf

    # Handle errors: 
    except Exception as e:
        print(f"Error during fetching columns: {e}")
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

        # Define query to find MAX(column_value) and ratio: 
        MAX_VALUE_QUERY = f"""
        SELECT 
            MAX(`{column_name}`), 
            ROUND((MAX(`{column_name}`)/{max_value})*100, 2) AS ratio
        FROM `{DATABASE_TO_CHECK}`.`{table_name}`;
        """

        # Execute this block with multiple threads: 
        start_time = time.time()
        cursor.execute(MAX_VALUE_QUERY)
        result = cursor.fetchone()
        elapsed = time.time() - start_time

        # Fetch only max value and calculated column fill ration: 
        current_value, ratio = result


        # Check the value against the defined WARNING_THRESHOLD: 
        # Lock multithreading for checks: 
        with lock:
            COLUMNS_CHECKED += 1
            if ratio is not None and ratio >= WARNING_THRESHOLD:
                print(f"[{COLUMNS_CHECKED :>{len(str(TOTAL_COLUMNS_EXTRACTED))}}/{TOTAL_COLUMNS_EXTRACTED}] Checked '{table_name}'.'{column_name}' - Type: '{column_type}'")
                print(f"  Column Max: {max_value}")
                print(f"  Current Value: {current_value}")
                print(f"  Time taken: {elapsed:.2f} sec")
                print(f"  Fill Ratio: {ratio:.2f}% 🚩")
                print("-" * 50)
            else:
                 print(f"[{COLUMNS_CHECKED :>{len(str(TOTAL_COLUMNS_EXTRACTED))}}/{TOTAL_COLUMNS_EXTRACTED}] Checked '{table_name}'.'{column_name}'... OK ({elapsed:.2f} sec)")
        
        # Close thread connection
        conn.close()

    # Handle errors: 
    except Exception as e:
        elapsed = time.time() - start_time
        # Lock multithreading for print: 
        with lock:
            print(f"FAILED after {elapsed:.2f} sec: {e}")
            print("SQL: ", MAX_VALUE_QUERY)



# ==================== MAIN SCRIPT EXECUTION ===================  

# Call func CONNECT_AND_FETCH_COLUMNS and pass variables to CHECK_COLUMN_MAX func with multiple threads: 
try:
    results, TOTAL_COLUMNS_EXTRACTED, connection, conf = connect_and_fetch_columns()
    with concurrent.futures.ThreadPoolExecutor(max_workers=NUMBER_OF_THREADS) as executor:
        executor.map(check_column_max, [(r, conf) for r in results])

except Exception as e:
    print(f"Error during processing: {e}")
    sys.exit(1)

# Print the full lenght of the script running and close main connection: 
finally:
    elapsed_final = time.time() - start_time_final
    print(f"\nFinished checking. {COLUMNS_CHECKED} out of {TOTAL_COLUMNS_EXTRACTED} columns were successfully evaluated. For {elapsed_final:.2f} sec")
    connection.close()
