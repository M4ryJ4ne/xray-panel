#!/bin/bash
set -u

while true; do
    /root/xray-panel/scripts/devices_collect.sh || true
    sleep 5
done
