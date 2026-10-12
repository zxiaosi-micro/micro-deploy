# runbook · order（订单与 Saga 编排服务）

> 服务：order ｜ RPC 8090 / metrics 9110 ｜ module `micro-server/services/order`
> 职责一句话：下单/支付/出库/建站/激活的 Saga 编排器（saga+outbox+cron 自研状态机，ADR-03），交易链路（NFR-AVL-001 99.9%）的枢纽。
> 关联任务：S5-01~05 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：order_db（order/order_item/saga/shipment*/return_*）；Saga 步骤推进的唯一协调者。支付单/质保/场站都在下游域，order 只持状态机。

**Saga 纪律**：扫描推进按归属租户重建 ctx（`tenantx.Skip` 扫描 + `ctxkit.WithTenant` 调下游，否则 10408）；下游业务码判定用 `errcode.FromError`（FromGRPC 二次解析恒失败）。

| 依赖 | 用途 | 超时 | 降级 |
|---|---|---|---|
| inventory RPC | 锁库存/释放 | 5s | Saga 停靠（next_retry_at 退避） |
| finance RPC | 支付单 | 5s | 同上 |
| contract RPC | 合同/质保 | 5s | 同上 |
| station RPC | 建站 | 5s | 同上 |
| Kafka | order_created/paid/... 事件 | 同事务 Outbox | Relay 退避 |

## 2. 健康指标

- RED：`:9110/metrics`；cron：`order-pay-timeout-scan`（30s）/ `order-saga-retry-scan`（30s）/ `order-saga-manual-queue-watch`（1m 积压日志）。
- 业务：saga status=RUNNING 且 next_retry_at 越界堆积（drill -case station 可观测 E16 语义）；PENDING 支付超时取消量。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 下单后 PayOrder 报 51003 | Saga 锁库存由 cron 30s 推进，CREATED 不可支付 | 端侧有界等待（mobile-bff payWhenLocked 40s）；e2esmoke waitFor 同款 |
| Saga 停靠不推进 | 下游停机 / cron 停摆 | 看 saga.last_error 定位步骤；下游恢复后 30s 内自动续推（drill 验证）；顽固单人工 RetrySaga |
| 支付确认后订单不动 | order_paid 消费/事件链断裂 | 查 event_outbox SENT 状态 + finance ConfirmPayment 幂等键（chaosmoke case2/3 口径） |
| 并发抢同 SKU 超卖疑云 | inventory 守卫 | available ≥ 0 断言（chaosmoke case6）；order 侧无库存逻辑 |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc order up`；启动前置 `source tools/devenv.sh micro_order`。
- 回滚：二进制回退；saga 行兼容历史版本状态机（新增步骤只加不改，前向兼容纪律）。

## 5. 紧急操作

- **人工重推**：`RetrySaga`（remark 留痕）；幂等由步骤幂等键（saga_id+step，NFR-CNS-002）保证。
- **支付超时批量**：pay-timeout 扫描自动取消；误取消走重下单（不做复活）。
- **编排器雪崩**：Saga 停靠是安全态（本地事务已提交），恢复只补推进不回滚——先修下游再等扫描。
