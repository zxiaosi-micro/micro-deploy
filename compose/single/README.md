# compose/single · 单机全量部署（4C4G 演示/体验环境）

把两阶段 prod 编排（ECS-1 应用 + ECS-2 数据）合并到**一台 4C4G** 的单机：29 容器常驻
（7 中间件 + APISIX/Web 边缘 + 18 服务），砍掉可观测六件套，全部容器加 mem_limit + 4G swap 兜底。

## 与 prod 编排的组网差异

- **单网络**：etcd 广播 / Kafka advertised / BFF 的 `*_RPC` 直连全走容器名（etcd 广播坑的单机正解）
- **镜像本地构建**：无 CI/ghcr 时，本机交叉编译（`CGO_ENABLED=0 GOOS=linux GOARCH=amd64`）+
  极简 alpine Dockerfile，scp 后服务器 `docker build`；工具箱同理（migrate/seed/configpush/mqinit/envcheck → micro-tools:s1）
- **MySQL/Redis/MinIO/TDengine 容器化**（prod 用云托管），密码体系与 dev `.env` 同源（`MICRO_DEV_*`）

## 用法（服务器 /opt/micro/）

```bash
# 0) 目录布局：compose/single/{docker-compose.yml,.env,...} + web/{admin,dealer,station} + config/ + keys/ + img/ + bin/ + migrations/
cp compose/single/.env.example compose/single/.env   # 填真实密钥（不入库）

# 1) 中间件
cd compose/single && docker compose up -d mysql redis etcd tdengine tdengine-init kafka emqx emqx-bootstrap minio minio-init

# 2) 数据层（工具箱容器跑，--env-file 读同目录 .env）
for s in identity party catalog inventory file audit notification order finance contract device station ops analytics hello; do
  docker run --rm --network micro-net --env-file .env -v /opt/micro/migrations:/m:ro micro-tools:s1 /t/migrate -svc $s -dir /m/$s up
done
docker run --rm --network micro-net --env-file .env micro-tools:s1 /t/seed
docker run --rm --network micro-net --env-file .env -v /opt/micro/config:/cfg:ro micro-tools:s1 /t/configpush -dir /cfg
docker run --rm --network micro-net --env-file .env micro-tools:s1 /t/mqinit -brokers kafka:9092

# 3) 全量拉起 + APISIX 路由（IP 直访场景）
docker compose up -d
source .env && APISIX_ADMIN=http://127.0.0.1:9180 APISIX_KEY=$MICRO_DEV_APISIX_ADMIN_KEY bash apisix-ip-routes.sh
```

## 端口面与访问地址（2026-10-14 TLS 收编后）

公网入口收敛到 **443 单端口**（DigiCert DV 证书 `zxiaosi.cn`/`www`，DNS 已指本机；证书在 `certs/`，不入库）：

| 地址 | 内容 |
|---|---|
| https://zxiaosi.cn/admin/ | 管理后台（登录：种子管理员 mobile `13800000000` + `MICRO_ADMIN_PW`） |
| https://zxiaosi.cn/dealer/ | 经销商端 |
| https://zxiaosi.cn/station/ | 场站端 |
| https://zxiaosi.cn/api/v1/* | admin-bff API（三端 Web 同源调用；`/` 302 → /admin/） |
| https://zxiaosi.cn/mapi/* | mobile-bff API（小程序/运维 App base URL 指这里，nginx 前缀改写 `/mapi/*` → `/api/v1/*`） |
| http://<IP>/ (80) | APISIX API 边缘（保留，默认路由 → admin-bff） |
| 1883 | EMQX MQTT（设备侧） |
| 3306/6379/2379/6041/9000/9001/18083 | 仅回环（127.0.0.1 发布，运维排障用） |

8080-8083 端口面已收编至 443（原三端 :8080-8082 与 mobile :8083 停用）。三端为极简 hash 路由，
路径挂载仅要求 **vite 构建带 base**（`pnpm --filter ./apps/<x> exec vite build --base=/admin/` 等）；
Git Bash 下必须 `MSYS2_ARG_CONV_EXCL="*" MSYS_NO_PATHCONV=1` 前缀，否则 `/admin/` 被 MSYS 路径转换改写成本机 Git 安装路径。

## 已知边界（2026-10-14 实测）

- 登录：`POST /api/v1/auth/login {mobile:"13800000000", password:$MICRO_ADMIN_PW}`（种子管理员，MOCKWX=1 微信链路可用）
- 分页参数是 `page`/`size`（不是 page_size）；请求缺参报 500 fallback 而非 110400（SetBadRequestClassifier 未覆盖 parse 错误，历史行为）
- S4 菜单迁移绑 admin 角色时 `menu_id>=...201` 范围过滤漏掉 S3 的 25 个 `system:*` 菜单——已由
  identity 迁移 000011 修复（admin × 全部菜单幂等绑定，2026-10-14 已应用验证）
- OTLP 链路无 Jaeger：服务日志周期性 otel export timeout 属预期噪声
