#!/usr/bin/env python3
"""Print every prompt the user typed into Claude Code on one local day, grouped by working dir.

Usage: today_prompts.py [YYYY-MM-DD]   (default: today, local time)
"""
import glob, json, os, re, sys
from datetime import date, datetime

day = sys.argv[1] if len(sys.argv) > 1 else date.today().isoformat()
TAGS = re.compile(r"<(system-reminder|local-command-stdout|command-message|command-args)>.*?</\1>", re.S)

def prompts(path):
    for line in open(path, errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        msg = d.get("message")
        if d.get("type") != "user" or d.get("isSidechain") or d.get("isMeta") or not isinstance(msg, dict):
            continue
        # typed = CLI, sdk = IDE/T3 hosts; system/None and sdk-cli are hooks, observers, tool loops
        if d.get("promptSource") not in ("typed", "sdk") or d.get("entrypoint") == "sdk-cli":
            continue
        text = msg.get("content")
        if isinstance(text, list):  # typed prompt with attachments; tool results have no text block
            text = " ".join(b.get("text", "") for b in text if b.get("type") == "text")
        ts = d.get("timestamp")
        if not text or not ts:
            continue
        local = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
        text = TAGS.sub("", text).strip()
        if local.date().isoformat() == day and text and not text.startswith("<"):
            yield local.strftime("%H:%M"), d.get("cwd", "?"), " ".join(text.split())[:400]

rows = []
for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
    if "claude-mem" in f:  # memory plugin observer sessions, not user work
        continue
    if date.fromtimestamp(os.path.getmtime(f)).isoformat() >= day:  # skip files untouched since before the day
        rows += prompts(f)
cwd = None
for t, c, text in sorted(rows, key=lambda r: (r[1], r[0])):
    if c != cwd:
        cwd = c
        print(f"\n## {c}")
    print(f"- {t} {text}")
if not rows:
    print(f"no prompts on {day}")
