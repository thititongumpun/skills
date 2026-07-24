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
to, not by matching descriptions), and **autopilot is Claude Code only** — it
needs subagents and TodoWrite.

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
- **pptx-diagram** — Mermaid → editable PowerPoint shapes via
  [officecli](https://officecli.ai).

When to reach for each, in the form agents read: [AGENTS.md](AGENTS.md).
