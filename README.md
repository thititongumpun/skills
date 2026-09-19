# skills

Personal agent skills. Plain markdown, so any coding agent can use them —
Claude Code loads them natively, everyone else reads them via `AGENTS.md`.

## Install

Copy the skill files with [skills.sh](https://skills.sh) (the `skills` CLI package — not a shell script):

```bash
npx skills@latest add thititongumpun/skills
```

Or install as a native Claude Code plugin (updates when this repo changes):

```
/plugin marketplace add thititongumpun/skills
/plugin install skills@thititongumpun
```

### Check your setup

Which skills actually work on this machine, and what's missing:

```bash
bash .agents/skills/skills-doctor/scripts/doctor.sh
```

Or in Claude Code: `/skills-doctor` — the same check plus the harness tools
(subagents, `AskUserQuestion`, `Artifact`) that a shell can't see. It reports
per skill, so you get "mfec-pptx-diagram is dead" rather than "officecli missing",
and prints the exact install command for each gap. `--fix` offers to run the
safe ones. It never installs anything on its own.

Installed as a plugin, a `SessionStart` hook runs `doctor.sh --skills` on
every startup/resume: silent when the third-party skills this repo routes to
(archify, ppt-master, superpowers) are present, an error naming each missing
one and its install line when not.

### Needed for explain-repo: codegraph

`explain-repo` explains an unfamiliar repo by tracing real call paths, which it
gets from a [CodeGraph](https://www.npmjs.com/package/@colbymchenry/codegraph)
index rather than from grep:

```bash
npm install -g @colbymchenry/codegraph
codegraph init -i        # once per repo you want explained
```

The skill checks for `.codegraph/` and offers to run `init` itself when the
target repo has none. Without codegraph at all it still works — it falls back
to reading entrypoints and config, and says in the report that the map is
shallower.

### Needed for n8n-upgrade: docker, curl; jq for the workflow diff

`n8n-upgrade` drives `docker compose` and the n8n REST API directly, so it is
dead without `docker` and `curl`. `jq` is optional — without it the
before/after active-workflow diff is printed as raw JSON for you to compare
by eye, and the skill says so.

### Needed for mfec-pptx-diagram: officecli, and python3 for the helpers

The skill is dead without [officecli](https://officecli.ai) — there is no
fallback:

```bash
npm install -g @officecli/officecli    # or: brew install officecli
```

Two bundled helpers are Python, and both are about catching things officecli's
own `view issues` cannot see:

- `check-layout.py` — fails when a shape leaves the 33.87 × 19.05 cm slide, or
  when a diagram covers slide text. `add --type diagram` does not clamp the box
  it is given, so an oversized one is silently clipped with no warning.
- `flow-motion.py` — places the travelling marker and its motion legs.
- `annotate.py` — fills the diagram's nodes by role, captions them, and draws
  the legend for the colours. `classDef`/`style` in the mermaid source are
  dropped by the native renderer, so colour has to be applied afterwards.

Without `python3` the diagram still lands; you just place and check it by hand.

A headless browser (Chrome/Chromium/Edge, or `playwright install chromium`) is
optional: it unlocks `render=image` for the mermaid types the editable-shape
synthesizer rejects — gantt, class, ER, state — and the screenshot check.
Without one, `render=auto` quietly falls back to native, so ask for
`render=native` explicitly when you want editable shapes either way.

### Optional: context7

Several skills query [context7](https://context7.com) for exact library API
surfaces (client configs, Terraform provider arguments, Mermaid syntax) and
tell you to pin the doc version to what your project depends on. Without it
they fall back to fetching doc pages, which works but is slower and 403s more:

```
/plugin install context7@claude-plugins-official
```

Keyless works out of the box, rate-limited; add an Upstash API key for more.

### Codex and other agents

There is no plugin equivalent outside Claude Code, but `npx skills add` drops
the files in the vendor-neutral `.agents/skills/` layout. Point your agent at
them from your project's `AGENTS.md` — copy the table from
[AGENTS.md](AGENTS.md) in this repo, e.g.:

```markdown
## Skills
Read the matching file in full before acting on its topic:
- `.agents/skills/confluent-kafka-developer/SKILL.md` — Kafka/Confluent design, review, diagrams
- `.agents/skills/mfec-pptx-diagram/SKILL.md` — Mermaid → animated PowerPoint slides
```

Caveats: discovery is manual (the agent loads a skill because `AGENTS.md` says
to, not by matching descriptions), and both `/plugin install` lines above are
Claude Code syntax — elsewhere you'd wire up the context7 MCP server yourself.
**Claude Code only**: `autopilot` and `yolo` (they need subagents and a todo
tool).

## Skills

- **autopilot** — plans a task, runs it through subagents, reviews the
  result, loops fixes until clean. Claude Code only.
- **yolo** — unattended task execution: asks up front, then plan → spawn
  subagents → execute → summarize fully silent, skips & logs unsafe actions.
  Claude Code only.
- **confluent-kafka-admin** — Kafka/Confluent *cluster* work: provisioning,
  RBAC/ACLs, networking, scaling, DR, cost.
- **confluent-kafka-developer** — Kafka/Confluent *application* work:
  producers/consumers, Streams, Connect, ksqlDB, Flink.
- **fetch-403** — recover a page the fetcher was refused, without quietly
  falling back to memory.
- **mfec-kafka-connect** — the change loop for a Kafka Connect connector in an
  MFEC customer pipeline: house file/connector/topic naming, validate against the
  worker, diff against live, deploy, watch status, prove the data with the IVT
  checksums, update the repo README. Carries the traps already hit (two sources
  sharing a topic, `FilterTimestamp` semantics, secrets in JSON) and the
  Debezium 1.x → 3.x property renames.
- **mfec-pptx-diagram** — Mermaid → editable PowerPoint shapes on the MFEC
  branded template, via [officecli](https://officecli.ai). Also animates a
  marker travelling the route (PowerPoint won't animate inside a group, so it
  rides on top), stages captions, and builds the comparison table and takeaway
  box around the picture. Install officecli first —
  `npm install -g @officecli/officecli`, or `brew install officecli` — this
  skill does nothing at all without it. Its two verification/animation helpers
  need `python3`; without one you keep the diagram but lose the layout gate
  that catches a diagram running off the slide edge. Diagram slide only — for
  a whole deck built from documents it points you at
  [ppt-master](https://github.com/hugohe3/ppt-master) (MIT,
  `npx skills add hugohe3/ppt-master`), installed side by side rather than
  bundled: it's 115 MB and self-checks its own files.
- **n8n-upgrade** — upgrade a self-hosted docker-compose n8n stack (n8n plus
  the `n8nio/runners` sidecar) to a pinned or latest stable tag: reads the
  official release notes and BREAKING-CHANGES for the version range, reports
  every env var or node that is deprecated, removed, or default-flipped with a
  replacement and stops for approval, snapshots DB + data volume + workflow and
  credential exports, bumps both tags together, then proves every previously
  active workflow is still active and runs a smoke workflow. Rollback is
  restore-from-snapshot, written out as steps, because n8n migrations don't
  revert.
- **explain-repo** — "what does this repo even do?" Reads a codebase you didn't
  write and hands back a plain-language summary, one diagram, every external
  service it talks to that isn't in the tree, and an explicit list of what it
  couldn't work out — rather than a confident guess. Read-only. Wants
  codegraph (see above) and draws its diagram with **archify** ([tt-a1i](https://github.com/tt-a1i/archify),
  MIT) if that skill is installed; falls back to a mermaid fence if it isn't.
- **skills-doctor** — what's missing on this machine and which skill each gap
  kills. Reports and prints commands; never installs on its own.
- **sync-skill-installs** — reinstalls this repo's skills into the global and
  project copies, refreshes the lock hashes, and proves both match source. The
  three locations don't share files, so editing `skills/` alone changes nothing
  an agent actually loads.

When to reach for each, in the form agents read: [AGENTS.md](AGENTS.md).
