#!/bin/bash
set -euo pipefail

USERS_DB="/root/xray-panel/bot_db/users.db"
DEVICES_DB="/root/xray-panel/bot_db/users_id.db"
TRAFFIC_DB="/root/xray-panel/bot_db/traffic_history.db"

TMP_DIR="/tmp/xray_profile_report"
mkdir -p "$TMP_DIR"

TRAFFIC_7D="$TMP_DIR/traffic_7d.db"
TRAFFIC_30D="$TMP_DIR/traffic_30d.db"

NOW=$(date +%s)

human_bytes() {
    local bytes="${1:-0}"

    if [ "$bytes" -ge 1099511627776 ]; then
        awk -v v="$bytes" 'BEGIN {printf "%.2f TB", v/1099511627776}'
    elif [ "$bytes" -ge 1073741824 ]; then
        awk -v v="$bytes" 'BEGIN {printf "%.2f GB", v/1073741824}'
    elif [ "$bytes" -ge 1048576 ]; then
        awk -v v="$bytes" 'BEGIN {printf "%.2f MB", v/1048576}'
    elif [ "$bytes" -ge 1024 ]; then
        awk -v v="$bytes" 'BEGIN {printf "%.2f KB", v/1024}'
    else
        echo "${bytes} B"
    fi
}

build_window_traffic() {
    local days="$1"
    local out_file="$2"
    local start_ts=$((NOW - days*86400))

    : > "$out_file"

    if [ ! -f "$TRAFFIC_DB" ] || [ ! -s "$TRAFFIC_DB" ]; then
        return
    fi

    awk -F'|' -v start="$start_ts" '
        $1 >= start {
            ts=$1
            user=$2
            up=$3+0
            down=$4+0
            total=up+down

            if (!(user in first_ts) || ts < first_ts[user]) {
                first_ts[user]=ts
                first_total[user]=total
            }

            if (!(user in last_ts) || ts > last_ts[user]) {
                last_ts[user]=ts
                last_total[user]=total
            }
        }
        END {
            for (u in last_total) {
                delta=last_total[u]-first_total[u]
                if (delta < 0) delta=0
                print u "|" delta
            }
        }
    ' "$TRAFFIC_DB" | sort -u > "$out_file"
}

get_user_traffic() {
    local user="$1"
    local file="$2"

    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        echo "0"
        return
    fi

    awk -F'|' -v u="$user" '$1==u {print $2; found=1} END {if (!found) print 0}' "$file"
}

build_window_traffic 7 "$TRAFFIC_7D"
build_window_traffic 30 "$TRAFFIC_30D"

echo "🔮 XRAY REPORT 🔮"
echo

profile_index=0

if [ ! -f "$USERS_DB" ] || [ ! -s "$USERS_DB" ]; then
    echo "База профилей пуста 🤷‍♂"
    exit 0
fi

while IFS='|' read -r email uuid shortid; do
    [ -z "${email:-}" ] && continue

    profile_index=$((profile_index+1))

    traffic_7=$(get_user_traffic "$email" "$TRAFFIC_7D")
    traffic_30=$(get_user_traffic "$email" "$TRAFFIC_30D")

    echo "$profile_index. $email📲"
    echo "   ♒️ Трафик за 7д:  $(human_bytes "$traffic_7")"
    echo "   ♒️ Трафик за 30д: $(human_bytes "$traffic_30")"
    echo

done < "$USERS_DB"

total_profiles=$(awk 'NF>0' "$USERS_DB" | wc -l)

if [ -f "$DEVICES_DB" ] && [ -s "$DEVICES_DB" ]; then
    total_devices=$(awk -F'|' '!seen[$1 FS $2]++' "$DEVICES_DB" | wc -l)
else
    total_devices=0
fi

if [ -f "$TRAFFIC_7D" ] && [ -s "$TRAFFIC_7D" ]; then
    total_traffic_7=$(awk -F'|' '{sum+=$2} END {print sum+0}' "$TRAFFIC_7D")
else
    total_traffic_7=0
fi

if [ -f "$TRAFFIC_30D" ] && [ -s "$TRAFFIC_30D" ]; then
    total_traffic_30=$(awk -F'|' '{sum+=$2} END {print sum+0}' "$TRAFFIC_30D")
else
    total_traffic_30=0
fi

echo "🪁 Общее"
echo "✳️ Всего профилей: $total_profiles"
echo "🆔 Всего IP: $total_devices"
echo "♒️ Трафик за 7д: $(human_bytes "$total_traffic_7")"
echo "♒️ Трафик за 30д: $(human_bytes "$total_traffic_30")"
