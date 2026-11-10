#!/usr/bin/env bash
# Assert rendered nginx topology: both public hosts → BFF; Core API not public.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export PORT=8080
export BFF_UPSTREAM=bff.internal:3001
export BACKEND_UPSTREAM=backend.internal:4000
export SYNC_UPSTREAM=sync.internal:3002
export API_SERVER_NAMES=api.cliqhub.io
export WEB_SERVER_NAMES='cliqhub.io www.cliqhub.io'
export CONTENT_SERVER_NAMES=content.cliqhub.io
export DNS_RESOLVER=127.0.0.11
export ARTIFACT_MAX_MB=50

envsubst '${PORT} ${BFF_UPSTREAM} ${BACKEND_UPSTREAM} ${SYNC_UPSTREAM} ${API_SERVER_NAMES} ${WEB_SERVER_NAMES} ${CONTENT_SERVER_NAMES} ${DNS_RESOLVER} ${ARTIFACT_MAX_MB}' \
    < "$ROOT/nginx.conf.template" > "$TMP/nginx.conf"

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q 'server_name api.cliqhub.io' "$TMP/nginx.conf" || fail 'missing api.cliqhub.io server'
grep -q 'server_name cliqhub.io www.cliqhub.io _' "$TMP/nginx.conf" || fail 'missing SPA server_name'
grep -q 'map \$http_x_client' "$TMP/nginx.conf" && fail 'X-Client map must be removed'
grep -q 'proxy_pass http://\$api_upstream' "$TMP/nginx.conf" && fail 'legacy $api_upstream must be removed'
grep -q 'resolver 127.0.0.11 valid=10s ipv6=on' "$TMP/nginx.conf" || fail 'missing DNS resolver'

# api host: /v1 → BFF (not Core API)
awk '/server_name api.cliqhub.io/,/^    }/' "$TMP/nginx.conf" | grep -q 'bff.internal:3001' \
    || fail 'api host must proxy /v1 to bff'
awk '/server_name api.cliqhub.io/,/^    }/' "$TMP/nginx.conf" | grep -q 'location /a2a/' \
    || fail 'api host must expose /a2a/ to bff'
awk '/server_name api.cliqhub.io/,/^    }/' "$TMP/nginx.conf" | grep -q 'backend.internal:4000' \
    && fail 'api host must not proxy /v1 to backend'

# spa host: /v1 → bff
awk '/server_name cliqhub.io/,/^    }/' "$TMP/nginx.conf" | grep -q 'bff.internal:3001' \
    || fail 'SPA host must proxy /v1 to bff'

# both hosts return 404 for /api/
grep -c 'location /api/' "$TMP/nginx.conf" | grep -qx '2' \
    || fail 'expected two /api/ 404 locations (api + spa hosts)'

# Files: both hosts stream uploads (no request buffering, the system limit) and downloads
# (no response buffering, no gzip) to the BFF (PLAN-hug-requests §6.6.6).
grep -c 'location = /v1/artifacts/upload {' "$TMP/nginx.conf" | grep -qx '2' || fail 'expected an upload location on both hosts'
grep -c 'location = /v1/artifacts/download {' "$TMP/nginx.conf" | grep -qx '2' || fail 'expected a download location on both hosts'
for host in 'api.cliqhub.io' 'cliqhub.io www.cliqhub.io'; do
    server="$(awk "/server_name ${host}/,/^    }/" "$TMP/nginx.conf")"
    upload="$(printf '%s\n' "$server" | awk '/location = \/v1\/artifacts\/upload/,/^        }/')"
    download="$(printf '%s\n' "$server" | awk '/location = \/v1\/artifacts\/download/,/^        }/')"
    printf '%s' "$upload" | grep -q 'bff.internal:3001' || fail "$host: upload must go to the bff"
    printf '%s' "$upload" | grep -q 'client_max_body_size 50m;' || fail "$host: upload must use ARTIFACT_MAX_MB"
    printf '%s' "$upload" | grep -q 'proxy_request_buffering off;' || fail "$host: upload must not buffer the request"
    printf '%s' "$upload" | grep -q 'proxy_read_timeout 300s;' || fail "$host: upload needs a long read timeout"
    printf '%s' "$download" | grep -q 'proxy_buffering off;' || fail "$host: download must not buffer the response"
    printf '%s' "$download" | grep -q 'gzip off;' || fail "$host: download must not be gzipped"
    printf '%s' "$server" | grep -q 'backend.internal:4000' && fail "$host: files must never go to Core directly"
done
grep -q 'ARTIFACT_MAX_MB' "$ROOT/entrypoint.sh" || fail 'entrypoint must require ARTIFACT_MAX_MB'

# Hug frontends (PLAN-hug-widgets §7): content.cliqhub.io serves only /hb/<sha256>/… from the BFF, with the
# BFF's own headers — no X-Frame-Options (the Hub frames them), no cookies forwarded, nothing else.
content="$(awk '/server_name content.cliqhub.io/,/^    }/' "$TMP/nginx.conf")"
[ -n "$content" ] || fail 'missing content.cliqhub.io server'
printf '%s' "$content" | grep -q 'location ~ ^/hb/\[0-9a-f\]{64}/' || fail 'content host must serve /hb/<sha256>/'
printf '%s' "$content" | grep -q 'bff.internal:3001' || fail 'content host must proxy /hb/ to the bff'
printf '%s' "$content" | grep -q 'proxy_set_header Host \$host;' || fail 'content host must keep Host (the BFF answers only for it)'
printf '%s' "$content" | grep -q 'proxy_set_header Cookie "";' || fail 'content host must not forward cookies'
printf '%s' "$content" | grep -q 'limit_except GET' || fail 'content host must allow GET/HEAD only'
printf '%s' "$content" | grep -q 'add_header' && fail 'content host must add no headers (no X-Frame-Options)'
printf '%s' "$content" | grep -q 'location /v1/' && fail 'content host must not serve the API'
printf '%s' "$content" | grep -q 'backend.internal:4000' && fail 'content host must never reach Core'
[ "$(printf '%s' "$content" | grep -c 'proxy_pass')" = "1" ] || fail 'content host must proxy only /hb/'
grep -q 'CONTENT_SERVER_NAMES:=content.cliqhub.io' "$ROOT/entrypoint.sh" || fail 'entrypoint must default CONTENT_SERVER_NAMES'

echo "OK: nginx topology (api.cliqhub.io → bff /v1+/a2a; cliqhub.io → bff; content.cliqhub.io → bff /hb/ only; DNS re-resolve; streamed file upload/download)"
