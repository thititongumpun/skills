---
name: 1minhotspot-stack
argument-hint: "[status | logs <service> | deploy <app> | rollback <app> [tag] | backup | <change request for an app>]"
description: Change, build, ship, and verify the 1minhotspot-stack monorepo apps (worker, fb-bot, warehouse + warehouse-hub, studio on the homelab docker compose; web on Cloudflare Workers) — how the apps connect, moon tests, GHCR publish workflows and release tags, pulling a new image onto the homelab via deploy/homelab/compose.yml, health checks, logs, backups, and image-tag rollback. Use when the user mentions 1minhotspot, 1minhotspot-worker, fb-auto-reply / fb-bot, warehouse / warehouse-hub, studio (ex lao-lotto), 1minhotspot.com, asks whether the stack is healthy, wants an app deployed or rolled back, or asks how the pieces talk to each other. n8n workflows belong to my-facebook-reels-workflows; n8n version bumps to n8n-upgrade.
---

# 1minhotspot stack

The deliverable is the new image (or Worker build) running on its target, its
healthcheck green, and the previous tag written down so it can go back. A
merged commit is not done; a `healthy` container with a clean log tail is.

## Scope — what this skill owns

| Part | Here |
| --- | --- |
| `apps/worker`, `apps/fb-bot`, `apps/warehouse` (+ `hub/`), `apps/studio` | **this skill**: build, publish, homelab deploy, prove, rollback |
| `apps/web` | **this skill**: Cloudflare Workers build/deploy, D1 migrations |
| `packages/go`, `packages/hub-events` | **this skill** (shared code / schema) |
| `workflows/*.json` in n8n, the n8n container | `my-facebook-reels-workflows` (sync, edit, import, restart) |
| n8n version upgrade | `n8n-upgrade` |
| `deploy/cloud/`, `deploy/hetzner/` host migration | read-only context here; a migration is its own task — confirm with the user before running any of those scripts |

Never import, publish, or restart n8n from this skill.

## Step 0 — read the repo's own record first

Project dir: `~/Desktop/dev/projects/1minhotspot-stack`.

1. Root `CLAUDE.md` — app table, conventions (moon, Go workspace, tags).
2. The app's own `apps/<app>/CLAUDE.md` (web: `AGENTS.md` — Next.js version
   differs from training data; read `node_modules/next/dist/docs/`) and
   `README.md`. Root CLAUDE.md says: read it before touching an app.
3. `deploy/homelab/compose.yml` — the header comment lists every env file and
   bind mount; it is the inventory of what lives on the host.
4. `git log --oneline -15 -- apps/<app>` — recent changes carry dated
   incident notes; the app CLAUDE.md files hold the rest (`(2026-10-xx)`).
5. If the task is "is it a host move?", read `deploy/hetzner/MIGRATION.md`
   and `deploy/cloud/README.md` (Thai). Whether either migration has been
   executed is not recorded in the repo — ask.

## System map

| App | Role | Talks to | Image / target |
| --- | --- | --- | --- |
| `worker` (Go) | polls Thai news RSS on `CRON_SCHEDULE`, upserts to Postgres/NocoDB, GETs n8n webhooks for tables with unused rows, re-shares hot reels as Page stories | n8n webhooks, Postgres, Facebook Graph, Gemini, Telegram, studio `POST /content/news/hot`, hub | `ghcr.io/thititongumpun/1minhotspot-worker` |
| `fb-bot` (Go, distroless) | replies/comments on the Facebook Page from one writer goroutine, SQLite dedup, daily write cap | Facebook Graph, hub; cloudflared routes to container name `fb-auto-reply` | `ghcr.io/thititongumpun/1min-fb-bot` |
| `warehouse` (React-three/Vite, nginx) | 3D realtime dashboard; nginx proxies `/events`, `/health` to the hub | hub | `ghcr.io/thititongumpun/1min-warehouse` |
| `warehouse-hub` (Go) | event fan-in: services `POST /ingest` with `X-Hub-Key`; UI reads SSE `GET /events`; persists `events.jsonl` in volume `hub-data`; probes n8n version and `PROBES` targets | every app, n8n `/metrics` | `ghcr.io/thititongumpun/warehouse-hub` |
| `studio` (Python/uv, FastAPI) | Lao lotto + news/horoscope/traffic/stats posts via cron subprocesses | Postgres, Facebook, YouTube, Gemini, hub; reads n8n reel covers read-only | `ghcr.io/thititongumpun/1min-studio` |
| `web` (Next.js 16 / OpenNext) | 1minhotspot.com: clip pages from the Facebook feed + D1 store; n8n pushes rewrites to `POST /api/ingest` (`x-ingest-secret`) | Facebook Graph, D1 `1minhotspot` | Cloudflare Worker `1minhotspot` (Workers Builds, root `apps/web`) |

Event schema: `packages/hub-events/schema.json` (docs/tests only, no codegen).
All homelab services sit on the external docker network `proxy`; the hub is
reachable only there (`http://warehouse-hub:8080/ingest`).

## Build and test locally

```bash
cd ~/Desktop/dev/projects/1minhotspot-stack
npx --yes -p @moonrepo/cli@2.6.1 moon run :test          # every app
npx --yes -p @moonrepo/cli@2.6.1 moon run worker:test    # one project; ids = dir names, plus warehouse-hub, shared-go
npx --yes -p @moonrepo/cli@2.6.1 moon ci                 # what CI runs (.github/workflows/ci.yml)
docker build -f apps/<go-app>/Dockerfile .               # Go apps build from repo root (shared module)
```

- fb-bot: also `go test -race ./...` in `apps/fb-bot` (its CLAUDE.md: runner
  and daily cap are concurrency-sensitive).
- web: `moon` `build` has `runInCI: false` — `next build` prerenders from
  remote D1 and needs `CLOUDFLARE_API_TOKEN`; Workers Builds does the real build.
- Shared Go code changes (`packages/go/**`) trigger both worker and fb-bot
  publishes; run both apps' tests.

## Publish — what a push to `main` produces

Path-filtered per app (`.github/workflows/<app>-publish.yml`):

| App | Trigger paths | Tags pushed |
| --- | --- | --- |
| worker | `apps/worker/**`, `packages/go/**` | `latest`, `sha-<short sha>` |
| fb-bot | `apps/fb-bot/**`, `packages/go/**`, tag `fb-bot/v*` | auto-increments `fb-bot/vX.Y.Z` patch + GitHub release; image `X.Y.Z`, `latest`; multi-arch |
| warehouse | `apps/warehouse/**` | warehouse `latest`, `sha-<short>`; hub `latest`, `sha-<full sha>` |
| studio | `apps/studio/**`, tag `studio/v*` | `latest`, `main`, `sha-<short>`, `X.Y.Z` on a `studio/v*` tag |
| web | — (no GitHub workflow) | Cloudflare Workers Builds on the connected repo |

Before deploying, confirm the run finished: `gh run list --workflow
<app>-publish.yml -L 3`. Only fb-bot is multi-arch; the rest are amd64 only.

## Change → deploy → prove loop (homelab apps)

Host: ssh alias is `N8N_SSH` in the project's `homelab.env` (same host as
n8n). Stack dir on the host: `/root/docker/1minhotspot-stack`, a copy of
`deploy/homelab/compose.yml` plus untracked `.env`, `worker.env`,
`fb-bot.env`, `studio.env`, `data/`, `lottery_output/` and credential files.
Never print those env files; refer to them by name.

```bash
set -a; . ./homelab.env; set +a
st() { ssh "$N8N_SSH" "cd /root/docker/1minhotspot-stack && $*"; }
```

Service names (compose → container): `1minhotspot-worker`,
`auto-reply-bot` → `fb-auto-reply`, `1min-warehouse`, `warehouse-hub`,
`1min-studio`.

1. **Change + test** locally (above). Commit only when the user asks.
2. **Record the running tag before anything moves** — this is the rollback:
   ```bash
   st "docker compose images"                                   # tag column
   st "docker inspect -f '{{.Image}} {{.Config.Image}}' <container>"
   ```
3. **Compose drift check.** If `deploy/homelab/compose.yml` changed, diff it
   against the host copy (`st "cat compose.yml"`) and show the diff; how the
   host copy is kept in sync is not documented — copy it only after a yes.
4. **Pull + recreate one service:**
   ```bash
   st "docker compose pull <service> && docker compose up -d <service>"
   ```
   fb-bot is pinned by `CONTAINER_VERSION` in the host `.env` (not
   `fb-bot.env`), default `latest`. Never `docker compose down` the stack:
   `hub-data` is a named volume, but downing takes every service with it.
5. **Prove** (next section). Any failure → rollback, don't fix forward
   without asking.
6. **Report** (Results block).

Ask before deploying anything that posts to Facebook on start-up paths
(worker, fb-bot, studio): confirm no job is mid-run, see Traps.

## Prove it — health and logs

```bash
st "docker compose ps"                                           # every service (healthy)
st "docker compose exec -T 1minhotspot-worker wget -qO- http://127.0.0.1:8080/health"
st "docker exec fb-auto-reply /bot -healthcheck && echo ok"      # distroless: no shell, no wget
st "docker exec warehouse-hub /hub -healthcheck && echo ok"
st "docker compose exec -T 1min-studio python -c \"import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8000/health').read().decode())\""
st "docker compose logs --since 15m --tail 200 <service>"
```

- worker `/health` is always 200; read `feeds[].state` (`ok|quiet|down`,
  `down` = 3+ consecutive failed fetches). `feeds` is `[]` until the first
  fetch after boot, so wait one `CRON_SCHEDULE` tick before judging.
- studio `/content/health` gives last content pipeline results (HTTP Basic;
  creds in `apps/studio/CLAUDE.md`, don't paste them into reports).
- warehouse UI: host port `8089`; studio: host port `8011`.
- Healthchecks run every 60 s with a 30 s start period; a fresh container
  shows `starting` for up to ~90 s.
- Worker logs are json-file, 100m × 10. n8n's `watchdog` workflow
  (`workflows/watchdog.mjs`) Telegram-alerts on worker/studio/fb-bot/hub/
  warehouse probes and reel staleness — a fresh alert after deploy is a fail.
- Cross-check the hub is receiving: the warehouse dashboard shows events from
  the redeployed app within its next job run.

## Rollback

Inferred from the tags above (no rollback script exists for single-app
deploys): pin the previous image recorded in step 2.

```bash
# worker / warehouse / hub / studio: compose uses :latest — edit the host compose image to :sha-<prev>
st "docker compose up -d <service>"
# fb-bot: set CONTAINER_VERSION=<prev X.Y.Z> in the host .env, then
st "docker compose up -d auto-reply-bot"
```

Then re-run Prove. Tell the user the host compose now pins a tag, so a later
`pull` will not move it until reverted to `:latest`.

**web:** no rollback procedure is documented in the repo. Use Cloudflare's
Worker deployment history (see the `wrangler` skill); a D1 migration is
forward-only unless the migration file provides a down path — confirm before
`wrangler d1 migrations apply 1minhotspot --remote`.

## web — deploy

- Normal path: push to `main`; Cloudflare Workers Builds builds `apps/web`.
- Manual: `pnpm deploy` in `apps/web` (`opennextjs-cloudflare build && deploy`);
  `pnpm preview` for a local Workers preview.
- Schema: `pnpm exec wrangler d1 migrations apply 1minhotspot --remote`, after
  adding a file in `db/migrations/`. Smoke: `pnpm exec tsx scripts/store-smoke.ts`.
- Prove: the site serves real clips, not the 12 sample clips — the log line
  `[clips] ... using sample data` means the feed credentials are missing.
- `/api/ingest` fails closed without `INGEST_SECRET`; a 401 storm from n8n
  after a deploy means the Worker secret is unset, not an n8n bug.

## Backups and restore

State to protect (from `deploy/hetzner/MIGRATION.md` + compose header):
`data/` (fb-bot SQLite + `-wal/-shm`), `lottery_output/`, the four `*.env`
files, `gcp-billing.json`, `client_secrets.json`, `youtube_token.pickle`,
volume `1min-warehouse_hub-data`, and the `pg18` databases (`hotspot`,
`nocodb`, `laolotto`, `n8n`, ...).

- `deploy/cloud/backup.sh` (for the cloud VM) does `pg_dumpall` + n8n data +
  fb-bot `data/` → R2, 14 days, cron 03:00, creds in `/root/.backup.env` on
  the host. Whether it is installed on the current host is unknown — check
  `crontab -l` on the host before claiming backups exist.
- Ad-hoc before a risky deploy:
  ```bash
  st "tar -czf /root/fb-bot-data-\$(date -u +%Y%m%dT%H%MZ).tgz data"
  ssh "$N8N_SSH" "docker exec pg18 pg_dumpall -U admin | gzip > /root/pg-\$(date -u +%Y%m%dT%H%MZ).sql.gz"
  ```
- No restore script exists in the repo. Restoring SQLite or Postgres
  overwrites live data — stop the owning service, show the plan, get a yes.
- `backups/` in this repo holds n8n workflow exports only — owned by
  `my-facebook-reels-workflows`.

## Results — always end with this

```
host:        <N8N_SSH>:/root/docker/1minhotspot-stack
service · before tag · after tag · health · log tail
1minhotspot-worker · sha-abc1234 · sha-def5678 · healthy · clean
publish run: <gh run url>    rollback: <command with previous tag>
```

## Traps

- **Facebook writes are never retried** (worker webhooks, fb-bot replies):
  a restart mid-job can lose a post, a retry can duplicate one. Deploy
  between job ticks; check `docker compose logs --since 5m` first.
- **Two stacks live at once = double posts.** During any host migration
  never run worker/n8n/cloudflared on both hosts (`deploy/cloud/README.md`).
- **fb-bot `data/` must be owned by 65532** (`chown -R 65532:65532 data`);
  distroless has no shell to fix it from inside.
- **Worker DNS is pinned to Google** (`dns: 8.8.8.8`) for Meta upload edge
  routing (2026-10-02); don't drop it when editing compose.
- **studio network aliases** `lotto`, `lao-lotto-lotto-1` stay until confirmed
  unused by n8n/cloudflared.
- **The reels skill's map says the worker is a "separate repo"** — it now
  lives in `apps/worker` here; image name unchanged.
- **Hub replay** survives restarts only via `hub-data`; recreating the volume
  under another name loses the day's KPIs.

## Unknowns (not recorded in the repo — ask, don't assume)

- Whether the homelab → cloud VM / Hetzner migration has happened, and which
  host `N8N_SSH` currently points at.
- How the host's `compose.yml` copy is kept in sync with
  `deploy/homelab/compose.yml` (no sync script).
- Whether `wud.watch=true` on fb-bot auto-updates it or only notifies.
- Whether `backup.sh` + cron is installed on the current host; no restore runbook.
- fb-bot's container port is set by `PORT` in `fb-bot.env` (README default 8000);
  the actual value is unknown.
- web rollback procedure and which Worker secrets are set (`INGEST_SECRET`,
  feed tokens) — check `wrangler secret list`, never print values.
