# micro-deploy/config · configcenter 配置正本（S2-06，ADR-10）
#
# 规则：
#   - 目录结构 = <服务名>/<文件名>.json|yml|yaml，一层服务段 + 一层文件（按服务分文件）
#   - 服务段 `_platform` 为平台全局配置（跨服务消费）
#   - etcd 键位 = /micro/config/<服务名>/<文件名去扩展名>（tools/configpush 推送）
#   - 修改流程：改本目录 → PR 评审 → 合并后 CI/本地推送 etcd → 服务 listener 秒级 reload（E15）
#   - 结构校验：configpush -validate（CI PR 门槛；json 必须 JSON 对象、yml 必须映射）
#
# 首批配置项登记（S2-06）：
#   _platform/features.json    功能开关
#   _platform/greylist.json    灰度白名单（ADR-22 双通道的功能侧）
#   ops/alert_baseline.yml     告警规则参数兜底值（ops 判定 alert_candidate 用）
#   admin-bff/polling.yml      轮询间隔（ADR-02：10s 默认，可调）
#   _demo/app.yml              listener 演示专用（go run ./tools/configpush -demo）
