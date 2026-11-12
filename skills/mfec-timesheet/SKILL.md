---
name: mfec-timesheet
argument-hint: "[YYYY-MM-DD, default today]"
description: Turn everything the user got done today into a timesheet task list — one "[PLACEHOLDER]" header line and short English bullets ("- Set up …", "- Test …"), ready to paste into the MFEC timesheet. Use when the user says "timesheet", "mfec-timesheet", "สรุปงานวันนี้", "ลง timesheet", or asks what they worked on today.
---

# MFEC timesheet

Output is one code block, nothing else around it but a one-line source note:

```
[PLACEHOLDER]
- Set up real WarpStream BYOC cluster and agent following the official docs.
- Test WarpStream BYOC: durability (kill agent, no data loss), latency and throughput benchmark, SASL + ACL on the real control plane, consumer lag.
- Write the WarpStream BYOC lab doc with results and caveats; review it and update the summary.
```

`[PLACEHOLDER]` stays literally — the user fills the project code. Never
guess it.

## 1. Collect today's work

The day is the local date (argument, or today). Use every source available,
then merge:

1. **This conversation** — always.
2. **Claude Code, all sessions of the day** — when `~/.claude/projects/`
   exists: `python3 <this skill dir>/scripts/today_prompts.py [YYYY-MM-DD]`.
   It prints every prompt the user typed that day, grouped by working dir
   (hook, observer, and tool-loop messages are dropped). A prompt is a
   request, not proof it was done — keep it only if the conversation or
   git shows it ran; when only the prompt exists, keep it if it is clearly
   work that was carried out (e.g. "deploy X" followed by more prompts on
   the same thing), drop it if unsure.
3. **Git** — in each working dir the script listed (or the current repo):
   `git log --since=<day>T00:00 --until=<day>T23:59 --author="$(git config user.email)" --oneline`.

Other agents (Codex, Cursor, Gemini, …) without those transcripts: use 1
and 3 and say in the source note that only this session was covered.

## 2. Write the bullets

- One bullet per task, not per prompt or commit. Fold retries, fixups,
  "แก้", "commit push", and follow-up tweaks into the task they belong to.
- English, imperative verb first (Set up, Test, Fix, Review, Write, Deploy,
  Upgrade, Tear down), one sentence, ends with a period. Details after a
  colon, comma-separated, as in the example.
- Name the real thing: product, component, environment (dev/uat/prd),
  what was proven. No file paths, commands, commit hashes, ticket-less
  jargon, or tool names of the agent itself (Claude, skills, subagents)
  unless the skill/tool *is* the deliverable.
- Skip chit-chat, questions that produced no work, and things only
  explained. Failed or abandoned work stays only if time went into it —
  say what was tried ("Investigate … ; blocked by …").
- Order by when it happened. No grouping headers, no times, no hours.

## 3. Reply

The code block, then one line: sources used (this session / N Claude
Code sessions / git in M repos). If nothing was found for the day, say so
instead of inventing bullets.
