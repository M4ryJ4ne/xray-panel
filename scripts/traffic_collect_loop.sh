#!/bin/bash
set -u

while true; do
    /root/xray-panel/scripts/traffic_collect.sh || true
    sleep 300
done
