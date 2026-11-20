---
name: sync-skill-installs
description: Reinstall this repo's skills into the global (~/.agents/skills) and project (.agents/skills) copies, refresh skills-lock.json hashes, verify both match source, then update the installed Claude Code plugin (skills@thititongumpun) from the pushed repo. Use when the user says "reinstall global", "reinstall skills", "sync the installs", "update the plugin", or after editing anything under skills/ in this repo.
---

# Sync skill installs

Skills here live in three places that do not share files: `skills/` (source of
truth, tracked), `~/.agents/skills/` (global, for non-Claude agents), and
`.agents/skills/` (project-local, gitignored). Claude Code loads this repo's
skills only from the plugin (`skills:<name>`); a `~/.claude/skills/<name>` or
`.claude/skills/<name>` symlink to the same skill makes it show up twice, so
step 5 removes them (same for the superpowers and mattpocock plugins). Editing `skills/` alone changes nothing that any
agent actually loads.

Run the whole thing, every time — a partial sync is how installs drift:

```bash
cd "$(git rev-parse --show-toplevel)"

# 1. never ship build artifacts or scratch fixtures
find skills -name __pycache__ -type d -prune -exec rm -rf {} +

# 2. source -> global, source -> project (only the ones already installed there)
for s in skills/*/; do n=$(basename "$s"); rsync -a --delete --delete-excluded \
  --exclude='__pycache__' "$s" ~/.agents/skills/"$n"/; done
for d in .agents/skills/*/; do n=$(basename "$d"); [ -d "skills/$n" ] && rsync -a --delete --delete-excluded \
  --exclude='__pycache__' "skills/$n/" "$d"; done

# 3. global -> Antigravity CLI (~/.gemini/config/skills) & T3 Code Antigravity provider
mkdir -p ~/.gemini/config/skills
for d in ~/.agents/skills/*/; do n=$(basename "$d"); ln -sfn "../../../.agents/skills/$n" ~/.gemini/config/skills/"$n"; done
for p in ~/.t3/userdata/providers/antigravity/*/; do
  [ -d "$p" ] || continue
  mkdir -p "$p/config/skills"
  rsync -aL --delete --exclude='__pycache__' ~/.agents/skills/ "$p/config/skills/"
done

# 4. lock hashes follow the files
python3 - <<'PY'
import hashlib, json, pathlib
lock = pathlib.Path("skills-lock.json")
if lock.exists():
    d = json.loads(lock.read_text())
    for name, meta in d.get("skills", {}).items():
        f = pathlib.Path(meta["skillPath"])
        if f.exists():
            meta["computedHash"] = hashlib.sha256(f.read_bytes()).hexdigest()
    lock.write_text(json.dumps(d, indent=2) + "\n")
PY

# 5. no duplicates in Claude Code: a ~/.claude/skills or .claude/skills symlink to a
#    skill an enabled plugin already ships (this repo, superpowers, mattpocock, …) loads it twice
python3 - <<'PY'
import json, os, pathlib
h = pathlib.Path.home() / ".claude"
try:
    on = json.loads((h / "settings.json").read_text()).get("enabledPlugins", {})
    inst = json.loads((h / "plugins/installed_plugins.json").read_text())["plugins"]
except (OSError, ValueError, KeyError):
    raise SystemExit
names = {f.parent.name for k, v in inst.items() if on.get(k) for e in v
         for f in pathlib.Path(e["installPath"]).rglob("SKILL.md") if "node_modules" not in f.parts}
for d in (h / "skills", pathlib.Path(".claude/skills")):
    for l in (d.iterdir() if d.is_dir() else []):
        if l.is_symlink() and l.name in names:
            l.unlink(); print("removed dup:", l)
PY

# 6. prove it — all installs
for s in skills/*/; do n=$(basename "$s"); for dst in ~/.agents/skills/"$n" .agents/skills/"$n" ~/.t3/userdata/providers/antigravity/*/config/skills/"$n"; do
  [ -d "$dst" ] && { diff -rq "$s" "$dst" >/dev/null || echo "DRIFT: $dst"; }; done; done
```

Then report which skills changed. `.agents/` and `skills-lock.json` are
gitignored, so nothing here belongs in a commit.

## Fresh machine bootstrap (all skill packs)

To install this repo plus `obra/superpowers` and `mattpocock/skills` globally on a new machine (for Claude Code, Gemini CLI, Antigravity CLI, and T3 Code Antigravity):

```bash
npx -y skills@latest add thititongumpun/skills -g -s '*' -a antigravity gemini-cli -y  # Claude Code gets these via the plugin
# Claude Code gets all three packs as plugins, never as ~/.claude/skills symlinks (they would load twice)
claude plugin marketplace add thititongumpun/skills && claude plugin install skills@thititongumpun
claude plugin install superpowers@claude-plugins-official
claude plugin marketplace add mattpocock/skills && claude plugin install mattpocock-skills@mattpocock
npx -y skills@latest add obra/superpowers -g -s '*' -a antigravity gemini-cli -y
npx -y skills@latest add mattpocock/skills -g -s '*' -a antigravity gemini-cli -y

for p in ~/.t3/userdata/providers/antigravity/*/; do
  [ -d "$p" ] || continue
  mkdir -p "$p/config/skills"
  rsync -aL --delete --exclude='__pycache__' ~/.agents/skills/ "$p/config/skills/"
done
```

## Claude Code plugin

The plugin (`skills@thititongumpun`) installs from GitHub, not from this
working tree, so it only picks up what is pushed. Skip this part when the
`claude` CLI is missing or the plugin is not installed
(`claude plugin list | grep -q skills@thititongumpun`).

1. A skill changed since the last plugin release → bump `version` in
   `.claude-plugin/plugin.json` (patch for edits, minor for a new skill);
   the plugin updater compares versions, so an unbumped push is not picked up.
2. Unpushed commits (`git status -sb` shows `ahead`) → the plugin would
   get the old copy. Commit and push only when the user asked for it;
   otherwise stop here and say the plugin is behind until they push.
3. Then:

```bash
claude plugin marketplace update thititongumpun
claude plugin update skills@thititongumpun   # expect "updated from X to Y"; "already at" = version not bumped
```

Tell the user to restart Claude Code — the plugin loads at startup.

## Before you sync

- **Only `assets/` files the skill needs.** A customer deck or a test fixture
  parked in `skills/<name>/assets/` gets copied into both installs and
  re-copied on every sync. Keep fixtures in a scratch directory.
- **Deleting from `skills/` is not enough.** The installed copies keep the
  file until a `--delete` rsync runs. That is what this skill is for.
- **A rename is two renames.** `skills/old` → `skills/new` leaves
  `~/.agents/skills/old`, `.agents/skills/old`, and the
  plugin's old copy until the next plugin release. Remove the old directory
  in every install, then bump and update the plugin.
- **The skill registry is read at session start.** A renamed or new skill does
  not appear in this session — say so, and tell the user to `/clear` or
  restart.
