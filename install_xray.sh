#!/bin/bash
set -euo pipefail

echo "=============================="
echo "   XRAY REALITY INSTALLER"
echo "=============================="

PANEL_DIR="/root/xray-panel"
XRAY_DIR="/opt/xray"
CONFIG_JSON="$XRAY_DIR/config.json"
BOT_CONFIG="$PANEL_DIR/config"

DB_DIR="$PANEL_DIR/bot_db"
USERS_DB="$DB_DIR/users.db"
AUTH_DB="$DB_DIR/auth_users.db"
USERS_ID_DB="$DB_DIR/users_id.db"
PAYDAY_DB="$DB_DIR/payday.db"
PAYDAY_NOTIFY_DB="$DB_DIR/payday_notify.db"
TRAFFIC_DB="$DB_DIR/traffic_history.db"

XRAY_SERVICE="/etc/systemd/system/xray.service"
BOT_SERVICE="/etc/systemd/system/xray-bot.service"
COLLECTOR_SERVICE="/etc/systemd/system/xray-devices-collector.service"
TRAFFIC_COLLECTOR_SERVICE="/etc/systemd/system/xray-traffic-collector.service"

mkdir -p "$XRAY_DIR"
mkdir -p "$PANEL_DIR"
mkdir -p "$DB_DIR"
mkdir -p /var/log/xray

touch "$USERS_DB"
touch "$AUTH_DB"
touch "$USERS_ID_DB"
touch "$PAYDAY_DB"
touch "$PAYDAY_NOTIFY_DB"
touch "$TRAFFIC_DB"

echo "Устанавливаем зависимости..."
apt update -y
apt install -y curl unzip jq openssl python3 python3-pip ca-certificates python3-venv

cd "$PANEL_DIR"
python3 -m venv venv
"$PANEL_DIR/venv/bin/pip" install --upgrade pip
"$PANEL_DIR/venv/bin/pip" install -r "$PANEL_DIR/requirements.txt"

echo "Останавливаем старые сервисы..."
systemctl stop xray 2>/dev/null || true
systemctl stop xray-bot 2>/dev/null || true
systemctl stop xray-devices-collector 2>/dev/null || true
systemctl stop xray-traffic-collector 2>/dev/null || true

echo "Скачиваем Xray..."
cd /tmp
rm -f /tmp/xray.zip
rm -rf /tmp/xray_unpack
curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o /tmp/xray.zip
unzip -o /tmp/xray.zip -d /tmp/xray_unpack >/dev/null
rm -rf "$XRAY_DIR"
mkdir -p "$XRAY_DIR"
cp /tmp/xray_unpack/xray "$XRAY_DIR/"
chmod +x "$XRAY_DIR/xray"
rm -rf /tmp/xray_unpack

echo "Проверяем Xray..."
"$XRAY_DIR/xray" -version

echo "Генерируем Reality ключи..."
KEY_OUTPUT=$("$XRAY_DIR/xray" x25519)

PRIVATE=$(echo "$KEY_OUTPUT" | sed -n 's/^PrivateKey: *//p' | head -n1)
PUBLIC=$(echo "$KEY_OUTPUT" | sed -n 's/^Password (PublicKey): *//p' | head -n1)

if [ -z "${PUBLIC:-}" ]; then
    PUBLIC=$(echo "$KEY_OUTPUT" | sed -n 's/^PublicKey: *//p' | head -n1)
fi

if [ -z "${PRIVATE:-}" ]; then
    echo "Ошибка генерации PrivateKey"
    echo "$KEY_OUTPUT"
    exit 1
fi

if [ -z "${PUBLIC:-}" ]; then
    echo "Ошибка генерации PublicKey"
    echo "$KEY_OUTPUT"
    exit 1
fi

echo "$PRIVATE" > "$XRAY_DIR/private.key"
echo "$PUBLIC" > "$XRAY_DIR/public.key"

echo
read -rp "Введите имя первого пользователя: " USERNAME
read -rp "Введите BOT_TOKEN: " BOT_TOKEN
read -rp "Введите пароль входа в бота (BOT_PASS): " BOT_PASS
read -rp "Введите пароль для Reboot Server (REBOOT_PASS): " REBOOT_PASS
read -rp "Введите день оплаты сервера (1-31): " PAYDAY_DAY

if ! [[ "$PAYDAY_DAY" =~ ^[0-9]+$ ]] || [ "$PAYDAY_DAY" -lt 1 ] || [ "$PAYDAY_DAY" -gt 31 ]; then
    echo "Введите число от 1 до 31"
    exit 1
fi

echo "$PAYDAY_DAY" > "$PAYDAY_DB"
: > "$PAYDAY_NOTIFY_DB"

UUID=$("$XRAY_DIR/xray" uuid)
SHORTID=$(openssl rand -hex 4)

echo "$USERNAME|$UUID|$SHORTID" > "$USERS_DB"

echo "Создаём config бота..."
cat > "$BOT_CONFIG" <<EOF
BOT_TOKEN=$BOT_TOKEN
SCRIPTS_DIR=$PANEL_DIR/scripts/
REBOOT_PASS=$REBOOT_PASS
BOT_PASS=$BOT_PASS
EOF

echo "Создаём config.json Xray..."
cat > "$CONFIG_JSON" <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },

  "api": {
    "services": ["StatsService"],
    "tag": "api"
  },

  "stats": {},

  "policy": {
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    },
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    }
  },

  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      }
    ]
  },

  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    },

    {
      "port": 443,
      "protocol": "vless",
      "tag": "vless_tls",

      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "email": "$USERNAME",
            "flow": "xtls-rprx-vision",
            "level": 0
          }
        ],
        "decryption": "none"
      },

      "streamSettings": {
        "network": "tcp",
        "security": "reality",

        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,

          "serverNames": [
            "www.microsoft.com"
          ],

          "privateKey": "$PRIVATE",

          "shortIds": [
            "$SHORTID"
          ]
        }
      },

      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],

  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

echo "Проверяем JSON..."
jq . "$CONFIG_JSON" > /dev/null

echo "Выдаём права на скрипты..."
chmod +x "$PANEL_DIR/install_xray.sh" 2>/dev/null || true
chmod +x "$PANEL_DIR/build_config.sh" 2>/dev/null || true
find "$PANEL_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} \;

echo "Готовим логи Xray..."
touch /var/log/xray/access.log /var/log/xray/error.log
chmod 755 /var/log/xray
chmod 644 /var/log/xray/access.log /var/log/xray/error.log

echo "Создаём xray.service..."
cat > "$XRAY_SERVICE" <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=$XRAY_DIR/xray run -config $CONFIG_JSON
Restart=on-failure
RestartSec=5
LimitNOFILE=1000000
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "Создаём xray-bot.service..."
cat > "$BOT_SERVICE" <<EOF
[Unit]
Description=Xray Panel Telegram Bot
After=network.target xray.service

[Service]
Type=simple
WorkingDirectory=$PANEL_DIR
ExecStart=$PANEL_DIR/venv/bin/python $PANEL_DIR/bot.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "Создаём xray-devices-collector.service..."
cat > "$COLLECTOR_SERVICE" <<EOF
[Unit]
Description=Xray Devices Collector
After=network.target xray.service

[Service]
Type=simple
ExecStart=$PANEL_DIR/scripts/devices_collect_loop.sh 5
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

echo "Создаём xray-traffic-collector.service..."
cat > "$TRAFFIC_COLLECTOR_SERVICE" <<EOF
[Unit]
Description=Xray Traffic Collector
After=network.target xray.service

[Service]
Type=simple
ExecStart=$PANEL_DIR/scripts/traffic_collect_loop.sh 300
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

echo "Включаем и запускаем сервисы..."
systemctl enable xray
systemctl restart xray

sleep 2

systemctl enable xray-bot
systemctl restart xray-bot

systemctl enable xray-devices-collector
systemctl restart xray-devices-collector

systemctl enable xray-traffic-collector
systemctl restart xray-traffic-collector

IP=$(curl -s ifconfig.me)

echo
echo "=============================="
echo "       ГОТОВО"
echo "=============================="
echo

echo "Xray status:"
systemctl --no-pager --full status xray || true
echo
echo "Bot status:"
systemctl --no-pager --full status xray-bot || true
echo
echo "Devices collector status:"
systemctl --no-pager --full status xray-devices-collector || true
echo
echo "Traffic collector status:"
systemctl --no-pager --full status xray-traffic-collector || true

echo
echo "Ссылка подключения:"
echo "vless://$UUID@$IP:443?type=tcp&security=reality&pbk=$PUBLIC&flow=xtls-rprx-vision&sni=www.microsoft.com&sid=$SHORTID#$USERNAME"

echo
echo "users.db:"
cat "$USERS_DB"
echo
