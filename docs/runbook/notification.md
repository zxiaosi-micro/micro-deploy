# runbook · notification（消息通知服务）

> 服务：notification ｜ RPC 8089 / metrics 9109 ｜ module `micro-server/services/notification`
> 职责一句话：站内信/未读计数/订阅消息模板（微信）/通知设置，轮询增量的数据源（NFR-PRF-003 告警可见性的落地端）。
> 关联任务：S4-05 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：notification_db（message/template/setting）；10s 轮询接口（unread-count + since_id 增量）P95<100ms / <5KB（p5perf 验收）。

| 依赖 | 用途 | 超时 | 降级 |
|---|---|---|---|
| MySQL（micro_notification） | 全部 | 3s | 熔断 |
| 微信订阅消息 API | 异步触达（正式 appid 属合规范畴） | 5s | 失败重试 + 留痕；dev MOCKWX 不实发 |
| Kafka（notification_request 消费） | 域事件转站内信 | 消费侧 | event_retry 退避 |

## 2. 健康指标

- RED：`:9109/metrics`；业务：轮询接口 P95（500 并发 p5perf 口径）、订阅消息发送失败率、模板余额（微信侧）。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 轮询接口 P95 超标 | 未读计数查询慢 | idx(user_id, read) 索引核对；p5perf -case poll 复测 |
| 站内信缺失 | notification_request 消费滞后 | 消费组 lag + event_retry |
| 订阅消息发不出 | 模板/appid 配置 | 合规范畴（04 §3）：模板申请与正式 appid 由所有者完成 |
| since_id 增量漏消息 | 客户端游标回退 | max_id 语义按接口返回（新→旧序），客户端续传核对 |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc notification up`；启动前置 `source tools/devenv.sh micro_notification`。

## 5. 紧急操作

- 触达链路故障不影响站内信落库（异步通道隔离）；批量重发走模板维度补推。
- 全站公告：template + 群发（谨慎，频控红线）。
