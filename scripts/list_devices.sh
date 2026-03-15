#!/bin/bash
set -euo pipefail

DB="/root/xray-panel/bot_db/users_id.db"

if [ ! -f "$DB" ] || [ ! -s "$DB" ]; then
    echo "База устройств пуста 🫟"
    exit 0
fi

echo "📒 Список устройств 📒"
echo

current_user=""
count=0

while IFS='|' read -r email ip device_id first_seen; do
    [ -z "${email:-}" ] && continue

    if [ "$email" != "$current_user" ]; then
        if [ -n "$current_user" ]; then
            echo
        fi

        count=$((count+1))
        echo "$count. $email📲"
        echo
        current_user="$email"
    fi

    if [ -n "${first_seen:-}" ]; then
        first_seen_human=$(date -d "@$first_seen" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$first_seen")
    else
        first_seen_human="unknown"
    fi

    echo "   $device_id. $ip"
    echo "      Первое подключение: $first_seen_human"

done < <(sort -t'|' -k1,1 -k3,3n "$DB")
