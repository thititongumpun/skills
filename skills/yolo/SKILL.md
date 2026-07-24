---
name: yolo
description: You Only Live Once — unattended task execution meant to run while you're eating or sleeping. Asks everything it needs up front in one burst, then goes fully silent — plans with opus (fable for very complex/expert work), spawns subagents to execute (parallel where safe), reviews, and finishes with a summary. Skips unsafe/irreversible actions and logs them for you instead of stopping. Use when the user says "yolo", "/yolo <task>", "you only live once", "do it all while I'm away/eating/sleeping", or "run this unattended, don't ask me anything". Needs a subagent runtime — Claude Code only.
---

# yolo — You Only Live Once

You are an ORCHESTRATOR running an **unattended** task. The user is leaving —
eating, sleeping, away. After the one up-front question burst below, no human
answers anything until they're back. Do not do the work yourself; deploy
subagents and coordinate.

This skill IS the `autopilot` flow with four overrides. Follow `autopilot`'s
Phase 1 (Plan) → Phase 2 (Execute) → Phase 3 (Review) → Phase 4 (Fix loop)
exactly — same dispatch rules (one Agent call per task, parallel only for
different-file tasks, subagents don't spawn subagents, round cap default 2) —
with the changes below. If `rtk` is on the machine, shell commands (yours and
every subagent's) go through it; say so in each subagent's brief.

## Override 1 — Ask everything up front, then go silent (the defining rule)

This is the ONLY point yolo may ask the user anything.

Before Phase 1, do a quick codebase scan so you only ask what you genuinely
can't infer. Then find **everything that could block or fork the run** —
scope/boundaries, target files or repo, constraints, acceptance criteria, and
which approach to take when there's a real fork — and ask it all at once with
`AskUserQuestion`. Batch into as few questions as possible (up to 4 per call,
multi-select where it fits). Ask now, while the user is still here; a question
you skip now becomes a guess you own overnight.

Once this burst is answered, yolo is **fully silent**. Phases 1–5 never call
`AskUserQuestion` again. Any ambiguity that surfaces later is resolved by your
best judgment using codebase conventions and recorded as an **assumption** for
the final summary — never a prompt.

## Override 2 — Planner model heuristic

Planner/reviewer default `model: "opus"`. Escalate the *planner* to
`model: "fable"` when the task is very complex or needs expert / professional
judgment (opus itself may recommend this in Phase 1). Execution subagents
inherit the session default; escalate a task's executor to the planner's model
only when Phase 1 flagged that task `complex: true`.

## Override 3 — Safety: skip & log, never touch, never wait

Keep a running **Deferred (unsafe)** list. Do all normal reversible work
freely. But any unsafe / irreversible / outward-facing action — `git push
--force`, `rm -rf`, history rewrite, deploys, mass delete, sending emails or
external API writes — is **not performed at all**. Record it: the exact command
it would have run and why it was deferred. Never block waiting on it, never
improvise a workaround that has the same blast radius.

Rationale: hard-to-reverse and outward-facing actions need a human confirmer.
Unattended means no confirmer is present, so defer instead of confirm.

## Override 4 — Always finish with a summary

The user returns to a finished run, so end with a single report:

- **Done** — tasks completed, fix rounds used, whether the final review came
  back clean.
- **Assumptions made** — every ambiguity you resolved yourself (Override 1).
- **Deferred (unsafe) — do this when you're back** — the Override 3 list, each
  with the command and why.
- **Blocked** — any task that failed and blocked its dependents (report it;
  don't force past it).

## Don't stall

Unattended means no waiting on human input and no infinite loops. Respect the
fix-loop round cap; at the cap, stop and put remaining findings in the summary
rather than looping forever. Report progress via `TodoWrite` when available,
else reprint the checklist on state changes — counts and phase, never time
estimates.
