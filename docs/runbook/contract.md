# runbook · contract（合同/质保/SLA/索赔服务）

> 服务：contract ｜ RPC 8093 / metrics 9113 ｜ module `micro-server/services/contract`
> 职责一句话：合同归档/质保台账（事件驱动起算）/SLA 策略与计时/索赔/延保，质保到期扫描的责任方。
> 关联任务：S5-04 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：contract_db（contract/warranty/sla_*/claim/warranty_extension）；warranty.status 起算由 shipment_signed 事件驱动（PENDING→ACTIVE）。

**SLA 计时**：sla_timer 由工单事件驱动（ops → contract），违约判定 `sla_breach_scan` cron；升级动作回写 ops。

| 依赖 | 用途 | 超时 | 降级 |
|---|---|---|---|
| MySQL（micro_contract） | 台账 | 3s | 熔断 |
| Kafka（shipment_signed/warranty_started 等） | 质保起算 | 消费侧 | event_retry 退避 |
| ops RPC | SLA 升级回写 | 5s | 扫描下一轮重试 |

## 2. 健康指标

- RED：`:9113/metrics`；cron：`contract-warranty-expiry-scan`（1m）last_run 停摆即告警。
- 业务：PENDING 质保滞留（起算事件未到）、sla_timer 违约未升级数。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 质保未起算 | shipment_signed 未发/消费失败 | order 侧查出库状态；event_retry 表看退避；p4backfill 兜底 |
| 到期质保未 EXPIRED | cron 停摆 | last_run 对账；恢复后首轮补跑（drill -case cron 验证 E16） |
| SLA 违约未升级 | sla_breach_scan 停摆 / ops 回写失败 | 扫描重试；ops 侧工单状态机核对 |
| requireParty 查不到质保 | buyer_party_id 过滤位缺失 | contract.ListContractReq.buyer_party_id 契约（S9-01）核对 |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc contract up`；启动前置 `source tools/devenv.sh micro_contract`。

## 5. 紧急操作

- 质保状态人工修正：SQL 直改走审批（status 机 PENDING/ACTIVE/EXPIRED/REFUNDED）。
- SLA 计时暂停/恢复：paused_at 语义（计时窗口豁免）。
- 索赔争议：claim 审批流留痕，禁止绕过 approve 直接 settle。
