# runbook · identity（认证与账号服务）

> 服务：identity ｜ RPC 8081 / metrics 9101 ｜ module `micro-server/services/identity`
> 职责一句话：登录/登出/刷新/踢人/step-up 的**唯一会话写入方**（Redis DB4）+ 账号/角色/组织/菜单/租户管理。
> 关联任务：S3-01~05 ｜ 最近更新：2026-10-08

## 1. 职责与依赖

**职责边界（02 §9.5 / ADR-11）**：MySQL 只存"账号是什么"（8 表：tenant/user/org/role/menu/user_role/role_menu/user_sso_binding）；会话/锁定计数/权限快照在 Redis DB4（sessionx）。BFF（admin-bff 等）每请求 GET auth_cache 做鉴权，identity 是 auth_cache 的唯一写入方与刷新源。

**上下游依赖**（出站依赖，对应 02 §10 韧性策略表 identity 行）：

| 依赖 | 用途 | 超时预算 | 重试 | 熔断/降级 |
|---|---|---|---|---|
| MySQL（micro_identity 库） | 账号数据 | 5s 建连/3s 查询 | sqlx 内置 | 登录链不可降级（fail-closed 报 110500） |
| Redis DB4 | 会话/锁定/auth_cache | 3s Ping（启动期硬依赖） | go-redis 内置 | 启动期连不通直接 panic（fail-fast）；运行期 authz 侧 fail-open ≤30min |
| etcd | 服务注册 + 雪花 worker_id 分配 | 5s | — | snowflake 退化 `MICRO_WORKER_ID` 环境变量（单实例） |
| Kafka（audit_event topic） | auth.login 审计事件投递 | outbox 异步 | Relay 退避 ≤16 次 | Relay 未落地前事件仅落 outbox 表（PENDING），无下游影响 |
| 微信 jscode2session | LoginByWechat | 5s HTTP | 无（用户重试） | 未配置 Wechat.* 时返回 1101013 |

## 2. 健康指标

- **RED**（Prometheus，`http://<host>:9101/metrics`，go-zero 内置）：
  - QPS：`micro_server_rate`（按 method/service 维度）
  - 错误率：`micro_server_http_code_total` 中非 0 code 占比
  - P99：`micro_server_latency_bucket`
- **关键业务指标**（S7 运维域接入自定义埋点后补齐）：
  - `micro_identity_login_total{result=ok|credential_error|locked}`（登录结果分布；credential_error 突增 = 撞库告警信号）
  - `micro_identity_session_active`（Redis ZSET uid_sessions 总量，近似在线数）
- **Grafana 看板**：官方市场 go-zero 看板（Grafana ID 19909，Grafana :3000 → Dashboards → go-zero overview），按 `service="identity.rpc"` 过滤。
- **健康端点**：RPC 服务无 /healthz（BFF 深检归 BFF）；探活口径 = TCP 8081 可建连 + metrics 9101 有输出。登录链自检：`ValidateSession` RPC 冒烟。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 登录全量 110503（登录服务暂不可用） | Redis DB4 不通——identity 启动期 Ping 失败会 panic；运行期 CheckLocked 报错 | `docker ps` 查 micro-dev-redis；恢复后 identity 自动重连（sessionx 池化），无需重启 |
| 登录 10400 突增 | Loki 按 `service="identity"` + trace_id 检索登录日志；确认是撞库还是改密 | 撞库：观察 `login_fail:*` 计数（Redis DB4），必要时联系安全侧封 IP；确认无密码策略变更 |
| 用户投诉"被踢下线"（10402） | Jaeger :36686 按 trace_id 查登录链路；Redis `mutex:{uid}:{client}` 当前指向 | 互斥属正常行为（QQ 模式同端互顶）；若非本人操作 → 走会话管理页踢全部 + 重置密码 |
| 刷新报 10403 且伴随 ERROR 告警日志 `[安全告警] refresh token 重用` | 日志含 rtid 前缀；属重放攻击防御（RotateRefresh 墓碑命中已全端注销） | 确认该用户（日志 uid）全部会话已注销；通知用户重新登录；评估是否 token 泄漏 |
| 所有验签 10401（BFF 侧） | JWT kid 不在公钥集合——检查 `JWT_KEYS_DIR/keys.json` 与 identity 启动日志 kid 是否一致 | keys.json/公钥文件与 identity 同步后**仅重启 BFF**（identity 私钥不动）；见 §5 kid 轮换 |
| 雪花 ID panic `worker_id 无可用来源` | etcd 不可达且未设 MICRO_WORKER_ID | 临时：设 MICRO_WORKER_ID=<0~1023> 重启；根治：恢复 etcd 连通 |
| step-up 后仍 10406 | BFF 的 SensitivePrefixes 匹配了新路由但用户 access 是 level=1 旧 token | 前端 step-up 成功后必须用返回的新 access token 替换本地值（auth.ts 已实现）；确认 /auth/step-up 走的是免鉴权组 |

**排障入口**：Jaeger UI :36686（按 trace_id）｜ Loki（按 service/trace_id）｜ Redis DB4 直查（会话/锁定/墓碑）｜ MySQL micro_identity（账号事实）。

## 4. 发布与回滚

**发布步骤**（S3-05 口径，全服务通用示范）：

```
# 1) 迁移（up/down 成对；只前向兼容，先发布后迁移的两阶段纪律）
go run ./tools/migrate -svc identity up

# 2) 种子（幂等；仅新环境需要；MICRO_ADMIN_PW 必须强密码）
go run ./tools/seed

# 3) 本地/容器启动
go run ./services/identity -f services/identity/etc/identity.yaml
# 容器化：goctl docker --go 1.26 --port 8081 && docker build ...

# 4) 验证
#    - metrics 9101 有输出、日志 "identity 就绪：kid=..."
#    - BFF 侧登录冒烟：POST /api/v1/auth/login → /auth/me → /auth/menus
```

**迁移注意**：迁移 SQL 是表结构唯一事实源（ADR-08）；up/down 必须成对；goctl model 重生成只写 `_gen.go`，custom 覆写文件不碰。加列走新迁移文件（000004_...），禁改历史迁移。

**回滚口径**：
- 代码：回滚镜像/二进制即可（表结构前向兼容保证旧代码可跑）；
- 迁移：`go run ./tools/migrate -svc identity down -steps 1` **仅在无数据写入风险的空窗执行**（down 会删表删列）；生产回滚以"回滚代码不回滚库"为默认。

## 5. 紧急操作

- **降级开关（configcenter）**：identity 暂无运行时开关（ConfigKey `/micro/config/identity` 预留，S4 起消费）。紧急止血 = 重启 identity（会话在 Redis，重启不丢登录态）。
- **kill 开关**：紧急封禁某账号 → 管理后台用户管理禁用（即时踢全部会话 + auth_cache 失效）；无法进后台时：
  `redis-cli -n 4` → `SET mutex:{uid}:ADMIN_WEB ""` + 逐 `sess:{sid}` DEL（人工踢会话，事后补审计）。
- **人工介入队列**：outbox 表 `event_outbox`（status=PENDING/FAILED）= 未投递审计事件；Relay 恢复后自动重投，无需人工搬运（E10：禁裸删，处置走补投递重放）。

### kid 轮换流程（RotateKey，ADR-11）

JWT header.kid = SHA-256(SPKI DER) 前 16 hex（keygen 产出并写入 keys.json）。**新钥入集合 → 发新 token → 观察期移旧钥**：

1. **生成新钥**：`go run ./tools/keygen -force`（产出新 kid + jwt_rs256_private/public.pem，覆盖目录内同名文件前**先把旧公钥改名为 `jwt_rs256_public_<oldkid>.pem` 留存**）。
2. **新钥入集合**：编辑 keys.json，`jwt.kid` 指向新 kid；identity 重启后即以新 kid 签发。
3. **验签方扩展**：所有 BFF 的 keys.json 同步加入新公钥（旧公钥 PEM 保留在目录内）→ BFF 重启，多公钥集合新旧并存（`jwtauth.Verifier.RegisterKey` 语义）。
4. **观察期（≥ access TTL 30min，建议 24h）**：旧 token 自然过期/刷新耗尽。Grafana 观察 BFF 验签失败率（10401 占比）回落基线。
5. **移旧钥**：观察期后从各 BFF keys.json 删除旧 kid 条目并重启；identity 侧旧公钥 PEM 归档出目录。
6. **回滚**：任一步验签失败率异常 → 恢复旧 keys.json 重启 BFF（identity 私钥未动，旧 kid 仍可验）。

> 纪律：私钥永不入库（E11）；轮换全程 identity 不丢会话（会话在 Redis 与 kid 无关），用户无感。
