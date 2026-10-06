# micro-deploy 常用命令（S0-02；compose/dev 于 S2-01 落地）
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

.DEFAULT_GOAL := help
COMPOSE := docker compose -f compose/dev/docker-compose.dev.yml

_guard:
	@test -f compose/dev/docker-compose.dev.yml || { echo "compose/dev/docker-compose.dev.yml 未落地（S2-01）"; exit 1; }

## up: 全 profile 启动（15 容器，COMPOSE_PROFILES 在 .env 控制）
up: _guard
	$(COMPOSE) up -d

## up-core: 仅 core profile（MySQL/Redis/etcd/TDengine/Kafka）
up-core: _guard
	COMPOSE_PROFILES=core $(COMPOSE) up -d

## down: 停止并移除容器（卷保留）
down: _guard
	$(COMPOSE) down

## ps: 容器状态
ps: _guard
	$(COMPOSE) ps

## logs: 看日志；用法 make logs svc=mysql
logs: _guard
	@test -n "$(svc)" || { echo "用法：make logs svc=<容器短名>"; exit 1; }
	$(COMPOSE) logs -f --tail=200 $(svc)

## push-config: 配置正本校验并推送 etcd（tools/configpush 于 S2-06 落地）
push-config:
	@test -d config || { echo "config/ 配置正本未落地（S2-06）"; exit 1; }
	@test -n "$(key)" || { echo "用法：make push-config key=<服务配置文件>"; exit 1; }
	cd ../micro-server && go run ./tools/configpush -f ../micro-deploy/config/$(key)

## help: 目标清单
help:
	@echo "up / up-core / down / ps / logs svc=x / push-config key=x（S2 落地后生效）"
