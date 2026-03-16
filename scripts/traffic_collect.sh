#!/bin/bash
set -euo pipefail

XRAY_BIN="/opt/xray/xray"
XRAY_API="127.0.0.1:10085"
DB="/root/xray-panel/bot_db/traffic_history.db"

mkdir -p /root/xray-panel/bot_db
touch "$DB"

TS=$(date +%s)

"$XRAY_BIN" api statsquery --server="$XRAY_API" 2>/dev/null \
| jq -r '
    (.stat // [])[]
    | select(.name | startswith("user>>>"))
    | .name + "|" + (.value|tostring)
' \
| awk -F'|' -v ts="$TS" '
    {
        name=$1
        value=$2

        if (match(name, /user>>>(.*)>>>traffic>>>(uplink|downlink)/, m)) {
            user=m[1]
            dir=m[2]

            if (dir=="uplink") up[user]=value
            if (dir=="downlink") down[user]=value
        }
    }
    END {
        for (u in up) {
            if (down[u] == "") down[u]=0
            print ts "|" u "|" up[u] "|" down[u]
        }
        for (u in down) {
            if (!(u in up)) print ts "|" u "|0|" down[u]
        }
    }
' | sort -u >> "$DB"
