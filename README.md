# micro-deploy · 部署与配置正本

部署配置单独授权、密钥边界清晰的仓库（02 §4.1）：compose（profiles：core/edge/obs）/ K3s / **configcenter 配置正本（Git 化）** / 密钥样例 / runbook。

## 目录

```
micro-deploy/
├── compose/dev/        # docker-compose.dev.yml + .env.example（S2-01 落地，15 容器全量）
├── config/             # configcenter 配置正本：按服务分文件，PR 评审 + CI 推送 etcd（S2-06 落地）
├── docs/               # 平台文档分发副本 + runbook（索引见 docs/README.md）
│   └── runbook/        # 每服务上线前补同名 runbook（五节规范见 docs/runbook/README.md）
└── k8s/                # K3s + ArgoCD 清单（阶段二，goctl kube 生成后模板化）
```

## 红线（E11：密钥出仓）

- `.env` / `keys/` / `*.key` **永不入库**（.gitignore 已挡）；`.env.example` 入库
- dev 中间件密码一律 `MICRO_DEV_*` 前缀；密钥三件套由 `tools/keygen` 生成（S2-04）
- 配置正本修改走 PR 评审 → CI 推送 etcd——**Git 即版本历史、diff 即审计、revert 即回滚**（ADR-10）

## 常用命令（S2-01 compose 落地后可用）

```bash
make up         # COMPOSE_PROFILES 全量 up -d（容器名 micro-dev-<服务>）
make up-core    # 仅 core profile（MySQL/Redis/etcd/TDengine/Kafka）
make down / ps / logs svc=mysql
```

## 提交约定（S0-03）

中文 conventional commits + 任务号（`chore(compose): S2-01 全量容器化`）；全仓 CODEOWNERS 必评审（部署与配置单独授权）；PR 走 DoD 自查模板。
