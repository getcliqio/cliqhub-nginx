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

envsubst '${PORT} ${BFF_UPSTREAM} ${BACKEND_UPSTREAM} ${SYNC_UPSTREAM} ${API_SERVER_NAMES} ${WEB_SERVER_NAMES} ${DNS_RESOLVER}' \
    < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
