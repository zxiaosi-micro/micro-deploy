# runbook · ops（运维工单与告警服务）

> 服务：ops ｜ RPC 8094 / metrics 9114 ｜ module `micro-server/services/ops`
> 职责一句话：告警生命周期（候选→聚合→闭环）/工单状态机/SLA 计时挂钩/巡检计划与执行。
> 关联任务：S7-01~04 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：ops_db（alert/alert_rule/ticket/ticket_log/sla_timer/inspection_*）；alert_created 事件的生产方（analytics 读模型消费）。

**纪律**：工单创建统一走 createTicketCore（工单号 TK+日期+雪花尾段、TenantId、PENDING_DISPATCH 三件齐——绕过直插会炸 1062 重号/91007/91008）；JSON 列写入空串必炸 3140（nullif 模式）；alert.created 事件 Payload 传 map（预序列化 []byte 触发信封 base64 坑）。

| 依赖 | 用途 | 超时 | 降级 |
|---|---|---|---|
| MySQL（micro_ops） | 全部 | 3s | 熔断 |
| Kafka（alert_candidate 消费 + alert_created 生产） | 告警链 | 消费侧 | event_retry 退避 |
| contract RPC | SLA 绑定 | 5s | 扫描重试 |
| notification RPC | 订阅消息触达 | 5s | 触达失败留日志（告警本体不受影响） |

## 2. 健康指标

- RED：`:9114/metrics`；cron：`ticket_accept_timeout`（30s）/ `sla_breach_scan`（30s）/ `inspection_task_generate`（1m）。
- 业务：event_dead 数、告警闭环时长、工单超时升级量、p3smoke 口径闭环率。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 告警未生成 | alert_candidate 消费滞后 / 越限规则未命中 | iotingest 规则键 `/micro/config/iotingest/rules` 核对；ops 消费组 lag |
| 告警未聚合 | fingerprint 归并逻辑 | AggHitTx 聚合链（S11-01 登记豁免注释处）核对 |
| 工单 91008 状态机拒绝 | 非法转移 | ticket_log 留痕核对；人工驳回重派 |
| 巡检任务未生成 | inspection_plan enabled/next_exec_at | cron 补跑语义（E16）；计划配置核对 |
| Outbox 轮询 1054 连累 RPC | alert 表缺列（last_error 教训） | 四表以 eventbus/schema.go 为正本补迁移，重启复位熔断 |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc ops up`（含 000003 ticket.party_id）；启动前置 `source tools/devenv.sh micro_ops`。

## 5. 紧急操作

- **告警风暴抑制**：alert_baseline.yml（configcenter）调聚合窗口/阈值，推送秒级生效。
- **SLA 升级电话误触达**：notification 侧分级通道核对（电话/短信/企微）。
- **巡检误生成**：任务作废（状态机 REJECTED）不物理删。
