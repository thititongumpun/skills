---
name: mfec-timesheet
argument-hint: "[date] [project] [time] e.g. today BAY 9-10"
description: Turn everything the user got done on a day into a timesheet task list — a project header line ("[PLACEHOLDER]" unless a project arg is given) and short English bullets ("- Set up …", "- Test …"), ready to paste into the MFEC timesheet, then optionally save it into TimeCheese. Accepts optional args in any order: date (today/yesterday/YYYY-MM-DD), project, time (9-10). Use when the user says "timesheet", "mfec-timesheet", "สรุปงานวันนี้", "ลง timesheet", or asks what they worked on today.
---

# MFEC timesheet

Output is one code block, nothing else around it but a one-line source note:

```
[PLACEHOLDER]
- Set up real WarpStream BYOC cluster and agent following the official docs.
- Test WarpStream BYOC: durability (kill agent, no data loss), latency and throughput benchmark, SASL + ACL on the real control plane, consumer lag.
- Write the WarpStream BYOC lab doc with results and caveats; review it and update the summary.
```

`[PLACEHOLDER]` stays literally unless a project arg is given — the user
fills the project code. Never guess it.

## 0. Args

Optional, any order, e.g. `/mfec-timesheet today BAY 9-10`:

- **date**: `today` (default), `yesterday`, or `YYYY-MM-DD`.
- **time**: `9-10`, `9:30-12`, `13-18` → start/end `HH:MM`.
- **project**: any other token. Resolve it against the output of
  `npm --prefix /home/thiti/dev/TimeCheese run -s timesheet projects`
  (`project_no<TAB>project_name`; case-insensitive project_no first, then
  substring). The header line becomes that `project_no`. Ambiguous or no
  match: show candidates and ask. No project arg: keep `[PLACEHOLDER]`.

## 1. Collect today's work

The day is the date arg (default today, local). Use every source available,
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

## 4. Save to TimeCheese

After the reply, ask whether to save it into TimeCheese. Then:

- Header still `[PLACEHOLDER]`: ask which project (the user types it). Never guess.
- No time given: ask for start–end, or save without times (the DB allows null).
- On yes: write the bullets (no header line) to a temp file and run
  `npm --prefix /home/thiti/dev/TimeCheese run -s timesheet -- add --date <D> --project <project_no> [--start HH:MM --end HH:MM] --description-file <absolute tmp path>`.
  It validates the slot (09:00–18:00, no overlap, 8h max), inserts, and prints the
  row id + AI summary. Report that, or the error (e.g. overlap) as-is.
- "Not logged in": tell the user to run
  `npm --prefix /home/thiti/dev/TimeCheese run timesheet login` themselves
  (it asks for a password). Do not attempt it.
