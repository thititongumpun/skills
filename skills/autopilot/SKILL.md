---
name: autopilot
description: Fully self-driven task execution — Opus/Fable plans the work into a task list, subagents execute each task (escalating to Opus/Fable when a task is judged complex), then Opus/Fable reviews everything for bugs/improvements and loops fixes back until clean. Use when the user says "autopilot", "/autopilot <task>", "full auto", "run this end to end", or wants a multi-step task self-orchestrated without step-by-step guidance from them.
---

# Autopilot

You are an ORCHESTRATOR. Do not do the work yourself — deploy subagents for
planning, execution, and review, and coordinate between them.

Default planner/reviewer model is `opus`. Use `fable` instead only if the
user asked for it. Default fix-loop cap is 2 rounds unless the user says
otherwise.

Shell commands — yours and every subagent's — go through `rtk` (`rtk git
status`, `rtk cargo test`): same output, far fewer tokens. Say so in each
subagent's brief; they don't inherit this instruction.

## Progress reporting

The user is not driving this loop, so tell them where it is without being
asked.

- After Phase 1, print the full numbered task list, marking which tasks are
  flagged complex. That's the total scope — the user can't judge "remaining"
  until they've seen it.
- If `TodoWrite` is available, mirror the task list into it (one todo per
  task, plus one for Review) and keep statuses current — that's the native
  progress UI.
- If it isn't available, reprint the checklist as state changes, so the
  user always sees what's done and what's left:

  ```
  [3/7 done] Executing
  ✅ 1. Define Avro schema + compatibility mode
  ✅ 2. Add idempotent producer config
  ✅ 3. Wire Schema Registry client
  ⏳ 4. Add DLQ handling            (complex → opus)
  ⬜ 5. Streams topology tests
  ⬜ 6. Update docs
  ⬜ 7. Review
  ```

  Reprint on each state change, not on every tool call — one refreshed
  checklist per batch of task completions is enough.
- In the fix loop, state the round: `[Review round 1/2] 3 findings, fixing`.
- On finish, report what ran: tasks completed, fix rounds used, and whether
  the final review came back clean.

**Report counts and phase, never time estimates.** Subagent duration isn't
knowable in advance — "about 5 minutes left" would be invented. "4 of 7
tasks done, review pending" is true and just as useful.

## Phase 0: Clarify

Before deploying the Phase 1 Plan agent, check whether the request has
enough detail to plan against: scope/boundaries, target files or repo,
constraints, acceptance criteria. If anything material is missing or
ambiguous, use `AskUserQuestion` yourself to ask the user directly — do not
guess or assume on your own and do not delegate this to a subagent. Only
proceed to Phase 1 once the request is concrete enough to plan.

## Phase 1: Plan

Deploy one Agent call, `model: "opus"` (or `"fable"`), given the user's
full request. Before committing to an approach it must, brainstorming-style
(`superpowers:brainstorming`):
- Check the codebase's existing conventions, relevant docs (e.g. via
  context7 or project docs), and established patterns for the domain.
- Silently weigh 2-3 candidate approaches with their trade-offs, then
  commit to the one it recommends with a one-line rationale — don't surface
  the alternatives back to the orchestrator, just the decision and why.
- Prefer decomposing into smaller, independently understandable units over
  one tangled task, the same way a good design keeps components isolated.
- Make each task self-contained enough to hand straight to an executor:
  file paths, plus any convention or decision from the codebase scan it
  depends on. Whatever the planner learned and didn't write down is lost
  between phases.

It must return an ordered task list, each task marked `complex: true` only
when it genuinely needs strong reasoning — ambiguous requirements,
architecture-sensitive, security/correctness-critical. Don't mark things
complex by default; most mechanical, well-scoped tasks aren't.

## Phase 2: Execute

For each planned task, deploy one Agent call:
- One clear objective per subagent; require it to report exactly what it
  changed and how it verified it.
- `model`: omit for normal tasks (inherits session default). Set
  `model: "opus"` (or `"fable"`, matching Phase 1) only for tasks flagged
  `complex: true`.
- Dispatch independent tasks in parallel (single message, multiple Agent
  calls) — but only when they clearly touch different files; two agents
  editing the same file clobber each other and the review only ever sees
  the survivor. Unsure, or same file? Sequential, in plan order. Same rule
  governs the parallel fix agents in Phase 4.

## Phase 3: Review

Deploy one Agent call on the Phase 1 model, given the user's original
request, the full task list, and every execution report. It must check the
result against that original request, not just against the plan — a
perfectly executed wrong plan is still wrong. It must read the actual
changed files itself — not just trust the reports — and run the project's
own check (tests / typecheck / build, whatever the repo uses), including
the real output in its findings. A review that read everything but ran
nothing is not a clean review. For any bug it finds, apply
`superpowers:systematic-debugging` discipline before reporting it: identify
the root cause (read the actual error/logic, trace it to its source), not
just the symptom — a finding should name the root cause and where to fix
it, not "X looks off." Return either concrete findings (root cause + fix
location, plus any general improvements) or confirmation everything's
clean.

## Phase 4: Fix loop

If Phase 3 found issues:
1. Deploy one Agent call per finding to fix it (parallel where findings are
   independent). Each fix agent addresses the root cause Phase 3 identified
   — one focused change, not a scattershot of unrelated tweaks.
2. Re-deploy the Phase 3 review agent.
3. Repeat from step 1 up to the round cap. If the same finding is still not
   resolved at the cap, treat that as a systematic-debugging signal —
   repeated failed fixes on the same issue mean the approach is wrong, not
   that it needs one more patch. Stop and report the remaining
   findings (with what was tried) to the user instead of looping forever.

## Failure modes to avoid

- Don't skip the review step, even for "simple" requests.
- Don't keep looping fixes past the round cap.
- Don't let a subagent's self-report substitute for the review agent
  actually re-reading the files.
- Don't escalate every task to Opus/Fable — only ones actually flagged
  complex in Phase 1.
- A failed or empty-handed task agent blocks its dependents — report them
  as blocked, don't dispatch them anyway just to keep the loop moving.
