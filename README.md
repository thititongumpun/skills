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
per skill, so you get "pptx-diagram is dead" rather than "officecli missing",
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
actually whiteboard something.

Without it the skill still works, it just can't draw: it degrades to a
mermaid fence in the terminal and says so. Needs `node` on `PATH` and a
browser on the same machine — **you open `http://127.0.0.1:3000` yourself**,
nothing opens it for you. Explain mode additionally publishes a shareable
page, which needs the Artifact tool.

⚠️ The canvas server has **no authentication and wildcard CORS**
([#39](https://github.com/yctimlin/mcp_excalidraw/issues/39), and the fix in
[#74](https://github.com/yctimlin/mcp_excalidraw/pull/74) is unmerged). While
it runs, any page you visit can read or wipe your canvas. The skill therefore
starts it on use and stops it when done — don't leave it running.

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
- `.agents/skills/pptx-diagram/SKILL.md` — Mermaid → PowerPoint
```

Caveats: discovery is manual (the agent loads a skill because `AGENTS.md` says
to, not by matching descriptions), and both `/plugin install` lines above are
Claude Code syntax — elsewhere you'd wire up the context7 MCP server yourself.
**Claude Code only**: `autopilot` and `yolo` (they need subagents and a todo
tool), and `whiteboard`'s shareable page (it needs the Artifact tool).
Whiteboard's canvas is an MCP server, so it works in any MCP-capable agent;
its thinking works anywhere — you just get the mermaid fence instead of the
picture.

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
- **pptx-diagram** — Mermaid → editable PowerPoint shapes via
  [officecli](https://officecli.ai). Install it first —
  `npm install -g @officecli/officecli`, or `brew install officecli` — this
  skill does nothing at all without it.
- **skills-doctor** — what's missing on this machine and which skill each gap
  kills. Reports and prints commands; never installs on its own.

When to reach for each, in the form agents read: [AGENTS.md](AGENTS.md).
