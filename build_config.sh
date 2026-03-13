#!/bin/bash
set -e
set -u

DB="/root/xray-panel/bot_db/users.db"
CONFIG="/opt/xray/config.json"

PRIVATE=$(cat /opt/xray/private.key)

CLIENTS="[]"
SHORTIDS="[]"

# =========================
# СОЗДАЕМ CLIENTS JSON
# =========================

while IFS="|" read -r EMAIL UUID SHORTID
do

[ -z "$UUID" ] && continue

CLIENT=$(jq -n \
--arg id "$UUID" \
--arg email "$EMAIL" \
'{
id:$id,
email:$email,
flow:"xtls-rprx-vision"
}')

CLIENTS=$(echo "$CLIENTS" | jq ". + [$CLIENT]")

SHORTIDS=$(echo "$SHORTIDS" | jq ". + [\"$SHORTID\"]")

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

log:{
access:"/var/log/xray/access.log",
error:"/var/log/xray/error.log",
loglevel:"warning"
},

api:{
tag:"api",
services:["StatsService"]
},

stats:{},

policy:{
system:{
statsInboundUplink:true,
statsInboundDownlink:true
}
},

routing:{
domainStrategy:"AsIs",
rules:[
{
type:"field",
inboundTag:["api"],
outboundTag:"api"
}
]
},

inbounds:[

{
listen:"127.0.0.1",
port:10085,
protocol:"dokodemo-door",
settings:{
address:"127.0.0.1"
},
tag:"api"
},

{
port:443,
protocol:"vless",
tag:"vless_tls",

settings:{
clients:$clients,
decryption:"none"
},

streamSettings:{
network:"tcp",
security:"reality",

realitySettings:{
show:false,
dest:"www.microsoft.com:443",
xver:0,

serverNames:[
"www.microsoft.com"
],

privateKey:$private,

shortIds:$shortids
}
},

sniffing:{
enabled:true,
destOverride:[
"http",
"tls"
]
}
}

],

outbounds:[
{
protocol:"freedom",
tag:"direct"
},
{
protocol:"blackhole",
tag:"block"
}
]

}
' > "$CONFIG"


# =========================
# ПРОВЕРКА JSON
# =========================

jq . "$CONFIG" > /dev/null || {

echo "CONFIG ERROR"
exit 1

}


echo "Config rebuilt successfully"

systemctl restart xray
