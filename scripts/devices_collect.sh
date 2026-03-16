#!/bin/bash
set -euo pipefail

ACCESS_LOG="/var/log/xray/access.log"
DB="/root/xray-panel/bot_db/users_id.db"

mkdir -p /root/xray-panel/bot_db
touch "$DB"

get_active_ips() {
    ss -tnH state established 2>/dev/null \
    | awk '
        {
            local_addr = $3
            peer_addr  = $4

            if (local_addr ~ /:443$/) {
                print peer_addr
            }
        }
    ' \
    | sed -E '
        s/^\[::ffff:([0-9.]+)\]:[0-9]+$/\1/
        t
        s/^([0-9.]+):[0-9]+$/\1/
        t
        s/^\[([0-9a-fA-F:]+)\]:[0-9]+$/\1/
    ' \
    | sort -u
}

get_email_by_ip() {
    local ip="$1"

    grep "from $ip:" "$ACCESS_LOG" 2>/dev/null | tail -n 50 | awk '
        {
            if (match($0, /email:[[:space:]]*([^ ]+)/, m)) {
                email=m[1]
            }
        }
        END {print email}
    ' || true
}

add_device_if_new() {
    local email="$1"
    local ip="$2"

    local exists
    exists=$(awk -F'|' -v e="$email" -v i="$ip" '$1==e && $2==i {print 1; exit}' "$DB" || true)

    if [ -n "${exists:-}" ]; then
        return
    fi

    local next_id
    next_id=$(awk -F'|' -v e="$email" '
        $1==e {
            if ($3+0 > max) max=$3+0
        }
        END {
            print max+1
        }
    ' "$DB")

    [ -z "$next_id" ] && next_id=1

    echo "$email|$ip|$next_id|$(date +%s)" >> "$DB"
}

mapfile -t ACTIVE_IPS < <(get_active_ips || true)

for ip in "${ACTIVE_IPS[@]}"; do
    [ -z "$ip" ] && continue
    email=$(get_email_by_ip "$ip" || true)
    [ -z "${email:-}" ] && continue

    add_device_if_new "$email" "$ip"
done
