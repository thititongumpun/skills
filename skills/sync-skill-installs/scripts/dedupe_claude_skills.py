#!/usr/bin/env python3
"""Remove ~/.claude/skills and ./.claude/skills symlinks to skills an enabled Claude Code plugin
already ships, so they do not load twice. Runs from any directory."""
import json, pathlib
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
