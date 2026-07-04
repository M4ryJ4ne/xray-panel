#!/bin/bash
set -euo pipefail

DB="/root/xray-panel/bot_db/users.db"
CONFIG="/opt/xray/config.json"
PRIVATE_KEY_FILE="/opt/xray/private.key"

if [ ! -f "$DB" ]; then
    echo "users.db не найден ⚠️"
    exit 1
fi

if [ ! -f "$PRIVATE_KEY_FILE" ]; then
    echo "private.key не найден ⚠️"
    exit 1
fi

PRIVATE=$(tr -d '\r\n' < "$PRIVATE_KEY_FILE")

CLIENTS='[]'
SHORTIDS='[]'

# =========================
# СОЗДАЕМ CLIENTS И SHORTIDS JSON
# =========================

while IFS='|' read -r EMAIL UUID SHORTID; do
    [ -z "${EMAIL:-}" ] && continue
    [ -z "${UUID:-}" ] && continue
    [ -z "${SHORTID:-}" ] && continue

    CLIENT=$(jq -n \
        --arg id "$UUID" \
        --arg email "$EMAIL" \
        '{
            id: $id,
            email: $email,
            flow: "xtls-rprx-vision",
            level: 0
        }')

    CLIENTS=$(jq --argjson client "$CLIENT" '. + [$client]' <<< "$CLIENTS")
    SHORTIDS=$(jq --arg sid "$SHORTID" '. + [$sid]' <<< "$SHORTIDS")

done < "$DB"

# =========================
# BACKUP
# =========================

cp "$CONFIG" "$CONFIG.bak" 2>/dev/null || true

# =========================
# СОЗДАЕМ КОНФИГ
# =========================

jq -n \
    --arg private "$PRIVATE" \
    --argjson clients "$CLIENTS" \
    --argjson shortids "$SHORTIDS" \
'{
    log: {
        access: "/var/log/xray/access.log",
        error: "/var/log/xray/error.log",
        loglevel: "warning"
    },

    api: {
        tag: "api",
        services: ["StatsService"]
    },

    stats: {},

    policy: {
        system: {
            statsInboundUplink: true,
            statsInboundDownlink: true
        },
        levels: {
            "0": {
                statsUserUplink: true,
                statsUserDownlink: true
            }
        }
    },

    routing: {
        domainStrategy: "AsIs",
        rules: [
            {
                type: "field",
                inboundTag: ["api"],
                outboundTag: "api"
            }
        ]
    },

    inbounds: [
        {
            listen: "127.0.0.1",
            port: 10085,
            protocol: "dokodemo-door",
            settings: {
                address: "127.0.0.1"
            },
            tag: "api"
        },

        {
            port: 443,
            protocol: "vless",
            tag: "vless_tls",

            settings: {
                clients: $clients,
                decryption: "none"
            },

            streamSettings: {
                network: "tcp",
                security: "reality",

                realitySettings: {
                    show: false,
                    dest: "www.yahoo.com:443",
                    xver: 0,

                    serverNames: [
                        "www.yahoo.com"
                    ],

                    privateKey: $private,
                    shortIds: $shortids
                }
            },

            sniffing: {
                enabled: true,
                destOverride: [
                    "http",
                    "tls"
                ]
            }
        }
    ],

    outbounds: [
        {
            protocol: "freedom",
            tag: "direct"
        },
        {
            protocol: "blackhole",
            tag: "block"
        }
    ]
}' > "$CONFIG"

# =========================
# ПРОВЕРКА JSON
# =========================

jq . "$CONFIG" > /dev/null || {
    echo "CONFIG ERROR"
    exit 1
}

echo "Ребилд конфигурации сервера выполнен 🧬"

systemctl restart xray
