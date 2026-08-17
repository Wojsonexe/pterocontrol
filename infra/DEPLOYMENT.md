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

Steps 1-2 below happen in the Cloudflare dashboard, not in this repo —
nothing in `docker-compose.prod.yml` can do them for you.

## 1. Create the tunnel

In the [Cloudflare Zero Trust dashboard](https://one.dash.cloudflare.com/):
**Networks → Tunnels → Create a tunnel → Cloudflared → name it** (e.g.
`pterocontrol`) **→ Docker** as the connector environment. Cloudflare
shows you a token — copy it into `infra/.env.prod` as
`CLOUDFLARE_TUNNEL_TOKEN` (see step 4). You do not need to run the
`docker run` command Cloudflare suggests on that screen; the token is all
`docker-compose.prod.yml`'s `cloudflared` service needs, and the compose
file already has the right image/command.

## 2. Route your domain to the internal services

Still in the tunnel's configuration (**Public Hostname** tab), add one
route per service you want reachable from the internet:

| Public hostname | Service type | URL |
|---|---|---|
| `control-plane.<your-domain>` | HTTP | `control-plane-api:3000` |
| `grafana.<your-domain>` | HTTP | `grafana:3000` |

`control-plane-api`/`grafana` here are the compose service names — DNS
inside the tunnel's Docker network resolves them, no IP addresses
involved. Do **not** add a route for `prometheus:9090` — Prometheus has
no authentication of its own; it's only meant to be reached by Grafana
over the internal network, never from the internet.

Cloudflare creates the DNS record for you when you add the route; you
don't need to touch your domain's DNS panel separately.

## 3. Generate secrets

```bash
cd infra
cp .env.prod.example .env.prod
```

Fill in `.env.prod` (never commit it — already covered by the repo's
`.env.*` gitignore pattern). Every value that needs generating has the
exact command in `.env.prod.example`'s own comments. Two that are easy to
get wrong:

- `SECRETS_MASTER_KEY` and `JWT_SECRET` must be **different** values —
  never reuse one key for two cryptographic purposes (see
  `SecretsService`'s own doc comment in `packages/secrets`).
- `CLOUDFLARE_TUNNEL_TOKEN` is the token from step 1, not something you
  generate yourself.

## 4. Build and run

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

## 5. Bootstrap the first tenant

`POST /tenants` is gated by `BOOTSTRAP_TOKEN` (see `.env.prod`) — call it
once through the public hostname to create your first tenant + owner
account, then treat that token as spent (rotate it on the next deploy if
you're being careful — it has no other use).

## 6. Grafana

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
