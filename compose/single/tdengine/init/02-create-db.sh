#!/bin/bash
# 建 IoT 时序库（幂等）；iotingest 建超级表，这里只保证库存在
set -euo pipefail
NEW_PW="${MICRO_DEV_TDENGINE_PW:?MICRO_DEV_TDENGINE_PW 未设置}"
taos -h tdengine -u root -p"${NEW_PW}" -s "CREATE DATABASE IF NOT EXISTS micro_iot"
echo "[02-create-db] micro_iot 就绪"
