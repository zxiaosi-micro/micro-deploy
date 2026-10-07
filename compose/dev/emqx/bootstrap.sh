#!/bin/sh
# S2-02 · EMQX bootstrap（幂等，E6：认证器/ACL 随容器重建丢失，重跑一次即恢复）
# 执行方式：docker compose up emqx-bootstrap（depends_on emqx healthy）
# 说明：EMQX 5.8 REST API 不收 Dashboard Basic 认证——先 POST /api/v5/login 换 Bearer token。
# 建内容：
#   1) 密码认证器（password_based:built_in_database，bcrypt）——设备一机一密载体
#   2) 授权源 built_in_database —— ACL 规则载体
#   3) 平台联调账号（MICRO_DEV_EMQX_DEVICE_USER/PW）+ ACL：
#      允许发布 up/# 、订阅 down/#（S6 正式口径=设备仅 up/{tenant}/{pk}/{自身SN}/#，v4/02 §7.2）
# 各步骤先 GET 查存在性再创建/更新，可反复执行。
set -eu

API="http://emqx:18083/api/v5"
DASH_USER="${MICRO_DEV_EMQX_DASHBOARD_USER:?MICRO_DEV_EMQX_DASHBOARD_USER 未设置}"
DASH_PW="${MICRO_DEV_EMQX_DASHBOARD_PW:?MICRO_DEV_EMQX_DASHBOARD_PW 未设置}"
DEV_USER="${MICRO_DEV_EMQX_DEVICE_USER:?MICRO_DEV_EMQX_DEVICE_USER 未设置}"
DEV_PW="${MICRO_DEV_EMQX_DEVICE_PW:?MICRO_DEV_EMQX_DEVICE_PW 未设置}"
CT="-H Content-Type:application/json"

echo "[emqx-bootstrap] 等待 Dashboard API 就绪..."
i=0
while [ $i -lt 60 ]; do
  if curl -sf -o /dev/null "$API/status"; then break; fi
  i=$((i+1))
  [ $i = 60 ] && { echo "[emqx-bootstrap] API 未就绪，失败"; exit 1; }
  sleep 2
done

# ---- 0) 登录换 Bearer token（5.8 起 API 不收 Basic）----
TOKEN=$(curl -sf $CT -X POST "$API/login" \
  -d "{\"username\":\"${DASH_USER}\",\"password\":\"${DASH_PW}\"}" \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] || { echo "[emqx-bootstrap] Dashboard 登录失败（检查 MICRO_DEV_EMQX_DASHBOARD_*）"; exit 1; }

api() { # api METHOD PATH [BODY] → HTTP 状态码（Authorization 头在函数内引用 $TOKEN，避免分词把 token 拆成 URL）
  local m="$1" p="$2" b="${3:-}"
  if [ -n "$b" ]; then
    curl -s -o /dev/null -w '%{http_code}' -H "Authorization:Bearer $TOKEN" $CT -X "$m" "$API$p" -d "$b"
  else
    curl -s -o /dev/null -w '%{http_code}' -H "Authorization:Bearer $TOKEN" -X "$m" "$API$p"
  fi
}
api_body() { # api_body METHOD PATH [BODY] → 响应体
  local m="$1" p="$2" b="${3:-}"
  if [ -n "$b" ]; then
    curl -s -H "Authorization:Bearer $TOKEN" $CT -X "$m" "$API$p" -d "$b"
  else
    curl -s -H "Authorization:Bearer $TOKEN" -X "$m" "$API$p"
  fi
}

# ---- 1) 密码认证器：存在即跳过，否则 POST（mechanism+backend 双字段为 5.8 形状）----
echo "[emqx-bootstrap] 检查/创建密码认证器..."
if api_body GET "/authentication" | grep -q 'built_in_database'; then
  echo "[emqx-bootstrap]   已存在，跳过"
else
  code=$(api POST "/authentication" \
    '{"mechanism":"password_based","backend":"built_in_database","password_hash_algorithm":{"name":"bcrypt"},"user_id_type":"username"}')
  [ "$code" = 200 ] || [ "$code" = 201 ] || [ "$code" = 204 ] || { echo "[emqx-bootstrap]   创建失败（HTTP $code）"; exit 1; }
  echo "[emqx-bootstrap]   已创建"
fi

# ---- 2) 授权源 built_in_database：存在即跳过 ----
echo "[emqx-bootstrap] 检查/启用内置数据库授权源..."
if api_body GET "/authorization/sources" | grep -q 'built_in_database'; then
  echo "[emqx-bootstrap]   已存在，跳过"
else
  code=$(api POST "/authorization/sources" '{"type":"built_in_database","enable":true}')
  [ "$code" = 200 ] || [ "$code" = 201 ] || [ "$code" = 204 ] || { echo "[emqx-bootstrap]   启用失败（HTTP $code）"; exit 1; }
  echo "[emqx-bootstrap]   已启用"
fi

# ---- 3) 平台账号：存在即跳过，否则创建（409/400 = 已存在）----
echo "[emqx-bootstrap] 检查/创建平台账号 ${DEV_USER}..."
code=$(api POST "/authentication/password_based:built_in_database/users" \
  "{\"user_id\":\"${DEV_USER}\",\"password\":\"${DEV_PW}\",\"is_superuser\":false}")
case "$code" in
  200|201|204) echo "[emqx-bootstrap]   已创建" ;;
  400|409)     echo "[emqx-bootstrap]   已存在，跳过" ;;
  *) echo "[emqx-bootstrap]   创建失败（HTTP $code）"; exit 1 ;;
esac

# ---- 4) 平台账号 ACL（PUT 全量覆盖 = 幂等；up 只发 / down 只订）----
echo "[emqx-bootstrap] 写入平台账号 ACL..."
code=$(api PUT "/authorization/sources/built_in_database/rules/users/${DEV_USER}" \
  '{"username":"'"${DEV_USER}"'","rules":[{"permission":"allow","action":"publish","topic":"up/#"},{"permission":"allow","action":"subscribe","topic":"down/#"},{"permission":"deny","action":"all","topic":"#"}]}')
[ "$code" = 200 ] || [ "$code" = 201 ] || [ "$code" = 204 ] || { echo "[emqx-bootstrap] ACL 写入失败（HTTP $code）"; exit 1; }

echo "[emqx-bootstrap] 完成：认证器 + 授权源 + 平台账号 + ACL 就绪（幂等，可重跑）"
