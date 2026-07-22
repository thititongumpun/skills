# skills

Personal Claude Code skills.

## Install

Copy the skill files with the `skills.sh` installer:

```bash
npx skills@latest add thititongumpun/skills
```

Or install as a native Claude Code plugin (updates when this repo changes):

```
/plugin marketplace add thititongumpun/skills
/plugin install skills@thititongumpun
```

## Skills

- **autopilot** — Opus/Fable plans a task into a task list, subagents
  execute each task (escalating to Opus/Fable when a task is flagged
  complex), then Opus/Fable reviews everything and loops fixes back until
  clean. Trigger: "autopilot", "/autopilot \<task\>", "do this yourself",
  "full auto".
