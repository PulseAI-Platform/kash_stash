#!/bin/bash

hostname=$(hostname)

# --- Get MEM ---
MEM_PCT=""
if command -v free &>/dev/null; then  # Linux
    MEM_PCT=$(free | awk '/Mem:/ { printf("%.0f", ($3/$2)*100) }')
elif vm_stat &>/dev/null; then        # macOS
    pagesize=$(sysctl -n hw.pagesize)
    mem_total=$(sysctl -n hw.memsize)
    mem_free=$(vm_stat | awk '/Pages free/ {print $3}' | tr -d .)
    mem_inactive=$(vm_stat | awk '/Pages inactive/ {print $3}' | tr -d .)
    free_bytes=$(( ($mem_free + $mem_inactive) * $pagesize ))
    used_bytes=$(( $mem_total - $free_bytes ))
    MEM_PCT=$(awk -v used=$used_bytes -v total=$mem_total 'BEGIN{printf "%.0f", (used/total)*100}')
else
    MEM_PCT=0
fi

# --- Get CPU ---
CPU_PCT=""
if top -bn1 &>/dev/null 2>&1; then   # Linux
    CPU_LINE=$(top -bn1 | grep "Cpu(s)" | head -n 1)
    if [ -n "$CPU_LINE" ]; then
        idle=$(echo "$CPU_LINE" | awk -F',' '{ for(i=1;i<=NF;i++) if($i ~ /id/) {match($i,/[0-9.]+/); print substr($i, RSTART, RLENGTH)} }')
        [ -z "$idle" ] && idle=0
        CPU_PCT=$(awk -v i="$idle" 'BEGIN{ printf "%.0f", 100-i }')
    fi
elif top -l 1 &>/dev/null 2>&1; then    # macOS
    CPU_PCT=$(top -l 1 | awk -F'[:,]' '/CPU usage/ {gsub(/%.*/,"",$2);gsub(/%.*/,"",$3);u=$2+0;s=$3+0; printf "%.0f", u+s}')
else
    CPU_PCT=0
fi
[ -z "$CPU_PCT" ] && CPU_PCT=0

# --- Get Bandwidth (RX+TX per second as % of 100 MB/s)---
BW_PCT=0
if [ -e /proc/net/dev ]; then
    IFACE=$(ip route | awk '/default/ {print $5; exit}')
    [ -z "$IFACE" ] && IFACE=$(ip link | awk -F: '$0 ~ "^[0-9]+:" {print $2}' | grep -Ev 'lo|docker|veth' | head -n1 | xargs)
    [ -z "$IFACE" ] && IFACE="eth0"
    R1=$(cat /sys/class/net/${IFACE}/statistics/rx_bytes 2>/dev/null || echo 0)
    T1=$(cat /sys/class/net/${IFACE}/statistics/tx_bytes 2>/dev/null || echo 0)
    sleep 1
    R2=$(cat /sys/class/net/${IFACE}/statistics/rx_bytes 2>/dev/null || echo 0)
    T2=$(cat /sys/class/net/${IFACE}/statistics/tx_bytes 2>/dev/null || echo 0)
    DELTA=$(( (R2+T2)-(R1+T1) ))
    BW_MBPS=$(awk -v d="$DELTA" 'BEGIN {printf "%.0f", d/1048576 }')
    [ "$BW_MBPS" -gt 100 ] && BW_PCT=100 || BW_PCT=$BW_MBPS
fi

# Bar func: prints 20 chars max
bar() {
    pct=$1
    n=$(( ($pct*20)/100 ))
    chars=$(printf "%${n}s" | tr ' ' '#')
    pad=$(printf "%$((20-n))s")
    printf "%s%s (%s%%)" "$chars" "$pad" "$pct"
}

mem_bar=$(bar "$MEM_PCT")
cpu_bar=$(bar "$CPU_PCT")
bw_bar=$(bar "$BW_PCT")

tags="sysok,$hostname"
note=""

for what in mem cpu bw; do
    val=$(eval echo \$"${what^^}_PCT")
    if [ "$val" -ge 90 ]; then
        tags="$tags,${what}alert,alert"
        note="${note}${what^} alert: $val%
"
    elif [ "$val" -ge 70 ]; then
        tags="$tags,${what}warn,warning"
        note="${note}${what^} warning: $val%
"
    fi
done

graph="Mem: $mem_bar
Cpu: $cpu_bar
Bw : $bw_bar"

final_report="$graph"
if [ -n "$note" ]; then
    final_report="${final_report}

Warnings/Alerts:
$note"
fi

# Output JSON as required by the agent
echo "$final_report"
base64content=$(echo "$final_report" | base64 -w 0)
echo "{\"tags\": \"$tags\", \"content\": \"$base64content\"}"