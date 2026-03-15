#!/bin/bash
set -euo pipefail

while true; do
    /root/xray-panel/scripts/devices_collect.sh
    sleep 5
done
