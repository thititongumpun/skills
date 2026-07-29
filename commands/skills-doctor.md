---
description: Check which skills in this repo are missing dependencies
allowed-tools: Bash(bash:*)
---

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/skills-doctor/scripts/doctor.sh" || true`

Print that output verbatim, then add the half it structurally cannot see.

The script probes binaries and installed plugins. It cannot read your tool
list. Check yours and report per skill:

- subagents (`Agent`) and `AskUserQuestion` → autopilot, yolo. Both **hard**;
  without them neither skill runs at all.
- `TodoWrite` → autopilot, yolo. Soft — they fall back to reprinting the
  checklist.
- `Artifact` plus the `artifact-design` skill → whiteboard's explain mode.
  Hard for that mode only; design mode is unaffected.
- `WebFetch` / `WebSearch` → fetch-403 and both confluent-kafka skills. Their
  retrieval-first rule doesn't hold without these, and answering from memory
  instead is the exact failure those skills exist to prevent.

Install nothing yourself. For a missing plugin, give the `/plugin install`
line and stop. If the user asks you to fix a missing binary, run
`doctor.sh --fix` rather than inventing an install command — the script's
commands are verified, and a guessed package name is worse than no answer
(`@officecli/cli` looks right and 404s; the real one is
`@officecli/officecli`).
