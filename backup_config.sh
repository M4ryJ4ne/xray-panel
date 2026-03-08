#!/bin/bash
set -e
set -u

cp /opt/xray/config.json.bak /opt/xray/config.json
systemctl restart xray
