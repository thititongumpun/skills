---
name: my-facebook-reels-workflows
argument-hint: "[sync | <edit request> | deploy <workflows/name.json> | rollback [backup dir]]"
description: Sync and deploy the Thai-news → Facebook Reels n8n workflows (news khaosod, news thaipbs, news sanook) between the homelab n8n container and the current repo's workflows/ dir — pull the live JSON down, back it up, import an edited copy over ssh + docker compose, re-publish it, restart n8n, and prove it is active with a smoke run. Use when the user mentions the reels pipeline, 1minhotspot-worker, fb-auto-reply, khaosod/thaipbs/sanook workflows, or asks to sync, pull, push, edit, or roll back an n8n workflow in the homelab.
---

# Facebook Reels workflows

The deliverable is the homelab n8n running exactly what `workflows/` in this
repo says, every workflow that was active still active, and a backup that can
put the old JSON back. A saved file is not done; an active workflow with one
`success` execution is.

## System map — three parts, this skill owns one

| Part | Role | Here |
| --- | --- | --- |
| `1minhotspot-worker` | scrapes news sources → NocoDB (Postgres too, khaosod only) → POSTs the n8n webhook | context only, separate repo |
| **n8n** (homelab, docker compose, 2.x) | `news khaosod`, `news thaipbs`, `news sanook`: read from storage → render video → upload to Facebook + YouTube | **this skill** |
| `fb-auto-reply` | replies to Facebook comments | context only, separate repo |

Version bumps belong to `n8n-upgrade`; never touch the worker or the replier.

## How to call it

| You say | What runs |
| --- | --- |
| `/my-facebook-reels-workflows sync` | Step 0–1: pull every workflow into `workflows/`, report drift, stop |
| `/my-facebook-reels-workflows change my thaipbs add node <what>` | Step 0–2, edit `workflows/news-thaipbs.json` (see Editing), then Step 3–5 |
| `/my-facebook-reels-workflows deploy workflows/news-sanook.json` | Step 0–1 with the working-tree file stashed aside, Step 2 from the synced copy, then Step 3–5 on the working-tree file |
| `/my-facebook-reels-workflows rollback` | Step 6 from the newest `backups/n8n-workflows-*/`; name a dir to pick another |

A plain-English request names the workflow by source (`khaosod`, `thaipbs`,
`sanook`) — map it to `workflows/news-<source>.json`. Anything that changes
the homelab (edit, deploy, rollback) shows the diff of the JSON and the
backup path before Step 3 and waits for a yes.

## Step 0 — locate the homelab

`homelab.env` in the project dir holds `N8N_SSH=<ssh alias>`,
`N8N_DIR=<compose dir on the host>` and `N8N_PG=<Postgres container holding
the n8n db>` (homelab: `pg18`). Missing? Ask once, write it, and add it
to `.gitignore`. Then:

```bash
set -a; . ./homelab.env; set +a
n8n() { ssh "$N8N_SSH" "cd $N8N_DIR && docker compose exec -T -u node n8n n8n $*"; }
n8n --version                       # must be 2.x — 1.x has no publish:workflow
n8n list:workflow                   # id|name, the inventory
n8n list:workflow --active=true     # what must still be active at the end
```

## Step 1 — sync homelab → `workflows/` (always first)

```bash
mkdir -p workflows
n8n list:workflow | while IFS='|' read -r id name; do
  slug=$(printf '%s' "$name" | tr 'A-Z ' 'a-z-')
  n8n export:workflow --id "$id" --pretty > "workflows/$slug.json"
done
git status --short workflows/
```

A dirty file here is drift: the homelab changed since the last commit. Say
which, and stop unless the user has an edit to push. `sync` alone ends here.

## Step 2 — back up before any change; no backup, no import

```bash
B=backups/n8n-workflows-$(date -u +%Y%m%dT%H%MZ); mkdir -p "$B"
cp workflows/<name>.json "$B"/                         # every file about to be imported, pre-edit
n8n list:workflow --active=true > "$B/active-before.txt"
```

The backup is the homelab's version, so Step 2 runs straight after Step 1
and before any edit. `deploy` of an already-edited file: `git stash push
workflows/<name>.json`, Step 1, Step 2, `git stash pop`. Commit the edit only
after Step 5 passes.

## Editing a workflow JSON

Sync and back up first (Steps 1–2), then edit the synced file, never a stale copy. Adding a
node is two edits: one object in `nodes` and one entry in `connections`.

```json
{ "name": "Set caption", "type": "n8n-nodes-base.set", "typeVersion": 3.4,
  "position": [880, 300], "parameters": { … } }
```

`connections` is keyed by the *upstream* node name:
`"Render video": {"main": [[{"node": "Set caption", "type": "main", "index": 0}]]}`.
Keep `id`, `versionId`, and every `credentials` block exactly as synced; pick
`type`/`typeVersion`/`parameters` by copying a node of the same type already
in one of the three workflows rather than from memory. Validate before
deploying: `python3 -m json.tool workflows/<name>.json >/dev/null`.

## Step 3 — wait for running executions, then import the edited file(s)

Import deactivates the workflow and its webhook stays unregistered until the
Step 4 restart, and the restart kills any render in flight. So drain first,
then run Steps 3 → 4 back to back in **one** command; never split them across
tool calls, since a rejected or interrupted call leaves the webhook off.

```bash
# executions still running (n8n keeps them in Postgres; container = $N8N_PG, db n8n)
running() { ssh "$N8N_SSH" "docker exec $N8N_PG psql -U admin -d n8n -At -c \"select count(*) from execution_entity where status in ('running','new') and \\\"stoppedAt\\\" is null\""; }
for i in $(seq 1 60); do n=$(running); [ "$n" = 0 ] && break; echo "running: $n, waiting"; sleep 15; done   # 15 min cap
[ "$(running)" = 0 ] || { echo "still running after 15 min — ask before deploying"; exit 1; }
```

Renders take 4–6 min. Hitting the cap means a stuck execution: show it and
ask, don't restart over it.

```bash
# own temp file per import (node-owned, removed on exit); any failure → non-zero
imp() { ssh "$N8N_SSH" "cd $N8N_DIR && docker compose exec -T -u node n8n sh -ec 'f=\$(mktemp /tmp/import-XXXXXX); trap \"rm -f \$f\" EXIT; cat >\"\$f\"; n8n import:workflow --input=\"\$f\"'" < "$1"; }
imp workflows/<name>.json || { echo "import failed — not publishing/restarting"; exit 1; }
```

Never run Step 4 after an import that did not exit 0. Import upserts by the
JSON's `id`, so the file must keep the id it was synced with. A changed id is a second copy, not an update. Credentials are
referenced by id inside nodes and are not exported; do not edit those ids.

## Step 4 — re-publish and restart

```bash
n8n publish:workflow --id <id>      # each imported id in active-before.txt
ssh "$N8N_SSH" "cd $N8N_DIR && docker compose restart n8n"
ssh "$N8N_SSH" 'for i in $(seq 1 24); do curl -sf http://localhost:5678/healthz && break; sleep 5; done'   # 120 s cap
```

The restart is not optional: a CLI import or publish does not re-register the
webhook or schedule triggers inside the running process. `restart`, never
`down` — `down` on an anonymous volume takes the encryption key with it.

## Step 5 — prove it

```bash
n8n list:workflow --active=true > "$B/active-after.txt"
diff "$B/active-before.txt" "$B/active-after.txt"      # empty, or a failure
n8n execute --id <id>                                  # one imported workflow, or POST the worker's webhook path
```

Any line in the diff, or an execution that is not `success`, goes to Step 6.
Do not fix forward without asking.

## Step 6 — rollback (also the `rollback` mode)

```bash
B=${1:-$(ls -d backups/n8n-workflows-*/ | tail -1)}      # newest unless a dir is named
for f in "$B"/*.json; do
  imp "$f" || { echo "rollback import failed: $f — not restarting"; exit 1; }   # imp() from Step 3
done
```

Then `publish:workflow` every id in `$B/active-before.txt`, restart (Step 4),
and run Step 5 with `active-before.txt` as the baseline. The homelab is now
what it was before Step 3; also `git checkout -- workflows/` if the repo copy
should follow.

## Results — always end with this

```
homelab:        <N8N_SSH>:<N8N_DIR>   n8n <version>
synced:         <n> workflows → workflows/   drift: <files or none>
backup:         <B>
workflow · id · active before · imported · active after · smoke
news khaosod · 12 · yes · yes · yes · success
restarted:      yes/no    next: commit workflows/<name>.json
```

## Traps this pipeline has already hit

- **`docker compose exec` without `-T`** — allocates a TTY over ssh; stdin redirect hangs and the export JSON picks up carriage returns. Always `-T`.
- **Renamed workflow** — the slug changes, the old file stays in `workflows/` and looks like a deleted workflow. Delete the stale file, keep the id.
- **Edited in the editor UI after the sync** — Step 3 silently overwrites it. Run Step 1 again right before Step 2 if any time has passed.
- **`update:workflow --active`** — deprecated since 2.0; `publish:workflow` / `unpublish:workflow` only.
- **Import split from restart (2026-10-23)** — an interrupted deploy left Sanook imported (= deactivated) for 2 min; the worker's webhook got `404 "GET snn" is not registered` and the story waited for the next 10-min poll. Drain, then Steps 3–4 in one command. The worker now retries only "never started" answers (404 not-registered, 502/503, connection refused) for ~2 min; a timeout or 500 is never retried, since that re-publishes the reel.
- **Fixed `/tmp/w.json` import path (2026-10-27)** — a stale root-owned `/tmp/w.json` in the container made `cat >/tmp/w.json` fail as `node` ("Permission denied"); nothing was imported, and a chained restart would have reported a deploy that did nothing. Import through `imp()` (a fresh `mktemp /tmp/import-XXXXXX`, `sh -e`, removed on exit) and stop on non-zero.
- **Smoke-test a render without publishing (2026-10-27)** — copy the workflow JSON, give it a new `id`/name, swap its trigger for a `manualTrigger`, delete every node downstream of "Execute FFmpeg Command", make "Pick Article" a read-only `SELECT` of an already-used article (no `UPDATE … used=true`), replace "Save Script" with an echo, disable the Telegram nodes; import it with `imp`. Plain `n8n execute` fails (the main process holds the task broker port 5679, runners are external), so run: `ssh "$N8N_SSH" "cd $N8N_DIR && docker compose exec -d -u node -e N8N_RUNNERS_MODE=internal -e N8N_RUNNERS_BROKER_PORT=5699 -e N8N_PORT=5799 -e QUEUE_HEALTH_CHECK_PORT=5798 n8n sh -c 'n8n execute --id <demo-id> > /tmp/<demo-id>.out 2>&1'"`. Video: `/tmp/n8n_ffmpeg/<baseName>.mp4`. Then delete the demo: `docker exec $N8N_PG psql -U admin -d n8n -c "DELETE FROM execution_entity WHERE \"workflowId\"='<id>'; DELETE FROM workflow_entity WHERE id='<id>';"` and `rm /tmp/<demo-id>.out`. No restart needed.
