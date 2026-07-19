#!/bin/bash

# Always run from the script's own directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# ==========================================================
# Website Health Monitoring System
#
# Description:
# Monitors website availability using ICMP, TCP port checks,
# HTTP status codes, and response time.
#
# Monitoring Policy:
# - Website availability monitor (not host monitoring)
# - Ping (ICMP): Informational only
# - Port: Required
# - HTTP: Primary health signal
#     2xx / 3xx -> HEALTHY
#     4xx / 5xx -> UNHEALTHY
#     000       -> DOWN
# ==========================================================

mkdir -p logs reports

LOGFILE="logs/health.log"
CSVFILE="reports/health_report.csv"
WEBSITE_FILE="websites.txt"
CURL_TIMEOUT=5

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

TOTAL_COUNT=0
HEALTHY_COUNT=0
UNHEALTHY_COUNT=0
DOWN_COUNT=0

if [ ! -f "$WEBSITE_FILE" ]; then
    echo "ERROR: $WEBSITE_FILE not found!"
    exit 1
fi

if [ ! -s "$WEBSITE_FILE" ]; then
    echo "ERROR: $WEBSITE_FILE is empty!"
    exit 1
fi

# Create CSV header only once (preserve monitoring history)
if [ ! -f "$CSVFILE" ]; then
    echo "Timestamp,Website,Ping Status,Port Status,HTTP Status,Response Time,Overall Status" > "$CSVFILE"
fi

echo -e "${BLUE}"
echo "==============================================================="
echo "             Website Health Monitoring System"
echo "==============================================================="
echo -e "${RESET}"

while IFS= read -r WEBSITE
do
    WEBSITE=${WEBSITE//$'\r'/}

    [ -z "$WEBSITE" ] && continue
    [[ "$WEBSITE" =~ ^# ]] && continue

    TOTAL_COUNT=$((TOTAL_COUNT+1))
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

    echo
    echo "==============================================================="
    echo -e "${CYAN}Checking Website : $WEBSITE${RESET}"

    # Ping (Informational Only)
    if ping -4 -c 1 "$WEBSITE" >/dev/null 2>&1; then
        PING_STATUS="UP"
    else
        PING_STATUS="DOWN"
    fi

    # Port check + protocol selection
    if nc -z -w2 "$WEBSITE" 443 >/dev/null 2>&1; then
        PORT_STATUS="HTTPS OPEN"
        PROTOCOL="https"
    elif nc -z -w2 "$WEBSITE" 80 >/dev/null 2>&1; then
        PORT_STATUS="HTTP OPEN"
        PROTOCOL="http"
    else
        PORT_STATUS="CLOSED"
        PROTOCOL="https"
    fi

    read HTTP_STATUS RESPONSE_TIME <<< "$(
        curl -o /dev/null -s --max-time "$CURL_TIMEOUT" \
        -w "%{http_code} %{time_total}" \
        "$PROTOCOL://$WEBSITE"
    )"

    if [ "$HTTP_STATUS" = "000" ]; then
        DISPLAY_TIME="Timeout"
    elif [[ "$RESPONSE_TIME" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        DISPLAY_TIME=$(printf "%.3f sec" "$RESPONSE_TIME")
    else
        DISPLAY_TIME="N/A"
    fi

    if [ "$PORT_STATUS" = "CLOSED" ] || [ "$HTTP_STATUS" = "000" ]; then
        OVERALL_STATUS="DOWN"
        DOWN_COUNT=$((DOWN_COUNT+1))
    elif [[ "$HTTP_STATUS" =~ ^[23][0-9][0-9]$ ]]; then
        OVERALL_STATUS="HEALTHY"
        HEALTHY_COUNT=$((HEALTHY_COUNT+1))
    else
        OVERALL_STATUS="UNHEALTHY"
        UNHEALTHY_COUNT=$((UNHEALTHY_COUNT+1))
    fi

    case "$OVERALL_STATUS" in
        HEALTHY) STATUS_COLOR=$GREEN ;;
        UNHEALTHY) STATUS_COLOR=$YELLOW ;;
        DOWN) STATUS_COLOR=$RED ;;
        *) STATUS_COLOR=$RESET ;;
    esac

    printf "%-18s : %s\n" "Ping Status" "$PING_STATUS"
    printf "%-18s : %s\n" "Port Status" "$PORT_STATUS"
    printf "%-18s : %s\n" "HTTP Status" "$HTTP_STATUS"
    printf "%-18s : %s\n" "Response Time" "$DISPLAY_TIME"
    echo -e "Overall Status     : ${STATUS_COLOR}${OVERALL_STATUS}${RESET}"

    echo "$TIMESTAMP | $WEBSITE | PING:$PING_STATUS | PORT:$PORT_STATUS | HTTP:$HTTP_STATUS | $DISPLAY_TIME | $OVERALL_STATUS" >> "$LOGFILE"
    echo "$TIMESTAMP,$WEBSITE,$PING_STATUS,$PORT_STATUS,$HTTP_STATUS,$DISPLAY_TIME,$OVERALL_STATUS" >> "$CSVFILE"

done < "$WEBSITE_FILE"

echo
echo -e "${BLUE}====================== SUMMARY ======================${RESET}"

printf "%-25s : %d\n" "Total Websites" "$TOTAL_COUNT"

echo -ne "${GREEN}"
printf "%-25s : %d\n" "Healthy Websites" "$HEALTHY_COUNT"
echo -ne "${RESET}"

echo -ne "${YELLOW}"
printf "%-25s : %d\n" "Unhealthy Websites" "$UNHEALTHY_COUNT"
echo -ne "${RESET}"

echo -ne "${RED}"
printf "%-25s : %d\n" "Down Websites" "$DOWN_COUNT"
echo -ne "${RESET}"

echo
echo "Logs Saved : $LOGFILE"
echo "CSV Saved  : $CSVFILE"
echo "Monitoring Completed Successfully."
