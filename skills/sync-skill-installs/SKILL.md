---
name: sync-skill-installs
description: Reinstall this repo's skills into the global (~/.agents/skills) and project (.agents/skills) copies, refresh skills-lock.json hashes, and verify both match source. Use when the user says "reinstall global", "reinstall skills", "sync the installs", or after editing anything under skills/ in this repo.
---

# Sync skill installs

Skills here live in three places that do not share files: `skills/` (source of
truth, tracked), `~/.agents/skills/` (global — every session outside this repo
reads it, via symlinks from `~/.claude/skills/`), and `.agents/skills/`
(project-local, gitignored). Editing `skills/` alone changes nothing that any
agent actually loads.

Run the whole thing, every time — a partial sync is how installs drift:

```bash
cd "$(git rev-parse --show-toplevel)"

# 1. never ship build artifacts or scratch fixtures
find skills -name __pycache__ -type d -prune -exec rm -rf {} +

# 2. source -> global, source -> project (only the ones already installed there)
for s in skills/*/; do n=$(basename "$s"); rsync -a --delete \
  --exclude='__pycache__' "$s" ~/.agents/skills/"$n"/; done
for d in .agents/skills/*/; do n=$(basename "$d"); [ -d "skills/$n" ] && rsync -a --delete \
  --exclude='__pycache__' "skills/$n/" "$d"; done

# 3. lock hashes follow the files
python3 - <<'PY'
import hashlib, json, pathlib
lock = pathlib.Path("skills-lock.json")
d = json.loads(lock.read_text())
for name, meta in d["skills"].items():
    f = pathlib.Path(meta["skillPath"])
    if f.exists():
        meta["computedHash"] = hashlib.sha256(f.read_bytes()).hexdigest()
lock.write_text(json.dumps(d, indent=2) + "\n")
PY

# 4. prove it
for s in skills/*/; do n=$(basename "$s"); diff -rq "$s" ~/.agents/skills/"$n" \
  || echo "DRIFT: $n"; done
```

Then report which skills changed. `.agents/` and `skills-lock.json` are
gitignored, so nothing here belongs in a commit.

## Before you sync

- **Only `assets/` files the skill needs.** A customer deck or a test fixture
  parked in `skills/<name>/assets/` gets copied into both installs and
  re-copied on every sync. Keep fixtures in a scratch directory.
- **Deleting from `skills/` is not enough.** The installed copies keep the
  file until a `--delete` rsync runs. That is what this skill is for.
- **A rename is two renames.** `skills/old` → `skills/new` leaves
  `~/.agents/skills/old`, `.agents/skills/old`, and the
  `~/.claude/skills/old` symlink behind, all still loading the old skill.
  Remove the old directory in every install and repoint the symlink:
  `ln -s ../../.agents/skills/new ~/.claude/skills/new`.
- **The skill registry is read at session start.** A renamed or new skill does
  not appear in this session — say so, and tell the user to `/clear` or
  restart.
