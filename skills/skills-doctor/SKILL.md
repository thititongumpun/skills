---
name: skills-doctor
description: Check which skills in this repo actually work on this machine and what's missing — reports per-skill consequences (which skill is dead, which is degraded) with the exact install command for each gap. Use when a skill says it needs a tool that isn't there, when something degraded silently and you want to know why, after installing these skills for the first time, or when the user asks "what do I need to install", "why isn't <skill> working", or runs "/skills-doctor". Reports and prints commands; never installs anything on its own.
---

# Skills doctor

```bash
scripts/doctor.sh              # report
scripts/doctor.sh --fix        # offer to run the safe installs, one y/N each
```

Exits `1` when a hard dependency is missing and some skill is therefore dead,
`0` otherwise. Soft misses don't turn it red — a doctor that shows red on a
healthy machine gets ignored within a week.

`--fix` only ever runs user-prefix package managers (`brew`, `npm -g`,
`scoop`, `uv tool`). Anything needing `sudo`, a `curl … | sh` pipe, or a
`/plugin install` is printed for the user to run themselves, even if they say
yes. With no terminal to prompt at, it prints every command and runs nothing.

## What it can't see, and why that matters

The script probes binaries and installed plugins. **A shell cannot see
Claude's tool list**, so subagents, `AskUserQuestion`, `TodoWrite`,
`Artifact`, and `WebFetch`/`WebSearch` are not checked and are not faked as
rows — a `command -v AskUserQuestion` check would be a lie that reads as
reassurance.

That gap is why the `/skills-doctor` command exists: it runs this script and
then reports the harness half from the agent's own tool list. If you're
running the script directly, that section is yours to check.
