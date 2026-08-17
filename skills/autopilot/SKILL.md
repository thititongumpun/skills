---
name: autopilot
argument-hint: "<task to run end to end>"
description: Fully self-driven task execution — Opus/Fable plans the work into a task list, subagents execute each task (escalating to Opus/Fable when a task is judged complex), then Opus/Fable reviews everything for bugs/improvements and loops fixes back until clean. Use when the user says "autopilot", "/autopilot <task>", "full auto", "run this end to end", or wants a multi-step task self-orchestrated without step-by-step guidance from them.
---

# Autopilot

You are an ORCHESTRATOR. Do not do the work yourself — deploy subagents for
planning, execution, and review, and coordinate between them.

Default planner/reviewer model is `opus`. Use `fable` instead only if the
user asked for it. Default fix-loop cap is 2 rounds unless the user says
otherwise.

If `rtk` is on the machine, shell commands — yours and every subagent's —
go through it (`rtk git status`, `rtk cargo test`): same output, far fewer
tokens. Say so in each subagent's brief; they don't inherit this.

## Progress reporting

The user is not driving this loop, so tell them where it is without being
asked.

- After Phase 1, print the full numbered task list, marking which tasks are
  flagged complex or simple and the model each will run on. That's the total
  scope — the user can't judge "remaining" until they've seen it, and a task
  tiered wrong is easiest to catch before it runs.
- If `TodoWrite` is available, mirror the task list into it (one todo per
  task, plus one for Review) and keep statuses current — that's the native
  progress UI. Carry the model in each todo's text too (`Add DLQ handling
  [opus]`); the todo list is what the user actually watches.
- If it isn't available, reprint the checklist as state changes, so the
  user always sees what's done and what's left:

  ```
  [3/8 done] Executing
  ✅ 1. Define Avro schema + compatibility mode   [sonnet]
  ✅ 2. Add idempotent producer config            [sonnet]
  ✅ 3. Wire Schema Registry client               [sonnet]
  ⏳ 4. Add DLQ handling                          [opus]    (complex)
  ⬜ 5. Streams topology tests                    [sonnet]
  ⬜ 6. Bump connector version                    [haiku]   (simple)
  ⬜ 7. Update docs                               [haiku]   (simple)
  ⬜ 8. Review                                    [opus]
  ```

  **Every row names the model that runs it** — no blanks, no "inherits the
  default." Every task has an explicit model (Phase 2), so print it: the
  user sees the whole tiering at a glance instead of reverse-engineering it
  from which rows are annotated. Keep the tier flag in parentheses after
  the model where one applies.

  Same rule for the phases the user doesn't see as tasks: the Phase 1 plan
  line and Phase 4 fix agents carry their model too (`[opus] planning`,
  `Fixing 3 findings [opus]`). If a `simple` task got redispatched (Phase 2),
  show both: `[haiku → sonnet] (simple, retried)`.

  Reprint on each state change, not on every tool call — one refreshed
  checklist per batch of task completions is enough.
- In the fix loop, state the round: `[Review round 1/2] 3 findings, fixing`.
- On finish, hand back with the Phase 5 summary.

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
  context7 or project docs), and established patterns for the domain. When
  a library's exact API matters, pull it from context7 and pin the version
  to what the project actually depends on — `resolve-library-id` ranks by
  documentation coverage, not recency, so its top hit is often an older
  release line. Put the resolved ID in the task so executors don't re-guess.
- Silently weigh 2-3 candidate approaches with their trade-offs, then
  commit to the one it recommends with a one-line rationale — don't surface
  the alternatives back to the orchestrator, just the decision and why.
- Prefer decomposing into smaller, independently understandable units over
  one tangled task, the same way a good design keeps components isolated.
- Make each task self-contained enough to hand straight to an executor:
  file paths, plus any convention or decision from the codebase scan it
  depends on. Whatever the planner learned and didn't write down is lost
  between phases.

If the approach is genuinely uncertain — unfamiliar API, unproven
integration, a performance assumption the whole design rests on — make
task 1 a thin end-to-end spike whose pass condition settles that question,
and make the rest of the plan conditional on it. Being wrong about the
approach costs every task after it, not just the first one.

Every task carries a **pass condition that can fail**: the exact command,
file shape, or comparison that decides it's done. "Looks right" is not a
pass condition — a task whose done-ness can't be checked is a task the
executor gets to declare finished on its own say-so.

It must return an ordered task list, each task marked `complex: true` only
when it genuinely needs strong reasoning — ambiguous requirements,
architecture-sensitive, security/correctness-critical. Don't mark things
complex by default; most mechanical, well-scoped tasks aren't.

A task may instead be marked `simple: true` when all three hold: it touches
**one known file** whose path the plan already names, the change is fully
specified in the task itself (no codebase search, no convention to infer,
no design choice left open), and the pass condition is a single command or
exact string check. Renames, config/version bumps, adding a declared import,
doc and comment text. If a task needs to *find* where to change something,
read a second file to know what to write, or judge whether the result is
right, it isn't simple — leave it unmarked. `simple` and `complex` are
mutually exclusive; when unsure, leave both off.

## Phase 2: Execute

For each planned task, deploy one Agent call:
- One clear objective per subagent, with its pass condition quoted
  verbatim; require it to report exactly what it changed and the result of
  running that check.
- Subagents don't spawn subagents. A subagent that hits ambiguity or can't
  meet its pass condition stops and reports back — it doesn't improvise a
  different task than the one it was given.
- `model`: set `model: "sonnet"` for normal tasks — the middle tier is
  explicit, not inherited. Set `model: "opus"` (or `"fable"`, matching
  Phase 1) only for tasks flagged `complex: true`, and `model: "haiku"`
  only for tasks flagged `simple: true`. Never omit `model`: inheriting the
  session default means the same plan runs a different tiering depending on
  what the user happens to be chatting on, and on an Opus session it
  quietly puts every unmarked task on Opus — the `complex` flag then buys
  nothing and the whole run is Opus-priced.
- If a `haiku` agent misses its pass condition or reports back confused
  about the task, redispatch that one task once on `model: "sonnet"` before
  treating it as failed — a mis-tiered task is cheap to retry and shouldn't
  block its dependents. Two misses on the same task is a plan problem, not
  a model problem: report it.
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
nothing is not a clean review.

For any bug it finds, apply `superpowers:systematic-debugging` discipline
before reporting it: confirm the fault with a direct check — grep, diff,
run it — and trace it to its root cause. A finding names the root cause
and where to fix it, not "X looks off." Not finding evidence that
something works is not evidence it's broken; an unverified finding sends a
fix agent chasing a ghost and costs a whole round. Return either concrete
findings (root cause + fix location, plus any general improvements) or
confirmation everything's clean.

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

## Phase 5: Hand back

The user did not watch the run, so this last message is the whole story for
them. Write it in plain language: short sentences, no jargon, no phase
numbers, no model names, no tool names. Someone who never read the plan
should be able to act on it. Three headings, in this order, always all
three:

```
## What I did
- Producers now send Avro instead of JSON. The schemas live in `schemas/`.
- Bad messages go to a dead-letter topic. Before, one bad message stopped
  the consumer.

## What broke and got fixed
- The consumer crashed on messages written before the change. Cause: it read
  them with the new schema. Fixed by pinning the reader schema to v1.
- Still broken: the retry test fails about 1 run in 10. I could not find why
  in 2 tries.

## What you need to do next
- You: add the schemas to the staging Schema Registry. I have no login for it.
- You: merge and deploy. I did not push anything.

8 tasks, 1 fix round, review clean.
```

- **Say who does each next action and why it needs a person** — a login you
  don't have, a third-party dashboard, a decision that is the user's to make.
  "Next action" with no owner gets read as already done.
- **Never drop a heading.** Nothing broke → write "Nothing broke." Nothing
  left → write "Nothing. It's done." A missing heading reads as unchecked.
- Anything still broken at the fix-loop cap, and any task that failed and
  blocked others, goes under "What broke and got fixed" as `Still broken:`
  with what was tried. Do not quietly leave it out, and do not promote it to
  "next action" unless the user is the one who has to act.
- Mirror the next-action list into `TodoWrite` when it's available, so the
  items survive the message.
- Close with one line of counts: tasks completed, fix rounds used, whether
  the final review came back clean. One line, not a fourth section.

## Failure modes to avoid

- **The one that actually happens: you do the work yourself.** Being told
  not to isn't enough — an orchestrator holding Edit/Write drifts into
  "this task is small, I'll just do it," and then no subagent report and
  no cold review ever covers that change. If you're about to edit a file,
  you've drifted; dispatch it instead.
- Don't skip the review step, even for "simple" requests.
- Don't keep looping fixes past the round cap.
- Don't escalate every task to Opus/Fable — only ones actually flagged
  complex in Phase 1.
- Don't downgrade to Haiku to save tokens on a task that only *looks*
  mechanical. The cost of a wrong tier is a whole failed task plus a retry;
  the cost of leaving `simple` off is a few tokens. Unmarked is the default.
- A failed or empty-handed task agent blocks its dependents — report them
  as blocked, don't dispatch them anyway just to keep the loop moving.
- Don't hand back a technical dump. The Phase 5 summary is for the person
  who walked away, not a replay of the run — no phase numbers, no model
  names, no subagent reports pasted through.
