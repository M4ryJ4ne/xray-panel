#!/bin/bash
set -euo pipefail

while true; do
    /root/xray-panel/scripts/traffic_collect.sh
    sleep 300
done
