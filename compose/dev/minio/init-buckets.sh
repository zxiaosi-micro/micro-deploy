#!/bin/bash
# S2-02 · MinIO init（一次性，幂等建双桶：micro-file / micro-contract）
# 合同桶开版本控制（v4/02 §6.5：micro-contract 版本控制，归档件按版本追溯）
set -euo pipefail

ALIAS="local"
ENDPOINT="http://minio:9000"
mc alias set "$ALIAS" "$ENDPOINT" "${MICRO_DEV_MINIO_ROOT_USER:?}" "${MICRO_DEV_MINIO_ROOT_PASSWORD:?}" >/dev/null

mc mb --ignore-existing "$ALIAS/micro-file"
mc mb --ignore-existing "$ALIAS/micro-contract"
mc version enable "$ALIAS/micro-contract" || true   # 已启用时报错，忽略（幂等）

echo "[minio-init] 双桶就绪：micro-file（普通文件）/ micro-contract（合同归档，版本控制开启）"
