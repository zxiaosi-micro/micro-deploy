#!/bin/bash
# S2-01 · TDengine 首启改默认密码（默认 root/taosdata，必改；幂等）
set -euo pipefail

NEW_PW="${MICRO_DEV_TDENGINE_PW:?MICRO_DEV_TDENGINE_PW 未设置}"
TAOSD_HOST="${TAOS_HOST:-tdengine}"

echo "[tdengine-init] 探测 taosd 就绪..."
for i in $(seq 1 60); do
  if taos -h "$TAOSD_HOST" -u root -ptaosdata -s "show databases" >/dev/null 2>&1; then
    break
  fi
  # 已改过密的情况：用新密码探测
  if taos -h "$TAOSD_HOST" -u root -p"${NEW_PW}" -s "show databases" >/dev/null 2>&1; then
    echo "[tdengine-init] root 密码已为目标值，跳过（幂等）"
    exit 0
  fi
  [ "$i" = 60 ] && { echo "[tdengine-init] taosd 60 次探测未就绪，失败"; exit 1; }
  sleep 2
done

# 仍可用默认密码 → 执行改密；否则视为已改（幂等）
if taos -h "$TAOSD_HOST" -u root -ptaosdata -s "show databases" >/dev/null 2>&1; then
  taos -h "$TAOSD_HOST" -u root -ptaosdata -s "ALTER USER root PASS \"${NEW_PW}\""
  taos -h "$TAOSD_HOST" -u root -p"${NEW_PW}" -s "show databases" >/dev/null 2>&1
  echo "[tdengine-init] root 默认密码已修改并验证通过（REST 6041 Basic 认证同此凭证，E7）"
else
  echo "[tdengine-init] 默认密码已不可用（视为已改密），跳过"
fi
