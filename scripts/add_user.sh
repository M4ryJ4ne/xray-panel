#!/bin/bash
set -e
set -u

DB="/root/xray-panel/bot_db/users.db"

USERNAME="$1"
#echo "Введите имя пользователя:"
#read USERNAME

UUID=$(/opt/xray/xray uuid)

SHORTID=$(openssl rand -hex 4)

echo "$USERNAME|$UUID|$SHORTID" >> "$DB"

bash /root/xray-panel/build_config.sh

systemctl restart xray

IP=$(curl -s ifconfig.me)
PUBLIC=$(cat /opt/xray/public.key)

echo
echo "Пользователь создан"
echo

echo "vless://$UUID@$IP:443?type=tcp&security=reality&pbk=$PUBLIC&flow=xtls-rprx-vision&sni=www.microsoft.com&sid=$SHORTID#$USERNAME"
