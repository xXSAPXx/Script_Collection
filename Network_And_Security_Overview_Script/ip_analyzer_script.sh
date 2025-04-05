#!/usr/bin/env bash


# Variables: 
TEXTFILE_COLLECTOR_DIR=/var/lib/node_exporter/textfile_collector/

# Check if hostname is (source) or (replica): 
rpl_env_type=`hostname -s | awk -F"-" '{print $(NF)}'`
        case "$rpl_env_type" in
                rpl??|src)
                        host=$(hostname -s)
                        ;;
                *)
                        host=$(hostname -s | cut -d"-" -f1-4)
                        ;;
        esac

#host=`hostname | cut -d"-" -f1-4`
#CONN_EST=`ss -tp | grep mysql | grep ESTAB | wc -l`
#CONN_TIMEWAIT=`netstat -aonlp | grep mysq | grep -i time | wc -l`

port=3306

#netstatdb_e=$(netstat -anolp | awk -v port="$port" '$4 ~ ":"port && /ESTABLISHED/ {split($5, arr, ":"); print arr[1]}' | sort | uniq -c | sort -nr | awk -v host="$host" 'NR>0 {print "netstatdb{hostname=\""host"\", type=\"established\", label=\""$2"\"} "$1}')
#netstatdb_w=$(netstat -anolp | awk -v port="$port" '$4 ~ ":"port && /TIME_WAIT/ && !/::1:port/ {split($5, arr, ":"); print arr[1]}' | sort | uniq -c | sort -nr | awk -v host="$host" 'NR>0 {print "netstatdb{hostname=\""host"\", type=\"timewait\", label=\""$2"\"} "$1}')

netstatdb_e=$(ss  -nta -o state established '( sport = :mysql )' | awk --posix  -F":" '/([0-9]+\.){3,}/{print $(NF-2)}' | awk '{print $NF}' | cut -d "]" -f 1 | sort | uniq -c | sort -nr | awk -v host="$host" 'NR>0 {print "netstatdb{hostname=\""host"\", type=\"established\", label=\""$2"\"} "$1}')
netstatdb_w=$(ss  -nta -o state time-wait '( sport = :mysql )' | awk --posix  -F":" '/([0-9]+\.){3,}/{print $(NF-2)}' | awk '{print $NF}' | cut -d "]" -f 1 | sort | uniq -c | sort -nr | awk -v host="$host" 'NR>0 {print "netstatdb{hostname=\""host"\", type=\"timewait\", label=\""$2"\"} "$1}')


# Add the extracted data to NODE_EXPORTER_TEXTFILE_COLLECTOR_DIR:
cat <<EOF > "$TEXTFILE_COLLECTOR_DIR/netstatdb.prom.$$"
# TYPE netstatdb gauge
$netstatdb_e
$netstatdb_w
EOF

# Rename the temporary file atomically.
# This avoids the node exporter seeing half a file.
mv "$TEXTFILE_COLLECTOR_DIR/netstatdb.prom.$$" \
  "$TEXTFILE_COLLECTOR_DIR/netstatdb.prom"



