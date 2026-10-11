# runbook · mobile-bff（多端 BFF）

> 服务：mobile-bff ｜ HTTP 8890 / metrics 9119 ｜ module `micro-server/services/mobile-bff`
> 职责一句话：运维 App（OPS_APP）与客户端小程序（CLIENT_MINI）的 BFF——聚合/裁剪/越权拦截，**客户侧一切查询按 party_id 隔离（requireParty）**。
> 关联任务：S9-01 ｜ 最近更新：2026-10-11

## 1. 职责与依赖

**职责边界**：无业务库（纯 BFF 不落 MySQL，与 admin-bff 同口径）；业务规则全部在下游 RPC。两条路由面：
- `approutes`（`/app/*`，AllowedClients=[OPS_APP]）：工单自领/处理（client_action_id 离线幂等）、巡检批量提交、告警 pending 增量轮询。
- `customerroutes`（`/customer/*`，AllowedClients=[CLIENT_MINI]）：微信登录（MOCKWX 模拟）→ 绑手机 → 档案/联系人/设备激活/合同/质保/延保购买/报修工单/消息/场站/SLA。

**上下游依赖**（出站，对应 02 §10 韧性策略表）：

| 依赖 | 用途 | 超时预算 | 降级行为 |
|---|---|---|---|
| identity | 登录/刷新/GetUser/BindPhone/Ping | 3~5s | fail（认证链不可降级） |
| ops / device / contract / order / station / notification / catalog / inventory / party | 端侧聚合查询 | 5s（yaml per-client） | BFF 快速失败回业务码 |
| TDengine REST | 设备遥测趋势只读（Basic 认证 E7） | 5s | 查询失败返回空 points（趋势页降级，不阻断） |

**requireParty 口径**：`identity.GetUser(uid) → party_id`；0 = 未绑定 → 110404。设备/工单详情再校验行归属（不匹配回 10408）。延保下单走 `/customer/extension-orders`，属 FailClosePrefixes（Redis 故障拒绝）。

## 2. 健康指标

- **RED**：`http://<host>:9119/metrics`（go-zero 内置），Grafana go-zero 官方看板按 `service="mobile-bff"` 过滤。
- **健康检查**：`GET :8890/api/v1/healthz`（免鉴权）——`{status: ok|degraded, checks:{identity, tdengine}}`；容器探针指向它，identity error 时置 degraded 并告警。
- **轮询接口专项**：`/app/alerts/pending`、`/app/tickets/pending` 的 QPS/P95/响应字节数进 RED（NFR-PRF-006：P95<100ms、<5KB）。

## 3. 常见故障

| 现象 | 排查 | 处置 |
|---|---|---|
| 登录报 1101013 微信未配置 | dev 未 source devenv.sh（MOCKWX 未注入） | `source tools/devenv.sh` 后重启；正式 appid 为用户侧动作（04 §3 F1） |
| 客户接口全报 110404 | 用户无 party 绑定 | 管理后台参与方管理建立客户档案 → identity BindParty |
| 客户查他人设备 10408 | requireParty 归属校验生效（正常拦截） | 核对 device.party_id 是否正确归属 |
| 延保下单 110500 | 首仓不存在（ListWarehouse 空） | 库存中心建仓 + 延保 SKU 入库 |
| 遥测趋势空 | TDengine 未起/凭证错/子表无数据 | envcheck TDengine 项；`select last_row(*) from iot_db.iot_<pk>_<sn>` |

## 4. 发布与回滚

- 启动：`source tools/devenv.sh`（JWT_KEYS_DIR/REDIS/MOCKWX）→ `go run ./services/mobile-bff -f services/mobile-bff/etc/mobile-bff.yaml`；yaml 全 `${ENV}` 占位，零硬编码。
- 配置：启动期配置（端口/RPC endpoints）走 yaml+env；运行时无 configcenter listener（BFF 与 admin-bff 同口径，轮询间隔等由端侧常量承载）。
- 回滚：回退镜像/二进制重启即可（无库无迁移）；契约变更按两阶段发布（先加列/字段后删）。

## 5. 紧急操作

- 互斥/踢人：管理后台会话管理页（identity KickSessions），mobile-bff 无会话写权限。
- Redis 故障：普通路由 fail-open（≤30min 暴露窗口 + 降级告警日志），`/customer/extension-orders` fail-close。
- 下游服务宕机：BFF 快速失败不雪崩；恢复后轮询端自动收敛（无补偿状态）。
