---
name: n8n-upgrade
argument-hint: "[compose dir or target version]"
description: Upgrade a self-hosted docker-compose n8n stack (n8nio/n8n plus the n8nio/runners sidecar) to a chosen or latest stable release with a docs-verified compatibility audit, pausing triggers and draining running executions before the restart (queued ones resume on startup, per the docs), a snapshot-based rollback, then resuming the paused workflows and checking executions run normally. Use when asked to update, upgrade, or bump n8n or its task runners, when the runner tag drifted from the n8n tag, when a release note names a removed node or env var the stack uses, or when an n8n upgrade broke workflows and needs rolling back. Official n8n docs and the upstream BREAKING-CHANGES.md only.
---

# n8n upgrade

The deliverable is, in this order: a compatibility report the user approves,
then the stack on the target tag with every previously active workflow still
active and a snapshot that can put the old version back. Nothing is pulled,
edited, or restarted before the report is approved.

Scope is a docker-compose stack with one `n8nio/n8n` main and one
`n8nio/runners` sidecar; queue-mode fleets, npm installs, and Kubernetes are
out of scope — say so and stop. Evidence is `docs.n8n.io` and `n8n-io/n8n`
`packages/cli/BREAKING-CHANGES.md` only; blog posts, third-party migration
guides, and memory are not. A docs URL that 404s is looked up in
`https://docs.n8n.io/sitemap.md`, not guessed.

## Step 0 — map the stack

```bash
cd <compose dir>
docker compose config | grep -E 'image:|N8N_|DB_|NODES_EXCLUDE|QUEUE_'
docker compose exec n8n n8n --version
```

Record: n8n tag, runner tag, `DB_TYPE`, `N8N_RUNNERS_MODE`, every `N8N_*`,
`DB_*`, `QUEUE_*`, `NODES_EXCLUDE` key actually set, and the data volume
name, and `URL` = the address the editor answers on (`http://localhost:5678`
unless `N8N_HOST`/`N8N_PORT`/`N8N_PATH` say otherwise). If the n8n tag and
runner tag differ, that is finding #1 — the docs require them equal. The
questions for the user (API key, one smoke-test workflow, DB user and name
when they are not in env) are asked together with the Step 2 report, one stop.

## Step 1 — pick the target and read the docs

Latest stable is the highest `^\d+\.\d+\.\d+$` tag from
`https://hub.docker.com/v2/repositories/n8nio/n8n/tags?page_size=100`, or the
version the user names. Never a floating tag (`latest`, `stable`, `next`,
`beta`): it makes "current" a moving target and defeats rollback.

Then read, in this order, only the headings between current and target —
a change from an earlier version is already in effect and is not reported:

1. `https://docs.n8n.io/changelog/release-notes-2.x.md`
2. `https://raw.githubusercontent.com/n8n-io/n8n/master/packages/cli/BREAKING-CHANGES.md`
3. `https://docs.n8n.io/deploy/host-n8n/configure-n8n/basic-configuration/use-environment-variables/task-runners.md`
4. `https://docs.n8n.io/deploy/host-n8n/keep-n8n-running/update-n8n.md`

Crossing a major (for example 2.x → 3.x) adds `docs.n8n.io/changelog/`
`v<major>0-breaking-changes.md` and the in-app Settings → Migration Report.

## Step 2 — audit, report, stop

Export the workflows first (this export is reused by Step 4):

```bash
docker compose exec -u node n8n n8n export:workflow --backup --output=/home/node/.n8n/export/
```

Cross the docs against Step 0 and the export:

| Check | Detect | Do |
| --- | --- | --- |
| env var deprecated, removed, renamed, or default flipped | a heading in range names it and Step 0 shows it set (the 2.0 heading's examples: `N8N_RUNNERS_ENABLED`, `N8N_RUNNERS_MODE=internal`, `N8N_CONFIG_FILES`, `QUEUE_WORKER_MAX_STALLED_COUNT`, `N8N_DEFAULT_BINARY_DATA_MODE=default`) | list old → new with the URL |
| node removed or disabled by default | `grep -o '"type": *"[^"]*"' export/*.json \| sort -u` against the notes (`n8n-nodes-base.start`, `executeCommand`, `localFileTrigger`, Python Code) | name every affected workflow |
| node behaviour or `typeVersion` change | notes name the node; export contains it | name the workflow, quote the note |
| runner image change | any Dockerfile extending `n8nio/runners`; `npm` → `pnpm` | rewrite line, cite |
| database driver change | `DB_TYPE` plus the notes (SQLite pool default, MySQL dropped) | blocking until migrated |

Report in this shape, nothing else before it:

```
Current → Target:        2.30.1 → 2.39.8 (n8n and runners)
Blocking:                …must change before the upgrade, or "none"
Changes required:        param · old · new · doc URL + heading
Deprecated/removed, with replacement:
                         what · replacement · workflows affected by name
No action:               what was checked and found clean
Pause plan:              workflows to unpublish, in-flight now (Step 3)
Rollback plan:           snapshot dir, restore order (Step 7)
```

Where the docs remove something without naming a replacement, propose the
nearest supported one and label it "suggested, not verified": `Start` →
`Manual Trigger` or `Execute Workflow Trigger`; `ExecuteCommand` kept only by
clearing `NODES_EXCLUDE` with the user's consent; Pyodide Python → external
runner Python. Then stop and ask, in one message: approve the tag bump
yes/no; each env change yes/no; each node replacement yes/no; pausing the
listed workflows for the window yes/no; plus the Step 0 questions.
**Nothing from Step 3.2 on runs before that answer.** "Just
upgrade it" approves the tag bump only; a changed env var, a cleared
exclusion, or an edited workflow needs its own yes. Step 3.1 is read-only and
may run while waiting.

## Step 3 — baseline, pause, drain

A `running` execution dies with the restart. An execution queued behind
`N8N_CONCURRENCY_PRODUCTION_LIMIT` (status `new`) does not: "On instance
startup, n8n resumes queued executions up to the concurrency limit and
re-enqueues the rest" (`docs.n8n.io/deploy/host-n8n/configure-n8n/scaling/control-concurrency.md`).
So before Step 5 nothing new may start and nothing may be `running`; the
queue is left as it is and resumes by itself after the restart.

**Ways to see what is running or queued** — use the first that works:

| Source | Command | Notes |
| --- | --- | --- |
| Public API (primary) | `curl -sH "X-N8N-API-KEY: $KEY" "$URL/api/v1/executions?status=running&limit=250"`, same for `new` and `waiting` | statuses per `docs.n8n.io/connect/n8n-api/executions.md` |
| Postgres | `docker compose exec -T db psql -U "$DB_POSTGRESDB_USER" -d "$DB_POSTGRESDB_DATABASE" -tAc "select status, count(*) from execution_entity where status in ('new','running','waiting') group by 1"` | works without an API key |
| SQLite | same SQL with `sqlite3` on `database.sqlite` in the data volume | |
| Editor | Executions tab; with a concurrency limit, the active/limit counter on top | eyes only |
| Logs | `docker compose logs --since 10m n8n \| grep -i concurrency` | queue add/release lines |

Statuses: `running` = in flight, wait for it. `new` = queued, survives the
restart — record it. `waiting` = parked on a Wait node with `waitTill`,
stored in the DB and resumed after restart — record it.

1. **Baseline (read-only, may run before approval)** into the Step 4 folder:
   `curl … "$URL/api/v1/workflows?active=true" > active-before.json`; the ids
   of every `new`/`running`/`waiting` execution into `inflight-before.txt`;
   the `error` + `crashed` counts; `n8n --version` into `VERSION`.
2. **Pause** — needs the Step 2 yes, because paused webhooks answer 404 and
   schedule ticks missed during the window are not replayed. Unpublish every
   id in `active-before.json` through the API (live, no restart):
   `curl -sfX POST -H "X-N8N-API-KEY: $KEY" "$URL/api/v1/workflows/<id>/unpublish"`;
   write the ids to `paused.txt` as each one succeeds — that file is the
   resume list, and Step 7 needs it too. Unpublishing does not cancel
   running or queued executions.
3. **Drain** — poll every 15 s until `running` = 0, 15-minute cap. The
   queue keeps feeding `running` as slots free, so with a backlog this
   also works the queue down; whatever is still `new` when `running` hits
   0 is left for startup:

```bash
cnt() { curl -sfH "X-N8N-API-KEY: $KEY" "$URL/api/v1/executions?status=$1&limit=250" | jq '.data|length'; }
for i in $(seq 1 60); do n=$(cnt running); [ "$n" = 0 ] && break; echo "running: $n, queued: $(cnt new)"; sleep 15; done
curl -sfH "X-N8N-API-KEY: $KEY" "$URL/api/v1/executions?status=new&limit=250" | jq -r '.data[]|"\(.id) \(.workflowId)"' > queued-at-restart.txt   # Step 6 checks these resumed
```

   Still running at the cap → stop and ask, listing the executions (id,
   workflow, status, startedAt): wait longer, stop them
   (`POST /api/v1/executions/<id>/stop` — lost work, needs its own yes), or
   abort and resume (`publish` each id in `paused.txt`). Never restart over a
   `running` execution without that answer.

## Step 4 — snapshot; no snapshot, no upgrade

Taken after the drain, so the dump holds no half-run execution. Into
`backups/n8n-<current>-<UTC yyyymmddThhmmZ>/`, re-runnable:

1. Copy the compose file, `.env`, and `docker compose config` output (holds
   secrets — never commit the folder).
2. `docker compose exec -u node n8n n8n export:credentials --backup --output=/home/node/.n8n/export/`, then copy the export dir out.
3. Database: `docker compose exec db pg_dump -U "$DB_POSTGRESDB_USER" -Fc "$DB_POSTGRESDB_DATABASE" > db.dump`
   when `DB_TYPE=postgresdb` (values from env, `.env`, or the user); for
   SQLite stop n8n and copy `database.sqlite`.
4. Volume: `docker run --rm -v <volume>:/data -v "$PWD":/backup alpine tar czf /backup/n8n_data.tgz -C /data .` — this holds the encryption key.

If an API call 401s, verify header and path on `docs.n8n.io`; do not guess.

## Step 5 — apply

Edit the compose file so `n8nio/n8n:<target>` and `n8nio/runners:<target>`
carry the identical string — refuse to bump one without the other. Apply only
the env changes from the approved report. Then:

```bash
date -u +%FT%TZ > UPGRADED_AT
docker compose pull && docker compose up -d      # up -d, not down: keeps volumes and network
for i in $(seq 1 24); do curl -sf "$URL/healthz" && break; sleep 5; done   # 120 s cap
docker compose logs --since 5m n8n | grep -iE 'migrat|error|deprecat'
docker compose ps runners && docker compose exec n8n n8n --version
```

A migration log line on first start is expected; an error line is not.

## Step 6 — resume, then prove the jobs run normally

1. **Resume** — `POST /api/v1/workflows/<id>/publish` for each id in
   `paused.txt`, nothing else (a workflow inactive before stays inactive).
   A publish that fails is a failure, named.
2. `curl … "$URL/api/v1/workflows?active=true" > active-after.json`; diff by
   id and name: `jq -r '.data[]|"\(.id) \(.name)"' active-before.json | sort`
   against `-after`. Missing or inactive = failure.
3. **Carried-over work** — each id in `inflight-before.txt` that was
   `waiting` must still be `waiting` (or since finished `success`); any
   `crashed`/`canceled` = failure, named with its workflow. Queued (`new`)
   executions left at the restart (`queued-at-restart.txt`) must leave
   `new` after startup — watch each to a terminal status; one stuck in
   `new` with free capacity, or `crashed`, = failure.
4. **Smoke** — fire the smoke workflow (webhook `curl`, or
   `docker compose exec -u node n8n n8n execute --id <id>`); one `success`.
5. **Watch real traffic** for 10 minutes (or until each resumed workflow
   with a schedule/webhook has run once, whichever the user named):
   executions with `startedAfter=$(cat UPGRADED_AT)` grouped by workflow and
   status. Any `error` or `crashed` newer than the upgrade = failure; a
   `running` stuck past the workflow's normal duration = report it.
6. Report: version, workflows resumed n/n, carried-over executions ok/failed,
   new executions per workflow by status, smoke result.

Any failure goes to Step 7. Do not fix forward without asking.

## Step 7 — rollback

Forward database migrations have no supported revert, so the snapshot is the
only way back — that is why Step 4 is mandatory.

1. `docker compose down` (only now).
2. Restore the compose file and `.env` from the snapshot.
3. `docker compose up -d db && docker compose exec -T db pg_restore -U <user> -d <db> --clean < db.dump` (or copy `database.sqlite` back).
4. `docker run --rm -v <volume>:/data -v "$PWD":/backup alpine sh -c 'rm -rf /data/* && tar xzf /backup/n8n_data.tgz -C /data'`.
5. `docker compose up -d`, then Step 5's health wait. The dump was taken
   with the workflows paused, so they come back unpublished: run Step 6
   from 1 (publish `paused.txt`) through 5 again.

## Traps this upgrade has already hit

- **Runner tag drift** — a partial pull left `n8nio/runners` one minor behind; Code nodes hung on "waiting for runner". Both tags in one edit, always.
- **`docker compose down` on an anonymous volume** — the data and the encryption key went with it, and every credential became unreadable. Name the volume; use `up -d` for the bump.
- **Encryption key** — a recreated volume with no `N8N_ENCRYPTION_KEY` in env generates a fresh key; the snapshot tar is the recovery.
- **`.env` after 2.0** — the dotenv upgrade reads backticks, `#`, and multiline values differently; quote values that contain them.
- **`update:workflow --active`** — deprecated since 2.0; scripts must use `publish:workflow` / `unpublish:workflow`.
