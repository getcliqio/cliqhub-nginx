#!/bin/sh
set -e

if [ -z "$PORT" ]; then
    echo "FATAL: PORT not set by Railway" >&2
    exit 1
fi

if [ -z "$BFF_UPSTREAM" ]; then
    echo "FATAL: BFF_UPSTREAM environment variable is not set" >&2
    exit 1
fi

if [ -z "$BACKEND_UPSTREAM" ]; then
    echo "FATAL: BACKEND_UPSTREAM environment variable is not set" >&2
    exit 1
fi

if [ -z "$SYNC_UPSTREAM" ]; then
    echo "FATAL: SYNC_UPSTREAM environment variable is not set" >&2
    exit 1
fi

# Largest file upload, in MB — the same value as Core's CLIQ_ARTIFACT_MAX_MB, so an oversized
# upload is refused here before it reaches the BFF or Core (PLAN-hug-requests §6.6.6).
if [ -z "$ARTIFACT_MAX_MB" ]; then
    echo "FATAL: ARTIFACT_MAX_MB environment variable is not set (use Core's CLIQ_ARTIFACT_MAX_MB)" >&2
    exit 1
fi
case "$ARTIFACT_MAX_MB" in
    *[!0-9]*) echo "FATAL: ARTIFACT_MAX_MB must be a whole number of MB, got '$ARTIFACT_MAX_MB'" >&2; exit 1 ;;
esac

# Host-based routing (Slice F). Override in Railway if needed.
: "${API_SERVER_NAMES:=api.cliqhub.io}"
: "${WEB_SERVER_NAMES:=cliqhub.io www.cliqhub.io}"

# Prefer the container's nameserver so .railway.internal resolves; fall back
# to Docker embedded DNS for local compose. nginx requires IPv6 literals in [].
if [ -z "$DNS_RESOLVER" ]; then
    DNS_RESOLVER=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null || true)
fi
: "${DNS_RESOLVER:=127.0.0.11}"
case "$DNS_RESOLVER" in
    *:*)
        case "$DNS_RESOLVER" in
            \[*\]) ;;
            *) DNS_RESOLVER="[${DNS_RESOLVER}]" ;;
        esac
        ;;
esac

export API_SERVER_NAMES WEB_SERVER_NAMES DNS_RESOLVER

echo "[nginx] BFF_UPSTREAM=${BFF_UPSTREAM}"
echo "[nginx] BACKEND_UPSTREAM=${BACKEND_UPSTREAM}"
echo "[nginx] SYNC_UPSTREAM=${SYNC_UPSTREAM}"
echo "[nginx] DNS_RESOLVER=${DNS_RESOLVER}"
echo "[nginx] ARTIFACT_MAX_MB=${ARTIFACT_MAX_MB}"

envsubst '${PORT} ${BFF_UPSTREAM} ${BACKEND_UPSTREAM} ${SYNC_UPSTREAM} ${API_SERVER_NAMES} ${WEB_SERVER_NAMES} ${DNS_RESOLVER} ${ARTIFACT_MAX_MB}' \
    < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
