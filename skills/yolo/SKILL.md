---
name: yolo
argument-hint: "<task to run unattended>"
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

A library API you half-remember is not an assumption to record, it's one to
resolve: query context7 (autopilot Phase 1 covers the how) and pin the version
to what the project depends on. Nobody is awake to catch a plausible method
name that doesn't exist, and it fails hours into the run.

## Override 2 — Planner model heuristic

Planner/reviewer default `model: "opus"`. Escalate the *planner* to
`model: "fable"` when the task is very complex or needs expert / professional
judgment (opus itself may recommend this in Phase 1). Execution subagents
inherit the session default; escalate a task's executor to the planner's model
only when Phase 1 flagged that task `complex: true`, and drop it to
`model: "haiku"` only when Phase 1 flagged that task `simple: true` (autopilot
Phase 1 defines the bar). Unattended means a mis-tiered task costs a silent
retry — leave both flags off when unsure.

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

Use autopilot's Phase 5 exactly — same three headings, same plain language,
same rules — with one heading added, and the unsafe list folded into the
last one:

```
## What I did
- ...

## What broke and got fixed
- ...

## What I assumed
- The staging cluster is the target. You said "staging" but not which one.
- Nothing else. Everything came from your answers up front.

## What you need to do next
- You: I did not push the branch. `git push --force` would rewrite history,
  and nobody was here to confirm it.
- You: rotate the old API key. That's a live credential change.

8 tasks, 1 fix round, review clean.
```

- **What I assumed** is the extra heading: every ambiguity you resolved
  yourself under Override 1. The user was asleep for those calls, so each one
  is a thing they may want to reverse. Nothing assumed → say so.
- The Override 3 deferred list lives under **What you need to do next**, one
  line each with the exact command you would have run and why you skipped it.
  It's a user action, not a separate section.
- The counts line also names any `simple`-flagged task that missed on haiku
  and had to be redispatched (`8 tasks, 1 retry, 1 fix round, review clean`).
  The user slept through it; a repeat offender means the plan's `simple` bar
  is set too loose.
- Blocked tasks follow autopilot's rule — `Still broken:` under **What broke
  and got fixed**, with what was tried. Don't force past a blocker to keep
  the loop moving.

## Don't stall

Unattended means no waiting on human input and no infinite loops. Respect the
fix-loop round cap; at the cap, stop and put remaining findings in the summary
rather than looping forever. Report progress via `TodoWrite` when available,
else reprint the checklist on state changes — counts and phase, never time
estimates.
