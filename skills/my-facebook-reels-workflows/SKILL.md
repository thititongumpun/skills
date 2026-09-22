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

`homelab.env` in the project dir holds `N8N_SSH=<ssh alias>` and
`N8N_DIR=<compose dir on the host>`. Missing? Ask once, write it, and add it
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

## Step 3 — import the edited file(s)

```bash
ssh "$N8N_SSH" "cd $N8N_DIR && docker compose exec -T -u node n8n sh -c 'cat >/tmp/w.json && n8n import:workflow --input=/tmp/w.json'" < workflows/<name>.json
```

Import upserts by the JSON's `id`, so the file must keep the id it was synced
with. A changed id is a second copy, not an update. Credentials are referenced
by id inside nodes and are not exported; do not edit those ids.

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
  ssh "$N8N_SSH" "cd $N8N_DIR && docker compose exec -T -u node n8n sh -c 'cat >/tmp/w.json && n8n import:workflow --input=/tmp/w.json'" < "$f"
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
