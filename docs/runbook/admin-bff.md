# runbook · admin-bff（管理后台聚合网关）

> 服务：admin-bff ｜ HTTP 8889 / metrics 9118 ｜ module `micro-server/services/admin-bff`
> 职责一句话：admin/dealer/station 三 Web 端唯一聚合入口（HTTP 面），鉴权/权限/限流在边缘收敛，下游 15 个 RPC 域聚合转发。
> 关联任务：S3-03 起 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：无数据库、无事件；只做 token 验签 → RBAC（routePerms 权限码表）→ RPC 转发 + 信封统一（{code,msg,data}）。行级数据隔离由下游域服务保证（BFF 不做二次过滤）。

**韧性策略**：全局 Use 链 = BearerProbe（免鉴权组）→ QuotaMW（租户 RPM 分钟桶 429，S11-01）→ 路由级 authz（会话 + auth_cache 每请求 GET，Redis 故障 LRU 兜底 fail-open ≤30min 告警；控制/财务类 fail-close——NFR-AVL-005）。

| 依赖 | 用途 | 超时预算 | 降级 |
|---|---|---|---|
| identity RPC | 登录/用户/租户/配额源（ListTenants 60s 缓存） | 8s | 限流 fail-open（配额源拉取失败短退避） |
| sessionx Redis DB4 | 会话校验 + auth_cache | 3s | LRU 兜底 + 降级告警 |
| 14 个域 RPC | 业务转发 | 8s | 下游熔断按 go-zero 内置 |

## 2. 健康指标

- RED：`http://<host>:9118/metrics`；健康：`GET /api/v1/healthz`（deep：identity + tdengine）。
- 业务观测：auth_cache 命中率（authz 指标）；429 计数（X-RateLimit 触发量）；各下游 RPC P95。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 全部请求 403 | auth_cache 空 / Redis 故障 fail-close 面 | Redis 健康；看 authz 降级告警日志；必要时重启恢复 LRU 预热 |
| 误伤 429 | 租户配额（quota JSON {"rpm":N}）过紧 | identity `PUT /tenants/:id/quota` 调整；生效 ≤60s（配额源 TTL） |
| 下游超时雪崩 | 某域 RPC 停机 | Jaeger 按 trace_id 定位域；下游服务按其 runbook 恢复 |
| swagger 与实现漂移 | 契约未重生成 | `make swagger` 重生成提交（CI diff 阻断） |

## 4. 发布与回滚

- 无迁移；`.api` 契约变更走生成流水线（validate → swagger → apitypes → build/vet/lint）。
- 启动前置：`source tools/devenv.sh micro_identity`（JWT_KEYS_DIR/会话 Redis 必需）。
- 回滚：二进制/镜像回退上一版本；routes.go 生成物随契约回退。

## 5. 紧急操作

- **限流全停**：无独立开关——将所有租户 quota 清空（`PUT /tenants/:id/quota` 空 JSON）即全量放行（default 语义）。
- **踢会话**：`POST /sessions/kick`（system:session:kick）。
- **降级排查**：authz 降级告警（DegradeHook 日志）→ Redis DB4 连通性。
