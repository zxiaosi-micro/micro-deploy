#!/bin/bash
# 单机版 tdengine 初始化：01 改密（dev 正本脚本）+ 02 建 micro_iot 库（幂等）
set -euo pipefail
bash /init/01-change-password.sh
bash /init/02-create-db.sh
