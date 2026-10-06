# v4 文档集 · 合并基线（当前有效版本）

**版本**：v4.0 ｜ **日期**：2026-10-06
**性质**：v4 是把 **v2 基线 + v3 增量修订层**合并重写后的**新基线**（同 v1→v2 惯例）；v1/v2/v3 原文冻结归档，仅供追溯。**冲突裁决顺序：v4 > v3 > v2 > v1**。
**技术文档重构说明**：02 文档按 **zero-skills（go-zero 官方工程范式知识库）+ go-zero.dev 官网指南** 重写——三层架构、goctl 生成流水线、httpx 错误语义、sqlx 数据访问、内置韧性组件、可观测三支柱全部对齐 go-zero 原生路径，**中间件全量官方化：配置中心 = core/configcenter（etcd）、消息队列 = go-queue（Kafka kq 单件）、延迟任务 = 业务表 next_exec_at + cron 注册表扫描（不引入延迟队列）、升级路径首选内置 SSE**；两大技术变更为 **数据访问层 GORM → goctl model + sqlx（ADR-08）** 与 **Nacos → configcenter（ADR-10）、RocketMQ → go-queue（ADR-12）**，**评审确认以本文档集为准**。

## 本目录

| 文档 | 说明 | 状态 |
|---|---|---|
| [01-需求文档.md](01-需求文档.md) | 需求规格（纯需求、无排期）：v2 需求基线 + NFR-ENV-001 全量容器化并入 + micro-web 仓名 + 可观测六件套定稿 | ✅ 定稿 |
| [02-技术文档.md](02-技术文档.md) | 技术架构（go-zero 范式重构版）：goctl 流水线 / sqlx 数据层 / 韧性 / 可观测 / ADR-01~24 | ✅ 定稿（已评审确认） |
| [03-任务清单.md](03-任务清单.md) | 12 阶段任务清单（新手友好版）：S0~S11 按终稿口径任务化，含 sqlx 新表 checklist / Kafka 事件 / configcenter 接入 / 坑位引用 | ✅ 定稿；执行进度在 [task/](../../task/README.md) 阶段文档记录 |
| [04-待办与演进.md](04-待办与演进.md) | **清仓版**：v2/v3 全部待办/技术债/演进建议闭账，剩余=外部依赖切换点 + 用户侧动作 | ✅ 定稿 |

## v2/v3 → v4 决策变更总表

| # | 讨论点 | v2/v3 口径 | **v4 定稿口径** |
|---|---|---|---|
| 1 | 中间件部署形态 | v2：本机五件套 + compose 边缘；v3：全量容器化（定稿） | **全量容器化并入正文**（NFR-ENV-001，01 §6.8）：单一全量 compose（profiles：core/edge/obs）、端口=默认+20000、数据全挂卷、密码 `.env`（MICRO_DEV_*）、双登记（compose 注释 + env.md）、应用服务不容器化 |
| 2 | 前端合仓名 | v2：micro-frontend；v3：micro-web（定稿） | **micro-web 并入全文**（ADR-17），合仓策略/目录/拆分条件不变 |
| 3 | 可观测六件套 | v3 建议方案 A，待确认 | **方案 A 定稿（ADR-21）**：Prometheus/Grafana/Loki/Promtail/Jaeger/Alertmanager 全保留，四类数据各司其职；dev 按 compose profiles 可选启动，生产常驻；NFR-OBS/FR-SYS-004/阶段验收无需连带修订 |
| 4 | 消息队列 | v2/v3：RocketMQ（v3 仅裁决"不引入 Proxy"） | **RocketMQ 整体退役，go-queue 替代（ADR-12）**：事件总线 = kq(Kafka)，**仅此一件**；延迟任务不引入 Beanstalkd，统一"业务表 next_exec_at + cron 注册表扫描"（ADR-09，秒级需求出现再加回 dq）；消费侧重试/DLQ 由 eventbus 自建承接；RocketMQ Proxy 议题作废 |
| 5 | **数据访问层（v4 新决策）** | GORM + Callbacks 租户插件 | **goctl model + sqlx**（ADR-08）：迁移 SQL=唯一事实源，生成 CRUD+行缓存；租户/软删过滤 model 层 SQL 显式携带 + tenantaudit 静态把关；03 任务清单重写时同步 |
| 6 | **API 文档生成（v4 新决策）** | 自研 tools/openapi | **goctl api swagger 内置**（ADR-20）：wrapCodeMsg/useDefinitions/authType/bizCode 错误码全用上；CI swagger-diff 门槛（同时清仓 C4） |
| 7 | **韧性/并发组件（v4 新决策）** | 自研批量写/定时器 | 对齐 go-zero 内置：executors.BulkExecutor（遥测批量写）、collection.TimingWheel（指令 ACK 超时，配持久兜底）、collection.Cache（规则/降级缓存）、syncx.SingleFlight（防击穿）、mr.Finish（BFF 并行扇出）、limit.PeriodLimit（租户 RPM 配额） |
| 8 | Saga 演进目标 | Temporal | 首选 **DTM**（go-zero driver，Saga 语义同构），次选 Temporal（ADR-03） |
| 9 | 灰度发布 | 未启用（D11 建议） | **双通道定稿（ADR-22）**：APISIX traffic-split + configcenter 灰度开关（Git 正本推送 etcd），多端上线后首个迭代启用 |
| 10 | **PDF 渲染（v4 复核）** | Gotenberg 容器（v2 引入） | **不引入（ADR-18）**：报表导出/合同打印稿均简单版式，Go 原生库进程内渲染；复杂版式硬需求出现时按切换点加回（04 §2） |
| 11 | 列表分页策略 | 未约定（C5 技术债） | 分页上限 100；大数据一律异步导出；不做虚拟滚动（定稿） |
| 12 | ercheck 工具 | D12 建议 | **不做**：迁移 SQL 即唯一事实源 + goctl 生成物自动同步（ADR-08 副产品） |
| 13 | 待办/技术债/演进 | v2/04 共 30+ 条 | **全部清仓**（04 文档）：A→需求 L3 条目、B→切换点、C→已解决、D→定稿、E→内化附录 C；剩余仅用户侧 F1~F6 |
| 14 | **配置中心（v4 复核）** | Nacos（v2 引入） | **go-zero core/configcenter（etcd）替代（ADR-10）**：watch/内存快照/类型校验；配置正本 Git 化（PR 评审 + CI 推送 etcd）；"多语言 SDK"理由删除；FR-SYS-003 已改写 |
| 15 | **API 网关（v4 复核）** | APISIX（v2 引入） | **维持 APISIX（ADR-01）**：go-zero 内置 gateway 是库级 HTTP↔gRPC 代理（静态映射、无鉴权/限流/灰度），不满足边缘需求，仅留作内部 gRPC 快速暴露备选 |
| 16 | **实时性升级路径（v4 增补）** | WebSocket 组件为升级项 | **升级首选 go-zero 内置 SSE（ADR-02）**：框架原生、零新增组件；其次才评估 WebSocket |
| 17 | **Docker/部署（v4 对齐）** | goctl docker 基线 | 官方 Docker 指南对齐：多阶段 alpine + tzdata + **HEALTHCHECK /healthz** + compose 编排；goctl docker 保留为生成入口 |
| 18 | **可观测性复核（v4 新增）** | 六件套 + promauto 自定义指标 | **六件套维持（ADR-21）**；自定义指标改用 go-zero 内置 `core/metric`（官方姿势）；**新增可选 Pyroscope 持续剖析为第 7 件（ADR-24，:24040）**；logx `Sensitive` 接口日志脱敏进安全域；Grafana 基线看板=官方市场 go-zero 看板；Promtail→Alloy / OTel Collector 登记切换点（04 §2） |

## 连带的结构性变化

| 维度 | v2/v3 | v4 |
|---|---|---|
| 需求文档 | v2 基线 + v3 覆盖层 | 单一基线（01），NFR-ENV-001 入 §6.8 |
| 技术文档 | v2 正文 + v3 增量 | **按 go-zero 范式重写**（02），ADR 至 23 条 |
| ORM/数据访问 | GORM + Callbacks | **goctl model + sqlx**（custom 覆写 + tenantaudit） |
| 消息队列 | RocketMQ（NameServer + broker） | **go-queue：Kafka（kq）单件**；重试/DLQ 职责转入 eventbus |
| 配置中心 | Nacos（独立容器） | **core/configcenter（etcd，零新增组件）**；配置正本 Git 化 |
| 定时任务 | RocketMQ 延迟消息 + cron 注册表 | **不引入延迟队列**：next_exec_at + cron 注册表扫描 / K8s CronJob 两分类（ADR-09） |
| PDF 渲染 | Gotenberg 容器 | **Go 原生库进程内**（Gotenberg 移除；再评条件见 ADR-18） |
| 文档生成 | 自研 openapi 工具 | goctl api swagger + apitypes（TS 类型保留自研） |
| dev 环境 | v3：全量 compose | 不变（正文 §15.2，含 profiles/卷/密码/组网要点） |
| 待办清单 | A4+B8+C4+C5+C9+C10+D12 共 10 条未闭 | **0 条未闭**（F 用户侧 6 条除外） |
| 任务清单 | v2/03 + task/ | v4/03 待 02 评审后重写；task/ 阶段文档继续做执行跟踪 |

## 维护约定

- 业务口径变更先改 `01`（评审）；技术口径变更先改 `02` 并追加 ADR；任务进度在 `task/` 阶段文档勾选；新需求（L3 触发）按 01 条目立项，不再新增待办条目。
- v2/03 已冻结为历史；**任务正本 = v4/03**，执行进度在 `task/` 阶段文档记录（冲突以 v4/03 > v2/03 为序）。
- 冲突裁决顺序：**v4 > v3 > v2 > v1**。
