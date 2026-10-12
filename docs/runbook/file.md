# runbook · file（文件服务）

> 服务：file ｜ RPC 8086 / metrics 9106 ｜ module `micro-server/services/file`
> 职责一句话：对象存储网关（MinIO/云 OSS）+ 文件元数据 + 异步导出产物归档（analytics 导出管道的落盘端）。
> 关联任务：S4-06 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：file_db（file 元数据）+ 对象存储（dev MinIO bitnamilegacy 冻结版仅限 dev；生产云 OSS，B1 切换点）。双桶（public/private）。

**gRPC 消息上限三处联动**（漏一处即 ResourceExhausted）：file 服务端 AddOptions(MaxRecv/SendMsgSize 64MB) + analytics/admin-bff 客户端 dial MaxCallRecv/SendMsgSize + file maxFileSize 64MB（S8 导出 10 万行 ~23MB）。

**导出 worker ctx**：TaskRunner 闭包按任务归属租户重建 ctx（消费 handler ctx 不可靠，裸 Background 也会 10408）。

| 依赖 | 用途 | 超时 | 降级 |
|---|---|---|---|
| MinIO/云 OSS | 对象读写 | 10s | 上传失败任务置 FAILED |
| MySQL（micro_file） | 元数据 | 3s | 熔断 |
| etcd | 发现/configcenter | 5s | 后台重试 |

## 2. 健康指标

- RED：`:9106/metrics`；业务：PutFile 失败率、桶容量水位、大文件上传 P95。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 导出产物超限报错 | 64MB 三处联动缺一 | 按 AGENTS 清单逐点核对（服务端/客户端/maxFileSize） |
| 下载 403 | 桶策略/预签名过期 | 预签名时长调整；private 桶走授权链 |
| OSS 切换后失败 | endpoint/凭证 | B1 切换核对 OSS_ENDPOINT/OSS_BUCKET |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc file up`；启动前置 `source tools/devenv.sh micro_file`。

## 5. 紧急操作

- 桶只读应急（防止误写）：OSS 侧策略。
- 元数据与对象不一致：以对象存储为准补元数据（幂等 PutFile）。
