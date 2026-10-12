# runbook · inventory（库存服务）

> 服务：inventory ｜ RPC 8084 / metrics 9104 ｜ module `micro-server/services/inventory`
> 职责一句话：仓库/库存台账/流水/盘点，Redis 原子预扣网关 + DB 行锁双保险防超卖（NFR-CNS-003）。
> 关联任务：S4-03 / S5-02 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：inventory_db + Redis 预扣；FIFO 批次库存（冒烟严禁并发 E1 的原因：共享库存池交叉消耗）。

**网关纪律**：Redis 预扣拒绝必须显式短路（gateReject）——不能落 DB 路径以业务错误返回，否则 sqlx 熔断器把业务错误计入失败率，并发拒绝风暴误开熔断（AGENTS 已知坑）。

| 依赖 | 用途 | 超时 | 降级 |
|---|---|---|---|
| MySQL（micro_inventory） | 台账/流水 | 3s | 熔断 |
| Redis | 原子预扣（Lua） | 500ms | Redis 故障降级纯 DB 路径（同样安全，NFR-CNS-003） |
| 事件生产 | stock_in/stock_out/stock_low → Kafka | 同事务 Outbox | Relay 退避 ≤16 次 |

## 2. 健康指标

- RED：`:9104/metrics`；cron：`inventory-redis-reconcile`（30s，Redis 预扣 vs DB 台账对账）last_run 停摆即告警。
- 业务：available 负值（=超卖征兆，零容忍）、预扣-台账差异计数。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| circuit breaker is open | 预扣拒绝风暴计入熔断（gateReject 短路缺失时） | 检查 Redis 预扣网关是否显式短路；服务重启复位熔断 |
| 库存差异 | Redis/DB 漂移 | cron 对账自动修；超差走盘点（stocktake approve） |
| 预扣成功但订单取消未释放 | Saga failCancel 缺口 | available 还原断言（drill -case inventory）+ p4backfill 不适用（非事件问题）——按单号人工核对流水 |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc inventory up`；启动前置 `source tools/devenv.sh micro_inventory`。
- 回滚：二进制回退；Redis 预扣键带版本时回滚需清预扣键（与 cron 对账配合）。

## 5. 紧急操作

- **熔断复位**：重启服务（sqlx 熔断随进程）。
- **冻结出库**：紧急情况下置 SKU 库存 available=0（预扣天然拒绝）——比停机影响小。
- 盘点差异审批：approve 后台账校准，流水留痕。
