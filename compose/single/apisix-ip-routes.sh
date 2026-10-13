#!/bin/bash
# apisix-ip-routes.sh · 单机无域名场景的 IP 直访路由（幂等，Admin API 推送）
#   默认路由（80/9080）→ admin-bff；server_port=9083 → mobile-bff
# 用法：APISIX_ADMIN=http://127.0.0.1:9180 APISIX_KEY=<admin-key> bash apisix-ip-routes.sh
set -eu

ADMIN="${APISIX_ADMIN:-http://127.0.0.1:9180}"
KEY="${APISIX_KEY:?需要 APISIX_KEY（Admin API admin key）}"
BFF_ADMIN="${BFF_ADMIN_UPSTREAM:-admin-bff:8889}"
BFF_MOBILE="${BFF_MOBILE_UPSTREAM:-mobile-bff:8890}"

req() { # req <method> <path> [body]
  local method=$1 path=$2 body=${3:-}
  if [ -n "$body" ]; then
    curl -sS -X "$method" "$ADMIN$path" -H "X-API-KEY: $KEY" -H 'Content-Type: application/json' -d "$body"
  else
    curl -sS -X "$method" "$ADMIN$path" -H "X-API-KEY: $KEY"
  fi
  echo
}

req PUT /apisix/admin/upstreams/bff-admin "{\"id\":\"bff-admin\",\"name\":\"bff-admin\",\"type\":\"roundrobin\",\"nodes\":{\"$BFF_ADMIN\":100}}"
req PUT /apisix/admin/upstreams/bff-mobile "{\"id\":\"bff-mobile\",\"name\":\"bff-mobile\",\"type\":\"roundrobin\",\"nodes\":{\"$BFF_MOBILE\":100}}"
# mobile 路由带 vars（9083 专用口），admin 为兜底 catch-all——两者 uri 相同但匹配条件互斥
req PUT /apisix/admin/routes/ip-mobile '{"id":"ip-mobile","name":"ip-mobile","uri":"/*","vars":[["server_port","==","9083"]],"upstream_id":"bff-mobile"}'
req PUT /apisix/admin/routes/ip-admin '{"id":"ip-admin","name":"ip-admin","uri":"/*","upstream_id":"bff-admin"}'

echo "[apisix-ip-routes] done"
