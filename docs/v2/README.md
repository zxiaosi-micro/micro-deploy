# v2 文档集 · 变更说明与导航

**版本**：v2.0 ｜ **日期**：2026-10-06
**性质**：v2 是在 v1 四份文档基础上，经项目所有者逐条确认（20 个讨论点 + 4 项关键决策）后的**修订版基线**。v1 已归档于 `docs/v1/`，此后以 v2 为准。

## 本目录

| 文档 | 说明 |
|---|---|
| [01-需求文档.md](01-需求文档.md) | 需求规格（纯需求、无排期） |
| [02-技术文档.md](02-技术文档.md) | 技术选型与架构（含 5 仓方案） |
| [03-任务清单.md](03-任务清单.md) | 12 阶段开发任务清单（新手指南） |
| [04-待办与演进.md](04-待办与演进.md) | 待办 / 技术债 / 替代方案 |

## v2 相对 v1 的决策变更总表

| # | 讨论点 | v1 口径 | **v2 定稿口径** |
|---|---|---|---|
| 1 | 前端仓库 | micro-web（命名与粒度被质疑） | 前端合并单仓 **`micro-frontend`**（web 三端 + 两小程序 + 运维 App + shared）；仓库共 5 个 |
| 2 | 电子签 A1 | 对接 e签宝/法大大（L3） | **基线=线下签署+上传归档**（平台不关心文件内容，只管归档/关联/状态/下载权限）；在线签署降为 L3（触发：客户明确要求） |
| 3 | BaaS 代扣 A2 | 微信代扣资质等待 | **随订阅域整体删除**（见 #5） |
| 4 | 保险对接 A3 | 保司 API 对接（L3） | **基线=保单登记**（字段+文件归档+设备关联，出险走工单）；保司 API 为 L3 |
| 5 | 租赁/融资租赁 | 继承原项目已实施的租赁域 | **确认业务无租赁**：删除 LEASE 合同/租金计划/押金户/RENTED 状态/归还工单/融资租赁/订阅（BaaS）/商城；增值域仅保留**梯次利用/回收、BI、经销商返利**（均 L3） |
| 6 | 硬件联调 A5/A6 | 真实样机/桩型为待办 | **验收口径=协议标准（MQTT/OCPP 1.6J）+ 模拟器全链路**，硬件接入不设门槛 |
| 7 | 运维 App 上架 A7 | 开发侧待办 | **用户侧动作**（应用市场审核由所有者处理） |
| 8 | 旧数据迁移 A8 | NFR-CMP + datamigrate | **删除**：本项目即全新系统，无旧数据 |
| 9 | 等保测评 A9 | 上线前外部流程待办 | **移出开发待办**：按二级设计的安防措施保留，测评为所有者决定的合规范畴 |
| 10 | 预测性维护 A10 | 远期方向 | v2 不收录 |
| 11 | C1 ambient 租户解析 | 双级解析+偿还条件 | **v2 硬约定**：DB 访问一律 `WithContext(ctx)`（lint+review 把关），单级解析，删除 ambient |
| 12 | C2 RBAC 缓存窗口 | 本地缓存+事件失效 | **v2 硬约定**：BFF 每请求查 Redis auth_cache（即时生效），本地缓存仅 Redis 故障降级兜底 |
| 13 | C3 JWT kid | 技术债 | **做进 S3 任务**：header 内置 kid + 多公钥集合 + 轮换 runbook |
| 14 | C7 PDF 渲染 | 待定 | **Gotenberg 容器**（复杂版式/合同）+ Go 原生库（报表）；不采用 Selenium |
| 15 | C8 测试依赖 | 部分用例本地 Skip | **CI 增加 TDengine 容器作业**强制全量；本地 CI 同款命令文档化 |
| 16 | D2 Saga | 自研+触发条件 | **确认维持自研**（触发条件写 ADR） |
| 17 | D5 实时推送 | Centrifugo | **砍掉 Centrifugo**：统一 10s 轮询（轻量增量接口）+ 微信订阅消息（异步提醒）；WebSocket 降为 L2 升级项 |
| 18 | D6 认证框架 | 自研 sessionx | **确认维持自研**（互斥/踢人/step-up 是有状态会话语义，标准 IdP 弱项）；未来开放平台场景评估 Zitadel |
| 19 | D7 任务调度 | 延迟消息为主 | **确认**：RocketMQ 延迟消息 + cron 扫描任务注册表（登记+last_run 指标） |
| 20 | D10 配置中心 | 自研 config 服务 | **引入 Nacos 做配置中心**（多语言是需求项）；**砍自研 config 服务**；服务发现仍走 etcd |

## 连带的结构性变化（由上述决策推导）

| 维度 | v1 | v2 |
|---|---|---|
| 仓库 | 5 仓（micro-web） | 5 仓（**micro-frontend**） |
| 后端服务数 | 20（含 subscription、config） | **18**：14 RPC + admin-bff + mobile-bff + iotingest + hello |
| common 包 | 12 个（含 pushjwt） | **11 个**（删 pushjwt） |
| 中间件 | compose 含 Centrifugo | **删 Centrifugo，增 Nacos**（:8848） |
| Redis DB 规划 | DB2=Centrifugo | DB2 预留（编号保留不复用） |
| device 状态机 | 含 RENTED | 无 RENTED |
| 合同类型 | 含 LEASE | SALES/STATION/SERVICE/FRAMEWORK/EXTENDED |
| 工单类型 | 含 LEASE_RETURN | ALERT/AFTER_SALE/INSPECTION/INSTALL/STATION |
| 客户端小程序 | 含商城分包 | 删商城（3 个分包：station/service/profile） |
| 事件 topic | 含 config_changed | 删（Nacos listener 替代） |
| 端口 | config 8088/9108、subscription 8096/9116 | 两对端口标记**预留**（编号不复用） |
