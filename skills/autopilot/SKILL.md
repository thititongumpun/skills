---
name: autopilot
description: Fully self-driven task execution — Opus/Fable plans the work into a task list, subagents execute each task (escalating to Opus/Fable when a task is judged complex), then Opus/Fable reviews everything for bugs/improvements and loops fixes back until clean. Use when the user says "autopilot", "/autopilot <task>", "do this yourself", "full auto", "run this end to end", or wants a multi-step task self-orchestrated without step-by-step guidance from them.
---

# Autopilot

You are an ORCHESTRATOR. Do not do the work yourself — deploy subagents for
planning, execution, and review, and coordinate between them.

Default planner/reviewer model is `opus`. Use `fable` instead only if the
user asked for it. Default fix-loop cap is 2 rounds unless the user says
otherwise.

## Phase 1: Plan

Deploy one Agent call, `model: "opus"` (or `"fable"`), given the user's
full request. Before committing to an approach, it must identify the best
practice or recommended pattern for this kind of task — check the
codebase's existing conventions, relevant docs (e.g. via context7 or
project docs), and established patterns for the domain — and design the
task list around that, not just the first approach that comes to mind. If
there are multiple reasonable approaches, it should pick the one it
recommends and say briefly why, rather than presenting options back to the
orchestrator. It must return an ordered task list, each task marked
`complex: true` only when it genuinely needs strong reasoning — ambiguous
requirements, architecture-sensitive, security/correctness-critical. Don't
mark things complex by default; most mechanical, well-scoped tasks aren't.

## Phase 2: Execute

For each planned task, deploy one Agent call:
- One clear objective per subagent; require it to report exactly what it
  changed and how it verified it.
- `model`: omit for normal tasks (inherits session default). Set
  `model: "opus"` (or `"fable"`, matching Phase 1) only for tasks flagged
  `complex: true`.
- Dispatch independent tasks in parallel (single message, multiple Agent
  calls). Run dependent tasks sequentially, in plan order.

## Phase 3: Review

Deploy one Agent call on the Phase 1 model, given the full task list and
every execution report. It must read the actual changed files itself — not
just trust the reports — and return either concrete findings (bugs +
improvements) or confirmation everything's clean.

## Phase 4: Fix loop

If Phase 3 found issues:
1. Deploy one Agent call per finding to fix it (parallel where findings are
   independent).
2. Re-deploy the Phase 3 review agent.
3. Repeat from step 1 up to the round cap. If still not clean at the cap,
   stop and report the remaining findings to the user rather than looping
   forever.

## Failure modes to avoid

- Don't skip the review step, even for "simple" requests.
- Don't keep looping fixes past the round cap.
- Don't let a subagent's self-report substitute for the review agent
  actually re-reading the files.
- Don't escalate every task to Opus/Fable — only ones actually flagged
  complex in Phase 1.
