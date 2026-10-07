#!/bin/bash
# S2-01 · MySQL 首启建应用账号（docker-entrypoint-initdb.d 仅在数据卷为空的首启执行）
# 说明：任务正本写的 01-app-user.sql 无法读取环境变量注入密码（E11 禁止硬编码入库），
#       故以 sh 包装执行 SQL——SQL 语句与任务口径一致：建应用账号 + 授权 micro_% 库。
set -euo pipefail

APP_USER="${MICRO_DEV_MYSQL_APP_USER:?MICRO_DEV_MYSQL_APP_USER 未设置}"
APP_PW="${MICRO_DEV_MYSQL_APP_PW:?MICRO_DEV_MYSQL_APP_PW 未设置}"

mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<SQL
-- 应用账号：服务/迁移/种子全部用它连库（root 仅人工运维）
CREATE USER IF NOT EXISTS '${APP_USER}'@'%' IDENTIFIED BY '${APP_PW}';
-- micro_%：库名约定 micro_<svc>（micro_identity/micro_order/...，tools/migrate 自动建库）。
-- 通配符授权使新库无需再次 GRANT（E12 少一步人工）。
GRANT ALL PRIVILEGES ON \`micro_%\`.* TO '${APP_USER}'@'%';
-- 迁移需要建表/改表（CREATE/ALTER 已含于 ALL），补建库权限的显式口径由 db 级通配覆盖
FLUSH PRIVILEGES;
SQL

echo "[01-app-user] 应用账号 ${APP_USER} 就绪，已授权 micro_%.*"
