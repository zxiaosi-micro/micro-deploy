# runbook · iotingest（遥测接入独立进程）

> 服务：iotingest ｜ OCPP WebSocket 8182 / metrics 9120 ｜ module `micro-server/services/iotingest`
> 职责一句话：EMQX 共享订阅 → Kafka 缓冲 → BulkExecutor 批量写 TDengine + 设备影子；越限候选初筛；OCPP 1.6J CSMS。
> 关联任务：S6-03 ｜ 最近更新：2026-10-10

## 1. 职责与依赖

**职责边界（02 §9.6）**：独立进程，遥测流量不穿透业务 RPC；不做业务判定（越限规则来自 configcenter 缓存，业务判定归 ops）；device/station 的影子键是本进程**唯一写入方**（`micro:iot:shadow:{sn}`，Lua 时间戳比较防乱序）。

**组件与背压点**：

| 组件 | 链路 | 语义 |
|---|---|---|
| forwarder | EMQX `$share/ingest/up/+/+/+/telemetry` → kq.Pusher `iot_telemetry_raw` | **MQ 成功才 ack MQTT**（QoS1 重投背压，FR-IOT-004）；畸形主题 ack 丢弃 |
| writer | kq 消费组 `iotingest-writer` → `executors.BulkExecutor(500 条/200ms)` → TDengine（同 ts 覆盖幂等）+ 影子 | BulkExecutor 回调不返回错误——**写失败回灌 Kafka**（持久化重试轨迹，02 §9.6）；Flush/Wait 优雅关闭 |
| rules | `collection.Cache` LRU 30s TTL + configcenter 变更失效 + barrier 防击穿 | 命中 → alert_candidate（key=sn）；ops 判定 |
| ocpp | OCPP 1.6J WS :8182（BootNotification/Heartbeat/StatusNotification/MeterValues → 五指标映射） | 2.0.1 预留扩展位；桩鉴权函数注入（dev 放行） |

**上下游依赖**：EMQX（:21883 dev）、Kafka（iot_telemetry_raw/alert_candidate）、TDengine REST（Basic 认证必带，E7）、Redis DB0（影子）、etcd（规则订阅 `/micro/config/iotingest/rules`）。

## 2. 健康指标

- **RED**：`http://<host>:9120/metrics`；OCPP 在线桩数（内存 gauge）。
- 业务观测：Kafka lag（`iot_telemetry_raw` 消费组 `iotingest-writer`）；TDengine 单批写失败回灌频次（ERROR 日志）；alert_candidate 生产速率。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| TDengine 写失败刷屏（回灌循环） | TDengine 宕机/口令错（E7 401） | 恢复 TDengine；回灌消息因同 ts 覆盖幂等可安全重放；极端积压重建消费组 Offset=earliest |
| 影子不更新 | Redis 失联 / writer 未启动 | 查 ShadowRedis 配置与 Kafka brokers；影子可从最新遥测重建（非关键数据） |
| 规则不生效 | E15 排障口径：先查 configpush 是否推到 etcd（`/micro/config/iotingest/rules`），再查服务日志 reload 记录 | 30s TTL 兜底生效 |
| EMQX 共享订阅无消息 | 认证器丢失（E6）/ 主题 ACL 收紧 | 重跑 `docker compose up emqx-bootstrap`；核对设备 ACL `up/{tenant}/{pk}/{sn}/#` |
| OCPP 桩连不上 | :8182 未监听 / 子协议不匹配 | 确认进程启动日志 `ocpp: CSMS 监听`；模拟桩走 `tools/ocppsim` |

## 4. 发布与回滚

- 无迁移（无业务库）；发布 = 重启进程（Kafka Offset 持久于消费组，重启不丢不重——TDengine 同 ts 覆盖兜底）。
- 回滚：二进制回退；TDengine 数据可从 Kafka 重放（保留 3 天，02 §14.2）。

## 5. 紧急操作

- 遥测洪峰：forwarder 背压自动生效（MQ 不 ack）；必要时下调 writer 单批（configcenter 暂无此项——重启改 yaml）。
- 影子键污染：`DEL micro:iot:shadow:<sn>` 后由下一条遥测重建。
- 规则误发风暴：configcenter 规则集清空推送（candidate 停发，30s 内生效）。

## 6. EMQX bootstrap 重跑（E6）

EMQX 认证器/ACL 随容器重建丢失——**容器重建后必跑**：

```
docker compose -f compose/dev/docker-compose.dev.yml up emqx-bootstrap   # 幂等
```

覆盖：密码认证器（built_in_database）+ 授权源 + 平台联调账号（MICRO_DEV_EMQX_DEVICE_USER/PW，ACL up/# 发布 + down/# 订阅）。设备级一机一密由 device 服务 ImportSN/ProvisionCredential 写入（同款 REST 端点）。
