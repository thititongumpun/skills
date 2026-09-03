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
| `confluent-kafka-developer` | Designing, writing, or reviewing Kafka application work — producers/consumers, Streams, Connect, ksqlDB, Flink — plus explaining concepts and diagramming flows. |
| `fetch-403` | A fetch tool returns 403 / an empty body / a bot-check page on a URL you still need. |
| `mfec-kafka-connect` | Editing, adding, deploying, or verifying a Kafka Connect connector config in an MFEC customer pipeline (Debezium source, JDBC sink, SFTP source, house SMTs) across dev/uat/prd; bumping a connector version; migrating a Debezium version; a connector or its sink data is wrong. Validate → diff → deploy → status → IVT checksums, then update the repo README. |
| `mfec-pptx-diagram` | Turning a Mermaid diagram into an editable PowerPoint slide on the MFEC template — including colour-coding nodes by role with a legend and captions, animating a marker along the route, and the comparison table and takeaway box around it. Requires [officecli](https://officecli.ai); the layout-check and animation helpers need `python3`. |
| `autopilot` | Self-driving a multi-step task end to end. Needs an agent runtime that can spawn subagents — **Claude Code only** in practice; skip it elsewhere. (A todo tool is used for progress when present; the skill falls back to a reprinted checklist without one.) |
| `yolo` | Running a multi-step task unattended (eating/sleeping) — asks everything up front, then plans/executes via subagents fully silent, skips unsafe actions and logs them. Claude Code only, like autopilot. |
| `whiteboard` | Two modes. *Design*: turning raw requirements into a diagram before any code — draws the flow onto a live Excalidraw canvas the user can rearrange by hand, reads their edits back, compares solutions with pros/cons when there's a real fork. *Explain*: diagramming work that already exists and publishing a shareable page so other people understand it. Never implements. Needs Node, a browser, and the excalidraw MCP server; degrades to an `archify` HTML diagram (or a mermaid fence) without them. |
| `explain-repo` | Someone needs to understand a repo they didn't write — "what does this do", onboarding, inheriting a service. Produces a plain-language summary, one architecture diagram (drawn by the external `archify` skill), the external services it depends on, and an explicit list of what could not be determined. Uses CodeGraph (`codegraph init -i` if the repo has no index); degrades to entrypoint reads without it. Read-only. |
| `sync-skill-installs` | Anything under `skills/` in this repo changed, or the user says "reinstall global" / "sync the installs". Copies source into `~/.agents/skills/` and `.agents/skills/`, refreshes `skills-lock.json`, and verifies both match — the three copies do not share files, so editing `skills/` alone changes nothing an agent loads. |
| `skills-doctor` | A skill here needs a tool that isn't installed, something degraded silently, or you want to know what to install after a fresh clone. Run `scripts/doctor.sh`. |

New skill added to this repo? Add a row here too.
