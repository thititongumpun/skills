# Skills

For agents without native skill discovery (Codex, Cursor, Gemini CLI, Copilot,
Amp, …). Read the matching `SKILL.md` **in full before acting** when a task
fits one of the descriptions below, then follow it.

Paths: `.agents/skills/<name>/SKILL.md` when installed with
`npx skills@latest add thititongumpun/skills`, or `skills/<name>/SKILL.md`
when working inside this repo.

| Skill | Read it when |
| --- | --- |
| `confluent-kafka-admin` | Administering, provisioning, securing, scaling, upgrading, or troubleshooting a Kafka/Confluent cluster; `confluent` CLI, Confluent Cloud API, or Confluent Terraform provider work. |
| `confluent-kafka-developer` | Designing an event/topic/schema model, explaining a Kafka concept, diagramming a Kafka/Streams flow, or reviewing producer/consumer/Streams/Connect code. |
| `pptx-diagram` | Turning a Mermaid diagram into an editable PowerPoint slide. Requires [officecli](https://officecli.ai). |
| `autopilot` | Self-driving a multi-step task end to end. Needs an agent runtime that can spawn subagents — **Claude Code only** in practice; skip it elsewhere. (A todo tool is used for progress when present; the skill falls back to a reprinted checklist without one.) |

New skill added to this repo? Add a row here too.
