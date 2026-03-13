#!/bin/bash
set -euo pipefail

XRAY_BIN="/opt/xray/xray"
XRAY_API="127.0.0.1:10085"
ACCESS_LOG="/var/log/xray/access.log"
DB="/root/xray-panel/bot_db/users_id.db"
INTERVAL="${1:-3}"

mkdir -p /root/xray-panel/bot_db
touch "$DB"

TMP_DIR="/tmp/xray_live_monitor"
mkdir -p "$TMP_DIR"

LAST_STATS="$TMP_DIR/last_stats.db"
CUR_STATS="$TMP_DIR/current_stats.db"
touch "$LAST_STATS"

# -----------------------------
# Получить стабильный номер IP внутри профиля
# Формат DB:
# email|ip|device_id|first_seen_unix
# -----------------------------
get_device_id() {
    local email="$1"
    local ip="$2"

    local existing
    existing=$(awk -F'|' -v e="$email" -v i="$ip" '$1==e && $2==i {print $3}' "$DB" | head -n1)

    if [ -n "$existing" ]; then
        echo "$existing"
        return
    fi

    local max_id
    max_id=$(awk -F'|' -v e="$email" '$1==e {if ($3>max) max=$3} END {print max+1}' "$DB")
    [ -z "$max_id" ] && max_id=1

    echo "$email|$ip|$max_id|$(date +%s)" >> "$DB"
    echo "$max_id"
}

# -----------------------------
# geo cache
# -----------------------------
get_geo() {
    local ip="$1"
    local cache="$TMP_DIR/geo_${ip}.json"

    if [ ! -f "$cache" ]; then
        curl -s --max-time 3 "http://ip-api.com/json/$ip?fields=status,country,isp,query" > "$cache" || true
    fi

    local country isp
    country=$(jq -r '.country // "Unknown"' "$cache" 2>/dev/null || echo "Unknown")
    isp=$(jq -r '.isp // "Unknown"' "$cache" 2>/dev/null || echo "Unknown")

    echo "$country|$isp"
}

# -----------------------------
# Получаем трафик по профилям из Xray API
# Пишем:
# email|uplink|downlink
# -----------------------------
read_xray_stats() {
    : > "$CUR_STATS"

    "$XRAY_BIN" api statsquery --server="$XRAY_API" 2>/dev/null | awk '
        /name:/ {
            if (match($0, /user>>>([^"]+)>>>traffic>>>(uplink|downlink)/, m)) {
                user=m[1]
                dir=m[2]
            }
        }
        /value:/ {
            gsub(/[^0-9]/, "", $0)
            if (user != "" && dir != "") {
                print user "|" dir "|" $0
                user=""
                dir=""
            }
        }
    ' | awk -F'|' '
        {
            key=$1
            if ($2=="uplink") up[key]=$3
            if ($2=="downlink") down[key]=$3
        }
        END {
            for (k in up) {
                if (down[k]=="") down[k]=0
                print k "|" up[k] "|" down[k]
            }
            for (k in down) {
                if (!(k in up)) print k "|0|" down[k]
            }
        }
    ' | sort -u > "$CUR_STATS"
}

# -----------------------------
# скорость профиля за интервал
# -----------------------------
get_profile_rate() {
    local email="$1"

    local cur_up cur_down old_up old_down
    cur_up=$(awk -F'|' -v e="$email" '$1==e {print $2}' "$CUR_STATS")
    cur_down=$(awk -F'|' -v e="$email" '$1==e {print $3}' "$CUR_STATS")
    old_up=$(awk -F'|' -v e="$email" '$1==e {print $2}' "$LAST_STATS")
    old_down=$(awk -F'|' -v e="$email" '$1==e {print $3}' "$LAST_STATS")

    [ -z "$cur_up" ] && cur_up=0
    [ -z "$cur_down" ] && cur_down=0
    [ -z "$old_up" ] && old_up=0
    [ -z "$old_down" ] && old_down=0

    local delta_up delta_down
    delta_up=$(( (cur_up - old_up) / INTERVAL ))
    delta_down=$(( (cur_down - old_down) / INTERVAL ))

    [ "$delta_up" -lt 0 ] && delta_up=0
    [ "$delta_down" -lt 0 ] && delta_down=0

    echo "$delta_up|$delta_down"
}

human_bps() {
    local bps="$1"
    if [ "$bps" -ge 1048576 ]; then
        awk -v v="$bps" 'BEGIN {printf "%.2f MB/s", v/1048576}'
    elif [ "$bps" -ge 1024 ]; then
        awk -v v="$bps" 'BEGIN {printf "%.2f KB/s", v/1024}'
    else
        echo "${bps} B/s"
    fi
}

# -----------------------------
# CPU/RAM
# -----------------------------
get_cpu() {
    top -bn1 | awk -F'[, ]+' '/Cpu\(s\)/ {printf "%.1f", $2 + $4}'
}

get_ram() {
    free -m | awk '/Mem:/ {printf "%d/%dMB (%.1f%%)", $3,$2,$3*100/$2}'
}

# -----------------------------
# Активные IP на 443
# -----------------------------
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

# -----------------------------
# Найти профиль по IP из access.log
# Берём последнюю подходящую строку
# -----------------------------
get_email_by_ip() {
    local ip="$1"

    grep "from $ip:" "$ACCESS_LOG" 2>/dev/null | tail -n 50 | awk '
        {
            if (match($0, /email:[[:space:]]*([^ ]+)/, m)) {
                email=m[1]
            }
        }
        END {print email}
    '
}

# -----------------------------
# основной цикл
# -----------------------------
#while true; do
    read_xray_stats

#    clear
    echo "====== XRAY LIVE PROFILES ======"
    echo
    echo "SERVER"
    echo "CPU: $(get_cpu)%"
    echo "RAM: $(get_ram)"
    echo

    mapfile -t ACTIVE_IPS < <(get_active_ips)

    declare -A USER_IPS=()

    for ip in "${ACTIVE_IPS[@]}"; do
        [ -z "$ip" ] && continue
        email=$(get_email_by_ip "$ip")
        [ -z "$email" ] && continue

        if [ -z "${USER_IPS[$email]:-}" ]; then
            USER_IPS[$email]="$ip"
        else
            case " ${USER_IPS[$email]} " in
                *" $ip "*) ;;
                *) USER_IPS[$email]="${USER_IPS[$email]} $ip" ;;
            esac
        fi
    done

    if [ "${#USER_IPS[@]}" -eq 0 ]; then
        echo "Активных профилей нет"
    else
        idx=1
        for email in $(printf "%s\n" "${!USER_IPS[@]}" | sort); do
            echo "$idx. $email"

            rates=$(get_profile_rate "$email")
            up_bps=${rates%|*}
            down_bps=${rates#*|}

            echo "   Profile traffic:"
            echo "      Down: $(human_bps "$down_bps")"
            echo "      Up:   $(human_bps "$up_bps")"

            ip_count=0
            for ip in ${USER_IPS[$email]}; do
                ip_count=$((ip_count+1))
                dev_id=$(get_device_id "$email" "$ip")

                geo=$(get_geo "$ip")
                country=${geo%%|*}
                isp=${geo#*|}

                echo "   $dev_id. $ip"
                echo "      Country: $country"
                echo "      ISP: $isp"
            done

            echo "   Active IPs now: $ip_count"
            echo
            idx=$((idx+1))
        done
    fi

    cp "$CUR_STATS" "$LAST_STATS"
#    sleep "$INTERVAL"
#done
