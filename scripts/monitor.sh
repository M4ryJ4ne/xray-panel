#!/bin/bash
set -e
set -u

LOG="/var/log/xray/access.log"
INTERVAL=2
IFACE=$(ip route | grep default | awk '{print $5}')

get_country() {
curl -s http://ip-api.com/json/$1 | jq -r '.country'
}

get_isp() {
curl -s http://ip-api.com/json/$1 | jq -r '.isp'
}

get_ping() {
ping -c1 -W1 $1 2>/dev/null | awk -F'=' '/time=/ {print $4}'
}

while true
do

clear

echo "====== XRAY LIVE MONITOR ======"
echo

CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}')
RAM=$(free -m | awk '/Mem:/ {printf "%d/%dMB (%.1f%%)", $3,$2,$3*100/$2 }')

RX=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
TX=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)

sleep 1

RX2=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
TX2=$(cat /sys/class/net/$IFACE/statistics/tx_bytes)

DOWN=$((RX2-RX))
UP=$((TX2-TX))

echo "SERVER"
echo "CPU: $CPU%"
echo "RAM: $RAM"
echo "NET: $((DOWN/1024)) KB/s ↓  $((UP/1024)) KB/s ↑"
echo

echo "USERS"
echo

IPS=$(ss -tn state established '( sport = :443 )' | awk '{print $5}' | cut -d: -f1 | sort | uniq)

COUNT=1

for IP in $IPS
do

USER=$(grep "$IP" $LOG | tail -1 | awk -F'email:' '{print $2}')

COUNTRY=$(get_country $IP)
ISP=$(get_isp $IP)
PING=$(get_ping $IP)

echo "$COUNT) $USER"
echo "   Device 1"
echo "      IP: $IP"
echo "      Country: $COUNTRY"
echo "      ISP: $ISP"
echo "      Ping: $PING"
echo

COUNT=$((COUNT+1))

done

sleep $INTERVAL

done
