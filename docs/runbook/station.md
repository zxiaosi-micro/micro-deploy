# runbook · station（场站服务）

> 服务：station ｜ RPC 8091 / metrics 9111 ｜ module `micro-server/services/station`
> 职责一句话：场站主数据/设备绑定/驻场人员/拓扑版本化的**唯一写入方**（station_db）+ 建站 Saga 步骤 6 对端。
> 关联任务：S6-02 ｜ 最近更新：2026-10-10

## 1. 职责与依赖

**职责边界**：station_db 全部表（station/station_device/station_staff/station_topology）归本服务；CreateStation 是 order Saga 步骤 6 的对端（幂等键 `tenant_id+order_no`——同订单重放返回已有场站，FR-STN-003）；station_created 事件（ops S7 消费建巡检计划）。设备归属变更走 device 服务生命周期，本服务只写绑定关系。影子监控聚合只读 Redis `micro:iot:shadow:{sn}`（writer=iotingest）。

**上下游依赖**：

| 依赖 | 用途 | 超时预算 | 重试 | 熔断/降级 |
|---|---|---|---|---|
| MySQL（micro_station 库） | 场站数据 | 3s | sqlx 内置 | fail-closed 业务码 |
| Redis DB0 | 影子只读（监控聚合） | 3s | go-redis 内置 | 影子不可用 → 监控项全离线（online=false），列表/绑定不受影响 |
| device RPC | SN→device_id 归一（绑定/反查） | 5s | 无 | 未配置 = 仅支持 device_id 绑定（Saga 传 SN 清单需可用） |
| Kafka（station_created 生产） | Outbox Relay 投递 | 异步 | 退避 ≤16 次 | 未配置 = 事件滞留 outbox（ops 侧暂不建巡检计划） |
| etcd | 发现/worker/configcenter | 5s | 30s 重试 | configcenter 无初值用默认 |

**Saga 补偿纪律（02 §9.1 步骤 6）**：建站失败 → order 重试 1m/5m/30m ×3 → MANUAL 人工队列；本服务侧幂等（order_no 锚点），人工重推安全。

## 2. 健康指标

- **RED**：`http://<host>:9111/metrics`。
- 业务观测：Outbox PENDING 积压（station_created 未投递）；`uk_station_tenant_order` 冲突频次（Saga 重放计数）。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| Saga 卡步骤 6（订单详情可见） | station 未启动 / device RPC 不可用（SN 解析失败） | 拉起服务后 order cron 自动续推；超限进人工队列走订单详情"重推" |
| 绑定清单出现 `dev:<id>` SN | device RPC 未配置时的降级占位 | 配置 DeviceRpc 后重新绑定（冗余 SN 仅展示口径） |
| 监控聚合全离线 | 影子 Redis 不可达 / iotingest 未写 | 查 iotingest writer 与 ShadowRedis 配置；monitor_stale_sec 热调 |
| station_no 冲突 | 租户内编号重复 | 换编号或留空自动生成 STN{id} |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc station up`；契约变更走 `goctl rpc protoc pb/station.proto …`（--module）。
- 回滚：二进制回退 + 迁移 down；绑定关系表软删可恢复。

## 5. 紧急操作

- 建站风暴（Saga 大量重放）：幂等锚点天然收敛，无需处置；确需止血可在 order 侧暂停 `order-saga-retry-scan`。
- 拓扑版本膨胀：configcenter `topology_max_ver` 保留数（>0 触发裁剪口径）。
