# Deployment — private server behind a Cloudflare Tunnel

This is the deployment the user actually described for this project: a
private server on the local network (no public IP exposed), reached
through a [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
rather than a traditional reverse proxy with Let's Encrypt/ACME. That
changes the shape of this setup in one important way worth stating up
front: **nothing here opens an inbound port on the server**. `cloudflared`
makes an outbound-only connection to Cloudflare's edge; Cloudflare
terminates TLS there and forwards matched requests down that tunnel to
whichever internal service you configure. There is no Traefik, no
certificate to renew, and no port 80/443 to open in a firewall.

Step 1 below happens in the Cloudflare dashboard, not in this repo —
nothing in `docker-compose.prod.yml` can do it for you.

## 1. Reuse the server's existing tunnel — don't create a second one

**This compose file has no `cloudflared` service.** The target server
already runs one long-lived, token-based `cloudflared` container serving
every app on that host (confirmed live before writing this: it runs
`tunnel run` with a `TUNNEL_TOKEN` env var — routing rules live in the
Cloudflare dashboard, not a local `config.yml` — and other apps on the
box, e.g. an existing Strapi instance, reach it the same way this file
sets up: by sharing its Docker network, not by running their own tunnel).
Running a second `cloudflared` would mean a second tunnel to manage for
no benefit — one more Public Hostname route on the existing tunnel does
the same job.

That existing tunnel's container is attached to an external Docker
network — on the reference deployment this is named `ingress`, and
`docker-compose.prod.yml` declares it as `external: true` for exactly
that reason. **If your existing tunnel's network has a different name,
change the `ingress:` network name in `docker-compose.prod.yml` (and the
`networks:` list on the `control-plane-api`/`grafana` services) to match
before running `up`** — `docker compose` fails loudly at startup if the
named external network doesn't exist, it won't silently create a
same-named-but-disconnected one.

In the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/),
open the existing tunnel's **Public Hostname** tab and add one route per
service you want reachable from the internet:

| Public hostname | Service type | URL |
|---|---|---|
| `control-plane.<your-domain>` | HTTP | `control-plane-api:3000` |
| `grafana.<your-domain>` | HTTP | `grafana:3000` |

`control-plane-api`/`grafana` here are the compose service names — once
both containers are on the tunnel's network, Docker DNS resolves them, no
IP addresses involved. Do **not** add a route for `prometheus:9090` —
Prometheus has no authentication of its own; it's only meant to be
reached by Grafana over the internal network, never from the internet.

Cloudflare creates the DNS record for you when you add the route; you
don't need to touch your domain's DNS panel separately.

## 2. Generate secrets

```bash
cd infra
cp .env.prod.example .env.prod
```

Fill in `.env.prod` (never commit it — already covered by the repo's
`.env.*` gitignore pattern). Every value that needs generating has the
exact command in `.env.prod.example`'s own comments. Easy to get wrong:
`SECRETS_MASTER_KEY` and `JWT_SECRET` must be **different** values —
never reuse one key for two cryptographic purposes (see
`SecretsService`'s own doc comment in `packages/secrets`).

## 3. Build and run

```bash
cd infra
docker compose -f docker-compose.prod.yml --env-file .env.prod build
docker compose -f docker-compose.prod.yml --env-file .env.prod run --rm migrate
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d
```

`migrate` is deliberately a separate, explicit step (`run --rm`, not
started automatically by `up -d`) — run it once before the first `up`,
and again after pulling any change that added a Prisma migration. This
exact pattern (the `control-plane-api` image, `npx prisma migrate
deploy`) was verified live during this project's own build: the image
successfully ran migrations against a real, empty Postgres.

Confirm things are actually up:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod ps
curl https://control-plane.<your-domain>/health/ready
```

## 4. Bootstrap the first tenant

`POST /tenants` is gated by `BOOTSTRAP_TOKEN` (see `.env.prod`) — call it
once through the public hostname to create your first tenant + owner
account, then treat that token as spent (rotate it on the next deploy if
you're being careful — it has no other use).

## 5. Grafana

Reachable at `https://grafana.<your-domain>` once step 2's route is in
place. First login is `admin` / whatever you set as
`GRAFANA_ADMIN_PASSWORD` — Grafana forces a password change on first
login. The Prometheus datasource and a starter `control-plane-api`
dashboard (process CPU/memory/event-loop-lag, from `infra/grafana/
dashboards/control-plane-api.json`) are provisioned automatically; no
manual "add datasource" step needed.

## What's deliberately not here

- **`federation-worker` has no metrics endpoint** — it has no HTTP server
  to hang one off (see `IMPLEMENTATION_STATUS.md`, FAZA 9b). Its restart
  count / logs are visible via `docker compose logs federation-worker` /
  `docker compose ps`, just not scraped into Prometheus yet.
- **No automated image registry / CI deploy step.** `docker compose build`
  builds from source on the server itself; there is no `docker push`/pull
  from a registry configured. Fine for a single-server deployment, worth
  revisiting if this ever needs to run on more than one host.
- **No automatic TLS renewal to configure** — that's the whole point of
  the Cloudflare Tunnel approach; Cloudflare handles it at their edge.

## 6. Running the test suite outside Docker

`npm test` / `npm run test:e2e` do **not** work right after a bare
`npm ci` at the repo root — found live running the full suite against
this deployment. The app's own multi-stage `Dockerfile` builds are fine
(they do this already), but a standalone `npm ci` skips two steps the
Dockerfile does explicitly, and jest fails with TypeScript errors that
look like missing types (`Module '"@prisma/client"' has no exported
member 'Tenant'`) and unresolvable workspace imports (`Cannot find
module '@pterocontrol/secrets'`) — neither is a real code problem, both
are just steps that didn't run yet:

```bash
npm ci
npm run build --workspace=@pterocontrol/pterodactyl-sdk
npm run build --workspace=@pterocontrol/rabbitmq
npm run build --workspace=@pterocontrol/secrets
npx prisma generate --schema services/control-plane-api/prisma/schema.prisma

npm test --workspace=services/control-plane-api
npm run test:e2e --workspace=services/control-plane-api
npm test --workspace=services/federation-worker
```

The three `packages/*` workspaces are consumed via their `dist/`
output (`"main": "dist/index.js"` in each `package.json`), and Prisma's
generated client only exists after `prisma generate` runs — the
Dockerfile's `build` stage does both before compiling the app; a plain
`npm ci` on its own does neither. `test:e2e` additionally needs Docker
on `PATH` (it spins up its own throwaway, isolated Postgres +
RabbitMQ — see `services/control-plane-api/test/global-setup.js` —
never the ones this compose file runs, and never on the same ports).

## Verified live on the reference deployment

Confirmed end-to-end against this project's own target server (not
just "container is running" — an actual internet → Cloudflare →
tunnel → `control-plane-api:3000` request, checked against both sides'
logs for errors):

```bash
curl -I https://control-plane.wlosek.ovh          # -> 404 (no root route; proves it reached Express)
curl https://control-plane.wlosek.ovh/health/ready # -> {"status":"ok","dependencies":{"database":"connected","rabbitmq":"connected"}}
```

Full test suite (25 unit + 3 e2e suites, `control-plane-api`; 11 unit
suites, `federation-worker`) passes: 237/237 tests, 0 failures.
