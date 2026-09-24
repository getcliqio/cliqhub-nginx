# cliqhub-nginx

Public edge router for CliqHub on Railway (`cliqhub-nginx`).

Terminates `api.cliqhub.io` and `cliqhub.io` / `www.cliqhub.io`, then proxies to private upstreams:

| Path / host | Upstream env |
|-------------|--------------|
| Web + API `/v1/*`, `/a2a/*`, SPA `/` | `BFF_UPSTREAM` |
| `/v1/sync/*` | `SYNC_UPSTREAM` |
| (required by entrypoint; not used as public Core) | `BACKEND_UPSTREAM` |

Health: `GET /nginx-health`.

## Required Railway variables

- `PORT` (Railway)
- `BFF_UPSTREAM` — e.g. `${{cliqhub-bff.RAILWAY_PRIVATE_DOMAIN}}:3001`
- `BACKEND_UPSTREAM` — Core private host (entrypoint requires it)
- `SYNC_UPSTREAM` — sync service private host
- Optional: `API_SERVER_NAMES`, `WEB_SERVER_NAMES`, `DNS_RESOLVER`

## Local topology check

```bash
./tests/nginx_topology.test.sh
```

## Railway

Point the `cliqhub-nginx` service at this repo (`main`), config path `railway.toml`, root directory `/`.
