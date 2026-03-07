#!/bin/bash

systemctl stop xray 2>/dev/null
rm -rf /opt/xray
rm -f /etc/systemd/system/xray.service

set -e

echo "=============================="
echo "   XRAY REALITY INSTALLER"
echo "=============================="

PANEL_DIR="/root/xray-panel"
XRAY_DIR="/opt/xray"
CONFIG="$XRAY_DIR/config.json"
DB="$PANEL_DIR/users.db"

mkdir -p $XRAY_DIR
mkdir -p $PANEL_DIR
mkdir -p /var/log/xray

echo "Устанавливаем зависимости..."

apt update -y
apt install -y curl unzip jq openssl

echo "Скачиваем Xray..."

cd /tmp
curl -L https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip -o xray.zip

unzip -o xray.zip
mv xray $XRAY_DIR/
chmod +x $XRAY_DIR/xray

echo "Проверяем Xray..."

$XRAY_DIR/xray -version

echo "Генерируем Reality ключи..."

KEY_OUTPUT=$($XRAY_DIR/xray x25519)

PRIVATE=$(echo "$KEY_OUTPUT" | grep "PrivateKey" | awk '{print $2}')
PUBLIC=$(echo "$KEY_OUTPUT" | grep "Password" | awk '{print $2}')

if [ -z "$PRIVATE" ]; then
echo "Ошибка генерации PrivateKey"
echo "$KEY_OUTPUT"
exit 1
fi

if [ -z "$PUBLIC" ]; then
echo "Ошибка генерации PublicKey"
echo "$KEY_OUTPUT"
exit 1
fi

echo "$PRIVATE" > $XRAY_DIR/private.key
echo "$PUBLIC" > $XRAY_DIR/public.key

echo "Reality ключи созданы"

echo
read -p "Введите имя первого пользователя: " USERNAME

UUID=$($XRAY_DIR/xray uuid)

SHORTID=$(openssl rand -hex 4)

echo "$USERNAME|$UUID|$SHORTID" > $DB

echo "Создаём config.json..."

cat > $CONFIG <<EOF
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
"flow": "xtls-rprx-vision"
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

jq . $CONFIG > /dev/null

echo "Создаём systemd сервис..."

cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=$XRAY_DIR/xray run -config $CONFIG
Restart=on-failure
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xray
systemctl restart xray

sleep 2

echo
echo "Проверяем статус..."

systemctl status xray --no-pager

IP=$(curl -s ifconfig.me)

echo
echo "=============================="
echo "       ГОТОВО"
echo "=============================="
echo

echo "Ссылка подключения:"
echo

echo "vless://$UUID@$IP:443?type=tcp&security=reality&pbk=$PUBLIC&flow=xtls-rprx-vision&sni=www.microsoft.com&sid=$SHORTID#$USERNAME"

echo
echo "users.db:"
cat $DB
echo
