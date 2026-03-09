#!/bin/bash
set -e
set -u

LOG="/var/log/xray/access.log"
INTERVAL=5

while true
do

clear

echo "====== XRAY LIVE MONITOR ======"
echo

echo "SERVER:"
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}')
RAM=$(free -m | awk '/Mem:/ {printf "%d/%dMB (%.1f%%)", $3,$2,$3*100/$2 }')

echo "CPU: $CPU %"
echo "RAM: $RAM"
echo

echo "CONNECTED PROFILES:"
echo

# берем последние строки логов
tail -n 500 "$LOG" | grep "email:" > /tmp/xray_live

USERS=$(awk -F'email:' '{print $2}' /tmp/xray_live | sort | uniq)

COUNT=1

for USER in $USERS
do

echo "$COUNT) USER: $USER"

IPS=$(grep "email:$USER" /tmp/xray_live | awk '{print $3}' | cut -d: -f1 | sort | uniq)

DEVICE=1

for IP in $IPS
do

COUNTRY=$(curl -s ip-api.com/json/$IP | jq -r '.country')
ISP=$(curl -s ip-api.com/json/$IP | jq -r '.isp')

echo "   Device $DEVICE"
echo "      IP: $IP"
echo "      Country: $COUNTRY"
echo "      ISP: $ISP"

DEVICE=$((DEVICE+1))

done

TOTAL=$((DEVICE-1))

echo "   Devices: $TOTAL"
echo

COUNT=$((COUNT+1))

done

echo "Active profiles: $((COUNT-1))"

sleep $INTERVAL

done
