# runbook · catalog（商品与价目服务）

> 服务：catalog ｜ RPC 8083 / metrics 9103 ｜ module `micro-server/services/catalog`
> 职责一句话：商品/SKU/价目（RETAIL/JOINT 等 price_type）/场站商品映射/质保策略维护，订单与库存的商品域锚点。
> 关联任务：S4-02 ｜ 最近更新：2026-10-13

## 1. 职责与依赖

**职责边界**：catalog_db（product/sku/price/station_product/warranty_policy）唯一写入方。订单下单时读价目（无可用价目即拒绝）；EXT_WARRANTY 类型 SKU 走延保销售链路（S5/S9）。

| 依赖 | 用途 | 超时 | 降级 |
|---|---|---|---|
| MySQL（micro_catalog） | 全部数据 | 3s | sqlx 熔断 |
| etcd | 发现/雪花/configcenter | 5s | 后台重试 |

## 2. 健康指标

- RED：`:9103/metrics`；业务：SetPrice 调用量（变价频率）、无价目拒绝率。

## 3. 常见故障

| 症状 | 定位 | 处置 |
|---|---|---|
| 下单报"无可用价目" | SKU 未设 RETAIL 价 | SetPrice 后重试（chaosmoke/p5perf 均此路径） |
| 延保月数错误 | EXT_WARRANTY SKU spec JSON `{"months":N}` | 改 spec 后重下；已产质保走退保链 |
| goctl 生成物风格漂移 | --style go_zero 缺失 | 禁手改生成物；重跑 goctl |

## 4. 发布与回滚

- 迁移：`go run ./tools/migrate -svc catalog up`；启动前置 `source tools/devenv.sh micro_catalog`。

## 5. 紧急操作

- 价目错误紧急下架：price 行软删 + 站内公告；存量订单不受影响（下单时快照）。
- station_product 解绑即时生效（场站设备可售范围）。
