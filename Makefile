# micro-deploy 常用命令（S2-01 起生效）
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

.DEFAULT_GOAL := help
COMPOSE := docker compose -f compose/dev/docker-compose.dev.yml

_guard:
	@test -f compose/dev/docker-compose.dev.yml || { echo "compose/dev/docker-compose.dev.yml 缺失"; exit 1; }
	@test -f compose/dev/.env || { echo "compose/dev/.env 缺失——先 cp .env.example .env 并填强随机密码"; exit 1; }

## up: 全 profile 启动（15 常驻 + 一次性 init，COMPOSE_PROFILES 在 .env 控制）
up: _guard
	$(COMPOSE) up -d

## up-core: 仅 core profile（MySQL/Redis/etcd/TDengine/Kafka）
up-core: _guard
	COMPOSE_PROFILES=core $(COMPOSE) up -d

## down: 停止并移除容器（named volume 保留）
down: _guard
	$(COMPOSE) down

## ps: 容器状态
ps: _guard
	$(COMPOSE) ps

## logs: 看日志；用法 make logs svc=mysql
logs: _guard
	@test -n "$(svc)" || { echo "用法：make logs svc=<容器短名>"; exit 1; }
	$(COMPOSE) logs -f --tail=200 $(svc)

## bootstrap-emqx: EMQX 认证器/ACL 幂等恢复（E6：容器重建后必跑）
bootstrap-emqx: _guard
	COMPOSE_PROFILES=edge $(COMPOSE) up emqx-bootstrap

## envcheck: 中间件连通体检 5/5（同 micro-server make envcheck）
envcheck:
	cd ../micro-server && go run ./tools/envcheck

## compose-check: compose 文件语法/插值校验（CI 同款，用 .env.example 避免依赖本机 .env）
compose-check:
	docker compose -f compose/dev/docker-compose.dev.yml --env-file compose/dev/.env.example config -q

## config-validate: 配置正本结构校验（CI PR 门槛同款，无需 etcd）
config-validate:
	cd ../micro-server && go run ./tools/configpush -dir ../micro-deploy/config -validate

## push-config: 推送配置正本到 etcd；用法 make push-config file=ops/alert_baseline.yml（省略 file= 全量推送）
push-config: _guard
	@test -d config || { echo "config/ 配置正本缺失（S2-06）"; exit 1; }
	cd ../micro-server && go run ./tools/configpush -dir ../micro-deploy/config $(if $(file),-file $(file),)

## keys: 生成密钥三件套 → deploy/conf/keys（keygen）
keys:
	cd ../micro-server && go run ./tools/keygen

## seed: 种子数据（MICRO_ADMIN_PW 必须已设置）
seed:
	cd ../micro-server && go run ./tools/seed

## help: 目标清单
help:
	@echo "up / up-core / down / ps / logs svc=x / bootstrap-emqx"
	@echo "envcheck / compose-check / config-validate / push-config [file=x]"
	@echo "keys / seed"
