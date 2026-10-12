#!/bin/bash
# apisix-init.sh · APISIX 边缘路由初始化 + 灰度双通道（S11-06，ADR-01/22；Admin API 推送幂等）。
#
# 路由面（02 §7.1）：
#   admin./dealer./station.*.example.com → admin-bff:8889   （管理/经销商/场站 Web）
#   m.example.com                        → mobile-bff:8890  （C 端小程序/运维 App）
#   per-route 限流（limit-req 突发兜底；租户 RPM 配额在 BFF 内 QuotaLimiter——两层互不替代）
#
# 灰度（ADR-22 通道一 traffic-split）：
#   apisix-init.sh grey-on   → admin-bff 灰度组切 5%（weight 5/95，按权重分流）
#   apisix-init.sh grey-off  → 摘除灰度权重（回全量）
#   通道二（configcenter 灰度开关）：config/_platform/greylist.json（Git 正本 → make push-config）
#
# 用法：
#   APISIX_ADMIN=http://127.0.0.1:29180 APISIX_KEY=<admin-key> bash apisix-init.sh
#   bash apisix-init.sh grey-on|grey-off|status
set -eu

ADMIN="${APISIX_ADMIN:-http://127.0.0.1:29180}"
KEY="${APISIX_KEY:?需要 APISIX_KEY（Admin API admin key）}"
BFF_ADMIN="${BFF_ADMIN_UPSTREAM:-admin-bff:8889}"   # 生产容器网络服务名；dev 用 host.docker.internal:8889
BFF_MOBILE="${BFF_MOBILE_UPSTREAM:-mobile-bff:8890}"
DOMAIN="${MICRO_DOMAIN:-example.com}"

req() { # req <method> <path> [body]
  local method=$1 path=$2 body=${3:-}
  if [ -n "$body" ]; then
    curl -sS -X "$method" "$ADMIN$path" -H "X-API-KEY: $KEY" -H 'Content-Type: application/json' -d "$body"
  else
    curl -sS -X "$method" "$ADMIN$path" -H "X-API-KEY: $KEY"
  fi
}

upstream_json() { # upstream_json <id> <nodes>
  cat <<EOF
{"id":"$1","name":"$1","type":"roundrobin","nodes":$2}
EOF
}

route_bff() { # route_bff <route-id> <host-pattern-json> <upstream-id>
  local id=$1 hosts=$2 up=$3
  cat <<EOF
{"id":"$id","name":"$id","uri":"/*","hosts":$hosts,
 "upstream_id":"$up","plugins":{"limit-req":{"rate":200,"burst":100,"rejected_code":429,"key_type":"var","key":"remote_addr"}}}
EOF
}

create_upstreams() {
  req PUT /apisix/admin/upstreams/bff-admin "$(upstream_json bff-admin "{\"$BFF_ADMIN\":100}")" >/dev/null
  req PUT /apisix/admin/upstreams/bff-mobile "$(upstream_json bff-mobile "{\"$BFF_MOBILE\":100}")" >/dev/null
  echo "· upstreams bff-admin/bff-mobile 已就绪（$BFF_ADMIN / $BFF_MOBILE）"
}

create_routes() {
  # admin./dealer./station. 三 Host → admin-bff；m. → mobile-bff（jwt 校验由 BFF authz 全链处理，边缘限流兜底）
  req PUT /apisix/admin/routes/bff-admin-web "$(route_bff bff-admin-web "[\"admin.$DOMAIN\",\"dealer.$DOMAIN\",\"station.$DOMAIN\"]" bff-admin)" >/dev/null
  req PUT /apisix/admin/routes/bff-mobile "$(route_bff bff-mobile "[\"m.$DOMAIN\"]" bff-mobile)" >/dev/null
  echo "· routes bff-admin-web / bff-mobile 已就绪（$DOMAIN）"
}

# grey <weight> 灰度组：traffic-split 按 weight 把 5% 流量切到灰度 upstream（发布演练时灰度组换新版本 nodes）
grey() { # grey <weight>
  local w=$1
  local remain=$((100 - w))
  cat <<EOF
{"id":"grey-bff-admin","name":"grey-bff-admin","uri":"/*","hosts":["admin.$DOMAIN"],
 "plugins":{"traffic-split":{"rules":[{"weighted_upstreams":[{"upstream_id":"bff-admin","weight":$remain},{"upstream_id":"bff-admin-grey","weight":$w}]}]}},
 "upstream_id":"bff-admin"}
EOF
}

grey_on() {
  req PUT /apisix/admin/upstreams/bff-admin-grey "$(upstream_json bff-admin-grey "{\"$BFF_ADMIN\":100}")" >/dev/null
  req PUT /apisix/admin/routes/grey-bff-admin "$(grey 5)" >/dev/null
  echo "· 灰度通道已开：admin.$DOMAIN 5% → bff-admin-grey（ADR-22 通道一）"
}

grey_off() {
  req DELETE /apisix/admin/routes/grey-bff-admin >/dev/null
  echo "· 灰度通道已摘（全量回到 bff-admin）"
}

status() {
  echo "== upstreams =="; req GET /apisix/admin/upstreams | head -c 600; echo
  echo "== routes ==";   req GET /apisix/admin/routes  | head -c 900; echo
}

case "${1:-init}" in
  init)
    create_upstreams
    create_routes
    status
    ;;
  grey-on)  grey_on ;;
  grey-off) grey_off ;;
  status)   status ;;
  *) echo "用法: $0 {init|grey-on|grey-off|status}" >&2; exit 1 ;;
esac
