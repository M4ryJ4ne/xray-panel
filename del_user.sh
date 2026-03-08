#!/bin/bash
set -e
set -u

DB="/root/xray-panel/users.db"

read NUM

USER=$(sed -n "${NUM}p" "$DB")

if [ -z "$USER" ]; then
    echo "Неверный номер"
    exit 1
fi

EMAIL=$(echo "$USER" | cut -d'|' -f1)

sed -i "${NUM}d" "$DB"

bash /root/xray-panel/build_config.sh

systemctl restart xray

echo "Пользователь $EMAIL удален"
