#!/bin/bash
set -e
set -u

DB="/root/xray-panel/bot_db/users.db"

IP=$(curl -s ifconfig.me)
PUBLIC=$(cat /opt/xray/public.key)

echo
echo "Список профилей 📙"
echo
echo "Всего: $(wc -l < $DB)"
echo

i=1

while IFS="|" read -r EMAIL UUID SHORTID
do

LINK="vless://$UUID@$IP:443?type=tcp&security=reality&pbk=$PUBLIC&flow=xtls-rprx-vision&sni=www.microsoft.com&sid=$SHORTID#$EMAIL"

echo "№ $i. $EMAIL📲"
echo "$LINK"
echo

((i++))

done < "$DB"
