#!/bin/bash

DB="/root/xray-panel/users.db"

echo
echo "Выберите номер пользователя для удаления:"
echo

nl -w2 -s') ' "$DB" | cut -d'|' -f1,2

echo
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

echo
echo "Пользователь $EMAIL удален"
