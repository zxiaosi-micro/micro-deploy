# runbook · audit（审计日志服务）

> 服务：audit ｜ RPC 8087 / metrics 9107 ｜ module `micro-server/services/audit`
> 职责一句话：操作审计 + 控制指令审计（NFR-SEC-004：控制类 100% 独立审计，含操作人/时间/参数/结果）。
> 关联任务：S4-04 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：audit_db（操作日志 + cmd_log）只增不改（追加式，NFR-DAT：热 6 个月/归档 ≥3 年）；各服务经 RPC 写审计，admin-bff 提供查询面。

| 依赖 | 用途 | 超时 | 降级 |
|---|---|---|---|
| MySQL（micro_audit） | 追加写 | 3s | 熔断（审计写失败业务侧不阻塞主流程，落本地日志告警） |
| etcd | 发现/雪花/configcenter | 5s | 后台重试 |

## 2. 健康指标

- RED：`:9107/metrics`；业务：审计写入失败计数（>0 告警——审计断档 = 合规风险）、cmd_log 与 device 指令量比对（100% 覆盖校验）。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 审计缺失某操作 | 调用方未接审计埋点 | 业务服务侧补埋点（控制指令 100% 红线） |
| 写入延迟积压 | DB 慢/熔断 | 慢查询治理；熔断期间日志本地留存可回灌 |
| 查询 403 | 权限码 audit:log:list | role_menu 配置核对 |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc audit up`；启动前置 `source tools/devenv.sh micro_audit`。

## 5. 紧急操作

- 审计表只增不删（合规）；误写通过补记冲正行（append-only 语义）。
- 归档窗口调整走 configcenter（保留期策略）。
