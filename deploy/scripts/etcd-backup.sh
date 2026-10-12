#!/bin/bash
# etcd-backup.sh · etcd snapshot 定时备份（S11-05，NFR-AVL-003 配套：etcd 承载
# 服务发现/configcenter/APISIX 正本，丢失=全链不可发现）。
#
# 背景：etcd 官方 3.7 镜像是 distroless（无 shell），compose 内无法跑循环备份容器——
# 标准做法 = 宿主 cron（install 模式，etcdctl 以 exec 形式免 shell 跑）；
# 有 etcdctl 的环境可用 loop 模式常驻。
#
# 模式：
#   install  打印可复制的 crontab 行（snapshot 每 6h 保留 28 份 + 滚动清理），部署时执行
#   run      单次 snapshot（cron 调用 / 手动验证）
#   loop     常驻循环（宿主机有 etcdctl 时可用：INTERVAL 默认 6h）
#
# 环境变量：ETCDCTL（默认 etcdctl）、ENDPOINT（默认 http://127.0.0.1:2379）、
#           BACKUP_DIR（默认 /var/backups/micro-etcd）、KEEP（保留份数，默认 28 = 7 天 × 4）
# 恢复：etcdctl snapshot restore <file> --data-dir=<new-dir> 后按原 command 起新 etcd（runbook identity.md §5 同款语义）。
set -u

ETCDCTL="${ETCDCTL:-etcdctl}"
ENDPOINT="${ENDPOINT:-http://127.0.0.1:2379}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/micro-etcd}"
KEEP="${KEEP:-28}"

snapshot_once() {
  mkdir -p "$BACKUP_DIR"
  local file="$BACKUP_DIR/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db"
  if ETCDCTL_API=3 "$ETCDCTL" --endpoints="$ENDPOINT" snapshot save "$file"; then
    echo "[etcd-backup] $(date -Iseconds) saved $(basename "$file") ($(du -h "$file" 2>/dev/null | cut -f1))"
    ls -1t "$BACKUP_DIR"/etcd-snapshot-*.db 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
      rm -f "$old"
      echo "[etcd-backup] pruned $(basename "$old")"
    done
  else
    echo "[etcd-backup] $(date -Iseconds) SNAPSHOT FAILED endpoint=$ENDPOINT" >&2
    return 1
  fi
}

case "${1:-install}" in
  run)
    snapshot_once
    ;;
  loop)
    snapshot_once || true
    while true; do
      sleep "${INTERVAL:-6h}"
      snapshot_once || true
    done
    ;;
  install)
    # 宿主 cron 版：snapshot 用 docker exec 形式（免宿主 etcdctl），清理用 docker run alpine（busybox find）
    SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    cat <<'EOF'
# --- etcd snapshot 定时备份（S11-05）· crontab -e 后粘贴 ---
# 每 6h 快照（etcd 容器内 etcdctl exec 形式，免 shell；产物落 named volume micro-prod-data_etcd-backups）
0 */6 * * * docker run --rm --network micro-prod-data-net -v micro-prod-data_etcd-backups:/backups quay.io/coreos/etcd:v3.7.0 etcdctl --endpoints=http://etcd:2379 snapshot save "/backups/etcd-snapshot-$$(date +%Y%m%d-%H%M%S).db" >> /var/log/micro-etcd-backup.log 2>&1
# 滚动清理：保留最近 28 份（busybox find，按修改时间取旧删除）
30 */6 * * * docker run --rm -v micro-prod-data_etcd-backups:/backups alpine:3.21 sh -c 'cd /backups && ls -1t etcd-snapshot-*.db 2>/dev/null | tail -n +29 | xargs -r rm -f' >> /var/log/micro-etcd-backup.log 2>&1
# --- 备份行结束 ---
EOF
    echo ""
    echo "dev 环境差异：--network micro-dev-net -v micro-dev_etcd-backups:/backups、endpoint http://etcd:2379（或 127.0.0.1:22379 走宿主映射）。"
    echo "有原生 etcdctl 的环境可直接：$SELF loop（systemd/计划任务托管）。"
    ;;
  *)
    echo "用法: $0 {install|run|loop}" >&2
    exit 1
    ;;
esac
