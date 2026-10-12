# runbook · finance（支付/退款/发票/对账/返利服务）

> 服务：finance ｜ RPC 8092 / metrics 9112 ｜ module `micro-server/services/finance`
> 职责一句话：资金域唯一记账方（payment/refund/invoice/reconcile_task/rebate_settlement），金额分域计算 + 规则快照留痕。
> 关联任务：S5-03 / S10-03 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：finance_db；ConfirmPayment 幂等键 channel_txn_id UK（重复投递=成功语义，chaosmoke case2/3）；支付状态机 CREATED→PAID→SETTLED。

**返利纪律（S10）**：规则快照（rule_raw/base_amount/rate/calc）随结算落库可追溯；ODKU PENDING 守卫（CONFIRMED 后金额锁定不可改）；月度对账 ReconcileRebate 差异 = 0 为验收线。

| 依赖 | 用途 | 超时 | 降级 |
|---|---|---|---|
| MySQL（micro_finance） | 记账 | 3s | 熔断 |
| order 事件（order_paid 等） | 记账触发 | 消费侧 | event_retry 退避 |
| party RPC | 返利规则源 | 5s | 结算失败停靠（人工重推） |

## 2. 健康指标

- RED：`:9112/metrics`；业务：SumByChannelDate 日结 vs 订单侧销售额（tools/reconcile 对账）、PENDING 支付滞留数、rebate 结算差异。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 重复入账疑云 | ConfirmPayment 重放 | UK 幂等即成功语义——核对同一 channel_txn_id 只有一行（正常证据，非 bug） |
| 资金对账差异 | 渠道侧与本地 | reconcile_task 生成处理任务；差异只允许补投递重放修复（NFR-CNS-006） |
| 返利金额争议 | 规则快照回溯 | rebate_settlement.rule_raw 还原当期规则；对账差异跑 ReconcileRebate |
| DECIMAL 显示 [50 48 ...] | database/sql []byte 陷阱 | 展示层走 str() 助手（AGENTS 已知坑，勿当数据损坏） |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc finance up`；启动前置 `source tools/devenv.sh micro_finance`。
- 回滚：二进制回退；记账表 schema 前向兼容（只加列）。

## 5. 紧急操作

- **支付通道故障**：ConfirmPayment 停止调用（通道不可达时本地无脏数据）；PaymentNo 重放安全。
- **发票冲红**：reverse RPC（红字发票，不物理删）。
- **结算错误**：PENDING 阶段可重算；CONFIRMED 只能冲正（快照锁定语义）。
