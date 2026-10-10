# runbook · analytics（分析域服务）

> 服务：analytics ｜ RPC 8095 / metrics 9115 ｜ module `micro-server/services/analytics`
> 职责一句话：CQRS 读模型**唯一写入方**（analytics_db：六大日聚合 + 事件台账 + 指标字典 + watermark）+ 异步导出管道 + 日级对账（v4/02 §9.8）。
> 关联任务：S8-01~05 ｜ 最近更新：2026-10-11

## 1. 职责与依赖

**职责边界**：analytics_db 全部表（report_* / export_task / recon_* / report_metric_dict）归本服务；报表服务面**只读本库**（报表不 JOIN 业务库）。业务库只在两处被直查（管理面特权，A1 应用账号 micro_% 授权）：日级对账（recon_targets）与补投递工具（tools/p4backfill）。

**事件链**：消费 14 类日聚合事件（order.×4 / stock.×3 / payment.refunded / order.return_approved / warranty.started / device.activated / shipment.signed / station.created / alert.created），消费组 `analytics-read-v{N}`（版本号 = report_meta.rebuild_version）；生产 export_requested（自管道）+ notification_request（对账差异站内信），Outbox Relay 退避 ≤16 次。

**幂等三层**：event_dedup（event_id，同事务）→ report_event_entry uk_biz（event_type+biz_key，backfill 新 event_id 重放也挡）→ 聚合 upsert 仅在首次应用时执行。

**上下游依赖**：

| 依赖 | 用途 | 超时预算 | 重试 | 熔断/降级 |
|---|---|---|---|---|
| MySQL（micro_analytics 库） | 读模型全部数据 | 3s | sqlx 内置 | 消费失败 → event_retry 退避重投（handler 失败不阻塞） |
| Kafka（14 topic 消费 + export_requested/notification_request 生产） | 事件链 | kq 同步 | Outbox Relay 退避 ≤16 次 | 未配置 brokers = 仅 RPC 面（消费/Relay/cron 不启动，日志留痕） |
| file RPC | 导出产物归档（PutFile，64MB 消息上限） | 5s | 无 | 未配置 = 导出任务置 FAILED（报错优于静默） |
| etcd | 服务发现 + 雪花 worker_id + configcenter | 5s | 30s 重试 | configcenter 无初值用启动默认（E15） |
| 各业务库（micro_order/inventory/finance/contract/device/station/ops，只读直查） | 日级对账 recon | 3s | 单指标失败跳过本轮 | recon 单指标失败不阻塞整轮（下轮补查） |

**导出并发限流**：渲染走 `threading.TaskRunner`（workers = confcenter `export_workers`，默认 2），与 RPC goroutine 隔离——p4load 验证 10 万行导出对在线请求零影响（P95 3.2ms ≤ 100ms 预算）。

**PDF 口径（ADR-18）**：Go 原生库（go-pdf/fpdf）+ UTF8 中文字体（`pdf_font`，默认 Windows simhei.ttf），简单表格版式、行数封顶 `export_pdf_rows`（默认 2000）；缺字体 = PDF 导出报业务错误（151007），CSV/XLSX 不受影响。

## 2. 健康指标

- **RED**：`http://<host>:9115/metrics`（go-zero 内置）。
- **cron 注册表**（E16 对账口径）：`daily_recon`（1m，configcenter `recon_enabled` 开关）——last_run 停摆即告警。
- 业务观测：`report_watermark.processed_count`（消费水位，14 topic 应齐）；`event_outbox` PENDING 积压；`export_task` status=RUNNING 滞留 >10min；`recon_diff` status=OPEN 数（差异率目标 0）；`event_dead` 表（死信 >0 告警）。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 报表数据缺当日 | 读模型消费滞后 | 查 `report_watermark` 各 topic processed_count 是否推进；Kafka lag（消费组 analytics-read-v1） |
| recon_diff 有 OPEN 差异 | 上游漏发事件（FR-ANA-004 设计行为，站内信已发） | `go run ./tools/p4backfill -date <biz_date>` 补投递（E10 禁裸删）；复跑对账到 0 |
| 对账单指标持续失败 | 该指标 source SQL 列变更 | 看 recon ERROR 日志（单指标失败跳过不阻塞）；修 recon_targets 后下轮自愈 |
| 导出任务卡 PENDING | Relay 停摆或 Kafka 断连 | 查 event_outbox 里 export_requested 是否 SENT；消费组 analytics-export 是否在线 |
| 导出任务 FAILED"归档失败" | file RPC 不可用或产物超 64MB | file 服务健康检查；超大数据走 CSV（PDF 有 export_pdf_rows 封顶） |
| PDF 导出报 151007 | pdf_font 未配置/字体缺失 | configcenter 推 `pdf_font` 指向可用 ttf（中文必须，ASCII 亦走该字体） |
| 消费报"biz_key 提取失败" | 上游 payload 契约变更 | 台账 payload 留原文明细；payload 解析与各服务 logic/events.go 对齐后重启 |
| 消费报"业务键重复跳过" | 重放/补投递正常去重（Info 级） | 无需处理——台账 uk_biz 幂等生效的证据 |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc analytics up`（down 成对可回滚；000003 字典种子幂等）。
- 契约变更：`goctl rpc protoc pb/analytics.proto …`（--module 必带，服务目录内相对路径）→ tidy → build → vet → lint。
- 启动前置：`source tools/devenv.sh micro_analytics`；compose core（MySQL/Redis/etcd/Kafka）+ file（导出归档用）。
- **回滚**：服务二进制回滚即可（读模型 schema 向后兼容）；消费组版本号机制保证逻辑回滚后重建：
  1. RPC `RebuildReadModel`（truncate 台账/六表/watermark + 版本号 +1）；
  2. 重启服务（新消费组 `analytics-read-v{N+1}` 从头回放）；
  3. Kafka 已过保留期的历史 → `tools/p4backfill -date <d>` 按业务库补发。

## 5. 紧急操作

- **停止消费**（读模型下游异常时保业务）：kill 进程即可——消费组 offset 已提交，恢复后续读；漏读由 event_dedup + 台账幂等兜底。
- **读模型重建**：见上文回滚第 1~3 步（RebuildReadModel RPC 权限码 `analytics:recon:rebuild`）。
- **对账手动触发**：RPC `RunRecon`（空日期 = T-1）或 BFF `POST /api/v1/reports/recon`（权限 `analytics:recon:run`）；差异自动站内信（每业务日防重）。
- **Kafka 积压清零后追赶**：加大 Conns/Consumers 前先确认台账幂等（并发消费同聚合键会 1062 重试，安全但慢）。
- **禁裸删（E10）**：任何差异修复只走 p4backfill 重放；recon_diff/event_dead 只增不删。
