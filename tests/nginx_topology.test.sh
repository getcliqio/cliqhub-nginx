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
export DNS_RESOLVER=127.0.0.11

envsubst '${PORT} ${BFF_UPSTREAM} ${BACKEND_UPSTREAM} ${SYNC_UPSTREAM} ${API_SERVER_NAMES} ${WEB_SERVER_NAMES} ${DNS_RESOLVER}' \
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

echo "OK: nginx topology (api.cliqhub.io → bff /v1+/a2a; cliqhub.io → bff; DNS re-resolve)"
