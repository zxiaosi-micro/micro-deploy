# runbook · party（参与方主数据服务）

> 服务：party ｜ RPC 8082 / metrics 9102 ｜ module `micro-server/services/party`
> 职责一句话：参与方（CUSTOMER/DEALER/STATION_OWNER/RECYCLER 等）主数据 + 组织关系 + 商机 + 经销商扩展，全平台业务对象的归属锚点。
> 关联任务：S4-01 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：party_db（party/contact/crm/opportunity/staff/dealer_ext）唯一写入方；S9 requireParty 契约的数据源（mobile 端按 party_id 过滤的过滤位提供方）。

**韧性策略**：读路径 NoCache（租户敏感查询不走主键行缓存）；S10 返利提供 dealer_ext.rebate_rule 规则源（finance RunRebateSettlement RPC 拉取）。

| 依赖 | 用途 | 超时 | 降级 |
|---|---|---|---|
| MySQL（micro_party） | 主数据 | 3s | sqlx 熔断 |
| etcd | 发现/雪花/configcenter | 5s | 后台重试接入 |

## 2. 健康指标

- RED：`:9102/metrics`；业务：party 创建/查询 P95、requireParty 相关 RPC 调用量。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 下游 10408 mustTenant | 调用方 ctx 未带租户 | 调用方补 ctxkit.WithTenant（事件消费/后台任务尤其注意） |
| S10 返利结算 41004 | dealer_ext.rebate_rule 缺失 | `PUT /parties/:id/dealer-ext` 维护规则后重跑结算 |
| 手机号查重冲突 | mobile_hash（HMAC 索引）唯一键 | 加密列由 MICRO_DATA_KEYS/MICRO_HASH_KEY 派生——密钥环境变量不一致会全量查重失效 |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc party up`；回滚二进制即可（schema 前向兼容）。
- 启动前置：`source tools/devenv.sh micro_party`（注意 yaml 占位符是 `${DSN|}`——单起时 export DSN）。

## 5. 紧急操作

- 参与方删除为软删（deleted_at）；误删恢复走 SQL 直改（走变更审批）。
- party_id 是全平台外键锚点：禁物理删除（含 RECYCLER 类型的回收单引用）。
