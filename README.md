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

- **autopilot** — Opus/Fable plans a task into a task list, subagents
  execute each task (escalating to Opus/Fable when a task is flagged
  complex), then Opus/Fable reviews everything and loops fixes back until
  clean. Trigger: "autopilot", "/autopilot \<task\>", "do this yourself",
  "full auto".
- **confluent-kafka-admin** — Confluent Data Streaming Platform administrator:
  Confluent Cloud and self-managed cluster provisioning, RBAC/ACLs,
  networking, Schema Registry, Connect, scaling, upgrades, DR, and cost
  governance. Retrieval-first against current Confluent docs.
- **confluent-kafka-developer** — Kafka/Confluent developer skill: design,
  explain, diagram, plan, and review Kafka application work. Researches
  official docs plus community sources (forum, Stack Overflow, GitHub)
  before answering.
- **pptx-diagram** — Mermaid → PowerPoint via `officecli`, producing real
  editable shapes and connectors (not a flat image) for flowchart and
  sequence diagrams. Requires [officecli](https://officecli.ai).
