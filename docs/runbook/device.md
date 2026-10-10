# runbook · device（设备与资产服务）

> 服务：device ｜ RPC 8085 / metrics 9105 ｜ module `micro-server/services/device`
> 职责一句话：设备主数据/一机一密凭证/生命周期状态机/指令下行/OTA 的**唯一写入方**（device_db）+ 设备影子只读。
> 关联任务：S6-01 ｜ 最近更新：2026-10-10

## 1. 职责与依赖

**职责边界（02 §2.3）**：device_db 全部表（device/lifecycle_log/topology/firmware/ota_task/ota_device/cmd）归本服务；状态机只由事件驱动（stock_in/stock_out/device.activated），Transition 仅限退役/报废白名单对（FR-DEV-003）。遥测数据面不经本服务（iotingest→Kafka→TDengine）；影子 Redis 键 `micro:iot:shadow:{sn}` 由 iotingest 写入、本服务与 station 只读。

**上下游依赖**（02 §10 韧性策略表 device 行）：

| 依赖 | 用途 | 超时预算 | 重试 | 熔断/降级 |
|---|---|---|---|---|
| MySQL（micro_device 库） | 设备数据 | 3s | sqlx 内置 | 档案/指令链 fail-closed 报业务码 |
| Redis DB0 | 影子读取 | 3s | go-redis 内置 | 影子不可用 → GetDeviceShadow 报 8801012（列表/指令不受影响） |
| EMQX REST（Dashboard :38083） | 凭证开通（一机一密 + ACL） | 5s | 幂等重放 | 未配置 = Provision 降级跳过（ProvisionErrors 回执）；开关 `provision_enabled`（configcenter） |
| EMQX MQTT（:21883 dev / 8883 生产） | 指令下行 down/{sn}/cmd QoS1 | 5s publish | paho 自动重连 | broker 失联 → cmd 停留 PENDING，cron 30s 兜底重试（≤3 次 → FAILED + cmd_failed 事件） |
| Kafka（stock_in/stock_out/cmd_ack 消费；device_activated/cmd_failed/ota_paused 生产） | 事件链 | kq 同步 | Outbox Relay 退避 ≤16 次 | 未配置 brokers = 仅 RPC 面（消费/Relay 不启动，日志留痕） |
| audit RPC | cmd_audit 独立审计 | 5s | 无（异步 best-effort） | 未配置 = cmd 表留痕兜底；写失败仅 ERROR 日志（E13 可观测失败） |
| etcd | 服务发现 + 雪花 worker_id + configcenter | 5s | 30s 重试 | configcenter 无初值用启动默认（E15） |

**TimingWheel 与持久兜底分工（02 §9.6）**：指令 ACK 3s 计时用 `collection.TimingWheel`（内存态，重启即失）——cmd 表状态机（PENDING→SENT→ACKED/FAILED）+ cron `device-cmd-retry-scan`（30s）扫描兜底重试；跨重启语义以 cmd 表为准。

## 2. 健康指标

- **RED**：`http://<host>:9105/metrics`（go-zero 内置）。
- **cron 注册表**（E16 对账口径）：`device-cmd-retry-scan`（30s）/ `device-ota-dispatch-scan`（30s）——last_run 停摆即告警。
- 业务观测：cmd 表 `status=SENT AND next_exec_at<NOW()` 数（指令积压）；ota_task RUNNING 任务 fail_count/total（失败率逼近 20% 阈值）；event_outbox PENDING 积压。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 设备连不上 MQTT | EMQX 认证器丢失（E6，容器重建后必现） | 重跑 `docker compose up emqx-bootstrap`；或对单设备调 `/devices/:id/credential` 补发 |
| 指令一直 PENDING/SENT | EMQX 失联或设备离线 | 看 `cmd.fail_reason` 与 cron 日志；重试超限自动 FAILED + cmd_failed（ops 告警闭环） |
| OTA 任务卡 RUNNING 不推进 | cron 停摆或 RPC 面 MQ 未配置 | 查 cronx last_run；确认 Kafka brokers 配置（Relay/消费同源） |
| OTA 失败率超阈自动暂停 | FR-IOT-007 设计行为（默认 20%） | ota_paused 事件已发；人工核查设备后 RollbackOtaTask 或修复后重推 |
| ImportSN 报"数据密钥未就绪" | MICRO_DATA_KEYS 未注入 | `source tools/devenv.sh micro_device` 后重启 |
| 状态机不推进 | 事件缺失（inventory 未发 sns） | 确认 inventory 版本（S6 起事件带 SN 明细）；查 device_lifecycle_log 事件类型 |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc device up`（down 成对可回滚）。
- 契约变更：`goctl rpc protoc pb/device.proto …`（--module 参数必带）→ tidy → build → vet → lint。
- 回滚：服务二进制回退 + 迁移 down（`-steps 1`）；事件消费者 Offset=first + 生命周期日志唯一键幂等，回滚重放安全。

## 5. 紧急操作

- 凭证批量重建（EMQX 重建后）：`docker compose up emqx-bootstrap`（平台账号）→ 逐台 `/api/v1/devices/:id/credential` 或重新 ImportSN 幂等。
- 指令风暴熔断：configcenter `/micro/config/device/main` 下调 `ota_dispatch_batch` / 关 `provision_enabled`；极端情况暂停 `device-ota-dispatch-scan`（摘 cron 注册即停）。
- 消费积压：kq Offset=first + dedup 幂等，可安全重置消费组到 earliest 补放。
