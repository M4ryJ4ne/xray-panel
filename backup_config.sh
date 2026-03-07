#!/bin/bash

cp /opt/xray/config.json.bak /opt/xray/config.json
systemctl restart xray
