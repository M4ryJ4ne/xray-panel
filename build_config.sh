#!/bin/bash

DB="/root/xray-panel/users.db"
CONFIG="/opt/xray/config.json"

PRIVATE=$(cat /opt/xray/private.key)

CLIENTS=""
SHORTIDS=""

FIRST=1

while IFS="|" read -r EMAIL UUID SHORTID
do

[ -z "$UUID" ] && continue

if [ $FIRST -eq 0 ]; then
CLIENTS+=","
SHORTIDS+=","
fi

CLIENTS+="
{
\"id\":\"$UUID\",
\"email\":\"$EMAIL\",
\"flow\":\"xtls-rprx-vision\"
}
"

SHORTIDS+="\"$SHORTID\""

FIRST=0

done < "$DB"

cp $CONFIG $CONFIG.bak

cat > $CONFIG <<EOF
{
"log":{
"access":"/var/log/xray/access.log",
"error":"/var/log/xray/error.log",
"loglevel":"warning"
},

"inbounds":[

{
"listen":"127.0.0.1",
"port":10085,
"protocol":"dokodemo-door",
"settings":{
"address":"127.0.0.1"
},
"tag":"api"
},

{
"port":443,
"protocol":"vless",
"tag":"vless_tls",

"settings":{
"clients":[
$CLIENTS
],
"decryption":"none"
},

"streamSettings":{
"network":"tcp",
"security":"reality",

"realitySettings":{
"show":false,
"dest":"www.microsoft.com:443",
"xver":0,

"serverNames":[
"www.microsoft.com"
],

"privateKey":"$PRIVATE",

"shortIds":[
$SHORTIDS
]
}
},

"sniffing":{
"enabled":true,
"destOverride":[
"http",
"tls"
]
}
}

],

"outbounds":[
{
"protocol":"freedom",
"tag":"direct"
},
{
"protocol":"blackhole",
"tag":"block"
}
]
}
EOF

jq . $CONFIG > /dev/null || { echo "CONFIG ERROR"; exit 1; }

echo "Config rebuilt successfully"

systemctl restart xray
