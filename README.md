# cliqhub-nginx

Public edge router for CliqHub on Railway (`cliqhub-nginx`).

Terminates `api.cliqhub.io`, `cliqhub.io` / `www.cliqhub.io` and `content.cliqhub.io`, then proxies to private upstreams:

| Path / host | Upstream env |
|-------------|--------------|
| Web + API `/v1/*`, `/a2a/*`, SPA `/` | `BFF_UPSTREAM` |
| `/v1/sync/*` | `SYNC_UPSTREAM` |
| `/v1/artifacts/upload`, `/v1/artifacts/download` (both hosts; streamed, see below) | `BFF_UPSTREAM` |
| `content.cliqhub.io`: `/hb/<sha256>/…` only (hug frontends; see below) | `BFF_UPSTREAM` |
| (required by entrypoint; not used as public Core) | `BACKEND_UPSTREAM` |

Health: `GET /nginx-health`.

## Required Railway variables

- `PORT` (Railway)
- `BFF_UPSTREAM` — e.g. `${{cliqhub-bff.RAILWAY_PRIVATE_DOMAIN}}:3001`
- `BACKEND_UPSTREAM` — Core private host (entrypoint requires it)
- `SYNC_UPSTREAM` — sync service private host
- `ARTIFACT_MAX_MB` — largest file upload in MB; set it to the same value as Core's `CLIQ_ARTIFACT_MAX_MB` (default 50). The entrypoint refuses to start without it.
- Optional: `API_SERVER_NAMES`, `WEB_SERVER_NAMES`, `CONTENT_SERVER_NAMES` (default `content.cliqhub.io`), `DNS_RESOLVER`

## Files

Every file byte goes through the BFF to Core; only Core talks to R2 (no presigned URLs).
`/v1/artifacts/upload` streams the request (`proxy_request_buffering off`, `client_max_body_size ${ARTIFACT_MAX_MB}m`,
300s timeouts) so an oversized upload is refused here first. `/v1/artifacts/download` streams the response
(`proxy_buffering off`, `gzip off`) so `Range` / `Content-Length` pass through.

## Hug frontends (content host)

`content.cliqhub.io` serves only the files of hug bundles, `GET /hb/<sha256>/<path>`, from the BFF's content route;
everything else there is 404. The Hub page frames them in a sandboxed `<iframe>` (PLAN-hug-widgets §7), so this
server adds **no headers** — in particular no `X-Frame-Options` — and the BFF's own pass through (a CSP with
`frame-ancestors` the Hub's origin, `nosniff`, no referrer, CORS for fonts, immutable caching). `Host` is kept: the
BFF answers `/hb/` only when it is its `CONTENT_ORIGIN` host. Cookies are not forwarded.

To deploy it: DNS and TLS for `content.cliqhub.io` on this service (Railway custom domain), and on the BFF
`CONTENT_ORIGIN=https://content.cliqhub.io` and `HUB_ORIGIN="https://cliqhub.io https://www.cliqhub.io"` — every host the Hub is served on (`WEB_SERVER_NAMES`), or hugs won't load on the missing one.

## Local topology check

```bash
./tests/nginx_topology.test.sh
```

## Railway

Point the `cliqhub-nginx` service at this repo (`main`), config path `railway.toml`, root directory `/`.
