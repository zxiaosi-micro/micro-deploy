# env.md · dev 环境端口与凭据登记表

> S2-01 双登记要求：本表与 `compose/dev/docker-compose.dev.yml` 注释逐行对应，并与 v4/02 §5.3 三处一致（冲突 +1 顺延时三处同步回写，E12）。
> 密码本体只在 `compose/dev/.env`（gitignore，E11）；本表登记**变量名**与用途，不登记值。

## 1. 端口登记（宿主机 = 官方默认 + 20000）

| profile | 服务 | 镜像（tag 写死小版本） | 容器端口 | 宿主机端口 | 卷 |
|---|---|---|---|---|---|
| core | MySQL 8.0 | `mysql:8.0.43` | 3306 | **23306** | micro-dev_mysql-data |
| core | Redis 7 | `redis:7.4.5` | 6379 | **26379** | micro-dev_redis-data |
| core | etcd 3.7 | `quay.io/coreos/etcd:v3.7.0` | 2379/2380 | **22379/22380** | micro-dev_etcd-data |
| core | TDengine 3 | `tdengine/tdengine:3.3.6.13` | 6041/6030 | **26041/26030** | micro-dev_tdengine-data |
| core | Kafka 4.x（KRaft 单机） | `apache/kafka:4.1.0` | 9092 | **29092** | micro-dev_kafka-data |
| edge | EMQX 5.8 | `emqx/emqx:5.8.7` | 1883/8883/18083 | **21883/28883/38083** | micro-dev_emqx-data |
| edge | APISIX 3.11 | `apache/apisix:3.11.0-debian` | 9080/9180 | **29080/29180** | —（配置存 etcd /apisix） |
| edge | MinIO | `bitnamilegacy/minio:2025.7.23-debian-12-r5` | 9000/9001 | **29000/29001** | micro-dev_minio-data |
| obs | Prometheus | `prom/prometheus:v3.5.0` | 9090 | **29090** | micro-dev_prometheus-data |
| obs | Grafana | `grafana/grafana:12.1.0` | 3000 | **23000** | micro-dev_grafana-data |
| obs | Loki / Promtail | `grafana/loki:3.5.3` / `grafana/promtail:3.5.3` | 3100 / 不映射 | **23100** / — | micro-dev_loki-data |
| obs | Jaeger all-in-one | `jaegertracing/all-in-one:1.74.0` | 16686/4317/4318 | **36686/24317/24318** | —（dev 内存态） |
| obs | Alertmanager | `prom/alertmanager:v0.28.1` | 9093 | **29093** | micro-dev_alertmanager-data |
| obs | Pyroscope（可选，ADR-24） | `grafana/pyroscope:1.13.0` | 4040 | **24040** | micro-dev_pyroscope-data |

一次性 init 容器（不占端口）：`tdengine-init`（core，改 TDengine root 默认密码）、`emqx-bootstrap`（edge，E6 幂等恢复认证器/ACL）、`minio-init`（edge，幂等建双桶）。

**明确不引入**（先登记再起，切换点 v4/04 §2）：RocketMQ / Nacos / Beanstalkd / Gotenberg（预留 **23001**，ADR-18）。

### 端口核对记录

| 日期 | 命令 | 结果 | 回写 |
|---|---|---|---|
| 2026-10-07 | `netstat -ano -p tcp`（22379~38083 号段过滤，落成后复核） | 仅 **33060** 被占（本机 MySQL X 协议端口，非本项目取号，不影响）；**22 个登记端口全部以 127.0.0.1 绑定监听**，无冲突、无需顺延 | 三处一致：v4/02 §5.3 / compose 注释 / 本表 |

### 2026-10-07 镜像选版备注（与 v4/02 §5.3 的差异说明）

- **etcd**：官方 ghcr 通道无 3.7 tag（`ghcr.io/etcd-io/etcd` 探测 404），`quay.io/coreos/etcd:v3.7.0` 可用——满足 §5.3 "etcd 3.7" 口径。
- **MinIO**：官方 `minio/minio` 2025-03 起撤出 Docker Hub、quay 仓库转私有（401）。dev 改用 Bitnami 冻结归档 `bitnamilegacy/minio:2025.7.23-debian-12-r5`（数据目录为 `/bitnami/minio/data`）；生产走云 OSS（切换点 B1，代码零改动）。
- **APISIX**：官方镜像 tag 均带 OS 后缀，定版 `3.11.0-debian`（§5.3 "APISIX 3.11" 口径不变）。

## 2. 凭据与环境变量（`compose/dev/.env`，gitignore）

| 变量 | 用途 | 消费方 |
|---|---|---|
| `COMPOSE_PROFILES` | 一处控制启动面（core/edge/obs） | docker compose |
| `MICRO_DEV_MYSQL_ROOT_PW` | MySQL root（仅人工运维） | mysql 容器 |
| `MICRO_DEV_MYSQL_APP_USER` / `MICRO_DEV_MYSQL_APP_PW` | 应用账号（首启 init 授权 `micro_%`.*） | mysql 容器 + 全部服务/工具 |
| `MICRO_DEV_REDIS_PW` | Redis requirepass | redis 容器 + 服务 |
| `MICRO_DEV_TDENGINE_PW` | TDengine root 密码（首启由默认 taosdata 改出，E7） | tdengine/tdengine-init 容器 + iotingest |
| `MICRO_DEV_EMQX_DASHBOARD_USER` / `..._PW` | EMQX Dashboard（:38083） | emqx/emqx-bootstrap 容器 |
| `MICRO_DEV_EMQX_DEVICE_USER` / `..._PW` | 设备联调平台账号（ACL：发布 up/#、订阅 down/#） | emqx-bootstrap 建号，S6 devicesim 用 |
| `MICRO_DEV_APISIX_ADMIN_KEY` | APISIX Admin API key（仅回环绑定兜底） | apisix 容器（config.yaml ${} 注入） |
| `MICRO_DEV_MINIO_ROOT_USER` / `..._PASSWORD` | MinIO 管理账号 | minio/minio-init 容器 + file 服务 |
| `MICRO_DEV_GRAFANA_ADMIN_USER` / `..._PASSWORD` | Grafana 管理员（:23000） | grafana 容器 |
| `MICRO_ADMIN_PW` | 种子管理员密码（tools/seed；未设置强告警拒绝） | 工具链（compose 不消费） |
| `MICRO_DATA_KEYS` / `MICRO_DATA_KEY_KID` | AES-256-GCM 数据密钥（keygen 产出） | 服务进程（crypto.EnvKeyProviderFromEnv） |
| `JWT_KEYS_DIR` | RS256/Ed25519 密钥目录（默认 `../micro-deploy/deploy/conf/keys`） | identity / 验签方 |

### 库/桶/键位命名约定

- MySQL 库名：`micro_<svc>`（micro_identity / micro_order / ...，tools/migrate `-svc` 自动建库；应用账号通配授权 `micro_%`——v4/02 §6.1 列表即服务名，S2-01 授权口径 `micro_%` 据此对齐）。
- TDengine 库名：`iot_db`（iotingest 首写建库，S6）。
- MinIO 双桶：`micro-file`（普通文件）/ `micro-contract`（合同归档，版本控制开启）。
- etcd 键位隔离：服务发现注册 key 照旧 ／ configcenter `/micro/config/...` ／ APISIX `/apisix`（ADR-10 三者互不相交）。

## 3. 运维备忘

- **EMQX 容器重建后**（E6）：`docker compose up emqx-bootstrap`（幂等）→ 认证器/授权源/平台账号/ACL 全部恢复。
- **EMQX 5.8 REST API 鉴权**：不再收 Dashboard Basic 认证——先 `POST /api/v5/authentication`（即 `/api/v5/login`）拿 Bearer token；认证器创建需 `mechanism`+`backend` 双字段。
- **APISIX 3.11 配置要点**（验收踩坑实录）：① `role=traditional` 时 etcd 连接读 **`deployment.etcd`**（顶层 etcd 段会被 config-default 覆盖）；② 环境变量替换语法是 **`${{VAR}}`**（`${VAR}` 为 Nginx 保留）；③ Admin API 需显式 `allow_admin`（宿主机经 docker 代理进来源 IP 是网关），宿主端口 29180 已绑 127.0.0.1 兜底。
- **TDengine REST**：`http://127.0.0.1:26041/rest/sql`，Basic `root:$MICRO_DEV_TDENGINE_PW`，401 易误判空结果（E7）。指标抓取暂缓：3.3.6.13 taosAdapter `/metrics` 返回 gzip 却缺 Content-Encoding 头（上游 quirk），S6 接入时随镜像版本复核。
- **Kafka**（E3）：advertised listener=`127.0.0.1:29092`，dev 客户端全在宿主机；`KAFKA_AUTO_CREATE_TOPICS_ENABLE=false`，topic 由 tools/mqinit 预建（E2，S5-01 落地）。
- **Prometheus 抓宿主机服务**：`host.docker.internal:91xx`（E17，容器内 127.0.0.1 指容器自己）；服务上线前 micro-go-zero 目标 DOWN 属预期。Jaeger 指标口 14269。
- **Promtail 采集**：bind mount 用 **三层**相对路径 `../../../micro-server/logs`（compose/dev 向上三层=micro-new 根，两层只到 micro-deploy）；logx JSON 字段为 `level`/`trace`（v1.10.x），Loki 可按 `{service="<svc>"}` 检索。
- **Grafana 看板**：provisioning 自动装配官方市场 **Go-Zero #19909**（JSON 已入库 `grafana/dashboards/`，数据源引用转为 provisioning uid `micro-prom`；市场下载原件含 `__inputs` 不能直接 provisioning）。
- **密钥三件套**：`deploy/conf/keys/`（gitignore）由 `go run ./tools/keygen` 产出；样例见 `deploy/conf/keys.example/`。
- **Windows 注意**（E9）：脚本一律引号包路径；bind mount 用相对路径（本 compose 已全部相对路径）；Git Bash 下 `docker run` 带容器内绝对路径参数需 `MSYS_NO_PATHCONV=1`。
