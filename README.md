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

### Needed for whiteboard's canvas: the excalidraw MCP

`whiteboard` draws onto a live [Excalidraw](https://excalidraw.com) canvas
you can edit by hand — drag a box, reroute an arrow — and then reads your
edits back:

```
claude mcp add excalidraw --scope user \
  -e EXCALIDRAW_NO_AUTOSTART=1 -- npx -y mcp-excalidraw-server
```

Keep the `EXCALIDRAW_NO_AUTOSTART=1` — without it the canvas spawns whenever
the agent connects, so port 3000 is listening at every session start whether
or not you're drawing. With it, the skill starts the canvas only when you
actually whiteboard something, and stops it when done.

Installed as a Claude Code plugin, a `SessionEnd` hook also stops the canvas
if a session ends before the skill got to shut it down. It costs ~6ms when
nothing is running. Via `npx skills add` there's no hook, so a killed session
can leave the canvas up — `npx -y mcp-excalidraw-server stop` clears it.

Without it the skill still works, it just can't draw an adjustable canvas: it
degrades to an **archify** HTML diagram (or a mermaid fence) and says so. Needs `node` on `PATH` and a
browser on the same machine — **you open `http://127.0.0.1:3000` yourself**,
nothing opens it for you. Explain mode additionally publishes a shareable
page, which needs the Artifact tool.

⚠️ The canvas server has **no authentication and wildcard CORS**
([#39](https://github.com/yctimlin/mcp_excalidraw/issues/39), and the fix in
[#74](https://github.com/yctimlin/mcp_excalidraw/pull/74) is unmerged). While
it runs, any page you visit can read or wipe your canvas. The skill therefore
starts it on use and stops it when done — don't leave it running.

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
tool), and `whiteboard`'s shareable page (it needs the Artifact tool).
Whiteboard's canvas is an MCP server, so it works in any MCP-capable agent;
its thinking works anywhere — you just get an archify HTML diagram instead of
the live picture.

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
- **whiteboard** — requirements → a diagram you can drag around on a live
  Excalidraw canvas, with your edits read back to you. Plus pros/cons and a
  pick when more than one design fits. Or `/whiteboard explain <repo|PR|task>`
  to diagram work that already exists and publish a shareable page for your
  team. Never implements. Needs the excalidraw MCP (see above).
- **fetch-403** — recover a page the fetcher was refused, without quietly
  falling back to memory.
- **mfec-pptx-diagram** — Mermaid → editable PowerPoint shapes on the MFEC
  branded template, via [officecli](https://officecli.ai). Also animates a
  marker travelling the route (PowerPoint won't animate inside a group, so it
  rides on top), stages captions, and builds the comparison table and takeaway
  box around the picture. Install officecli first —
  `npm install -g @officecli/officecli`, or `brew install officecli` — this
  skill does nothing at all without it. Its two verification/animation helpers
  need `python3`; without one you keep the diagram but lose the layout gate
  that catches a diagram running off the slide edge.
- **explain-repo** — "what does this repo even do?" Reads a codebase you didn't
  write and hands back a plain-language summary, one diagram, every external
  service it talks to that isn't in the tree, and an explicit list of what it
  couldn't work out — rather than a confident guess. Read-only. Wants
  codegraph (see above) and draws its diagram with **archify** ([tt-a1i](https://github.com/tt-a1i/archify),
  MIT) if that skill is installed; falls back to a mermaid fence if it isn't.
- **skills-doctor** — what's missing on this machine and which skill each gap
  kills. Reports and prints commands; never installs on its own.

When to reach for each, in the form agents read: [AGENTS.md](AGENTS.md).
