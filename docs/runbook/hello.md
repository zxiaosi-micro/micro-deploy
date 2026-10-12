# runbook · hello（模板服务）

> 服务：hello ｜ RPC 8888 / metrics 9117 ｜ module `micro-server/services/hello`
> 职责一句话：新服务骨架的活模板（newsvc 生成基线的参照实现），同时承担 workspace 编译健康探针。
> 关联任务：S1-09 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：无业务表、无外部依赖；cron 示例 `hello-heartbeat`（30s）演示 cronx 注册表模式。新服务落地照抄本骨架（confx.MustLoad → confcenter.MustListen 后台重试 → svc → zrpc + authz 拦截器 → consumer/relay/cron 挂载顺序）。

| 依赖 | 用途 | 降级 |
|---|---|---|
| etcd | 发现/雪花/configcenter | 后台重试接入 |

## 2. 健康指标

- RED：`:9117/metrics`；cron last_run 推进即健康。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| confcenter "无初值" | etcd 键位含文件名（/micro/config/hello/main） | 键位对齐 ConfigKey 默认值；listener 后台 30s 重试是模板自带语义 |
| goctl rpc 生成 import 变 micro-server/pb | 从根跑生成 | 服务目录内相对路径 + --module（AGENTS 已知坑清单） |

## 4. 发布与回滚

- 无迁移；`make newsvc name=x` 生成的新服务以本服务为基线。

## 5. 紧急操作

- 无业务影响面；停启自由（workspace 编译探针用途时保持运行）。
