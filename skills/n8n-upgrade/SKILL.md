---
name: n8n-upgrade
argument-hint: "[compose dir or target version]"
description: Upgrade a self-hosted docker-compose n8n stack (n8nio/n8n plus the n8nio/runners sidecar) to a chosen or latest stable release with a docs-verified compatibility audit, a snapshot-based rollback, and an active-workflow check before and after. Use when asked to update, upgrade, or bump n8n or its task runners, when the runner tag drifted from the n8n tag, when a release note names a removed node or env var the stack uses, or when an n8n upgrade broke workflows and needs rolling back. Official n8n docs and the upstream BREAKING-CHANGES.md only.
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

Export the workflows first (this export is reused by Step 3):

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
Rollback plan:           snapshot dir, restore order (Step 6)
```

Where the docs remove something without naming a replacement, propose the
nearest supported one and label it "suggested, not verified": `Start` →
`Manual Trigger` or `Execute Workflow Trigger`; `ExecuteCommand` kept only by
clearing `NODES_EXCLUDE` with the user's consent; Pyodide Python → external
runner Python. Then stop and ask, in one message: approve the tag bump
yes/no; each env change yes/no; each node replacement yes/no; plus the
Step 0 questions. **Nothing in Step 4 runs before that answer.** "Just
upgrade it" approves the tag bump only; a changed env var, a cleared
exclusion, or an edited workflow needs its own yes. Step 3 is read-only and
may run while waiting.

## Step 3 — snapshot; no snapshot, no upgrade

Into `backups/n8n-<current>-<UTC yyyymmddThhmmZ>/`, re-runnable:

1. Copy the compose file, `.env`, and `docker compose config` output (holds
   secrets — never commit the folder).
2. `docker compose exec -u node n8n n8n export:credentials --backup --output=/home/node/.n8n/export/`, then copy the export dir out.
3. Database: `docker compose exec db pg_dump -U "$DB_POSTGRESDB_USER" -Fc "$DB_POSTGRESDB_DATABASE" > db.dump`
   when `DB_TYPE=postgresdb` (values from env, `.env`, or the user); for
   SQLite stop n8n and copy `database.sqlite`.
4. Volume: `docker run --rm -v <volume>:/data -v "$PWD":/backup alpine tar czf /backup/n8n_data.tgz -C /data .` — this holds the encryption key.
5. Baseline: `curl -H "X-N8N-API-KEY: $KEY" "$URL/api/v1/workflows?active=true" > active-before.json`; the same for `/api/v1/executions?status=error` (count); `n8n --version` into `VERSION`.

If the API call 401s, verify header and path on `docs.n8n.io`; do not guess.

## Step 4 — apply

Edit the compose file so `n8nio/n8n:<target>` and `n8nio/runners:<target>`
carry the identical string — refuse to bump one without the other. Apply only
the env changes from the approved report. Then:

```bash
docker compose pull && docker compose up -d      # up -d, not down: keeps volumes and network
for i in $(seq 1 24); do curl -sf "$URL/healthz" && break; sleep 5; done   # 120 s cap
docker compose logs --since 5m n8n | grep -iE 'migrat|error|deprecat'
docker compose ps runners && docker compose exec n8n n8n --version
```

A migration log line on first start is expected; an error line is not.

## Step 5 — prove the active workflows

1. `curl … "$URL/api/v1/workflows?active=true" > active-after.json`.
2. Diff by id and name: `jq -r '.data[]|"\(.id) \(.name)"' active-before.json | sort` against `-after`; without `jq`, print both lists and compare by eye and say so.
3. Any workflow missing or now inactive is a failure.
4. `executions?status=error` newer than the upgrade timestamp is a failure.
5. Fire the smoke workflow (webhook `curl`, or `docker compose exec -u node n8n n8n execute --id <id>`) and wait for one `success` execution.

Any failure goes to Step 6. Do not fix forward without asking.

## Step 6 — rollback

Forward database migrations have no supported revert, so the snapshot is the
only way back — that is why Step 3 is mandatory.

1. `docker compose down` (only now).
2. Restore the compose file and `.env` from the snapshot.
3. `docker compose up -d db && docker compose exec -T db pg_restore -U <user> -d <db> --clean < db.dump` (or copy `database.sqlite` back).
4. `docker run --rm -v <volume>:/data -v "$PWD":/backup alpine sh -c 'rm -rf /data/* && tar xzf /backup/n8n_data.tgz -C /data'`.
5. `docker compose up -d`, then Step 4's wait and Step 5's diff again.

## Traps this upgrade has already hit

- **Runner tag drift** — a partial pull left `n8nio/runners` one minor behind; Code nodes hung on "waiting for runner". Both tags in one edit, always.
- **`docker compose down` on an anonymous volume** — the data and the encryption key went with it, and every credential became unreadable. Name the volume; use `up -d` for the bump.
- **Encryption key** — a recreated volume with no `N8N_ENCRYPTION_KEY` in env generates a fresh key; the snapshot tar is the recovery.
- **`.env` after 2.0** — the dotenv upgrade reads backticks, `#`, and multiline values differently; quote values that contain them.
- **`update:workflow --active`** — deprecated since 2.0; scripts must use `publish:workflow` / `unpublish:workflow`.
