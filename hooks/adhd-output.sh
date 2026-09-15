#!/usr/bin/env bash
# Applies the i-have-adhd output rules to this repo's skills.
#
# The i-have-adhd plugin's always-on flag is global (every session, every
# skill anywhere). This scopes the same rules to skills that live here: fires
# only when the invoked skill name matches a directory under skills/.
#
# ponytail: rules inlined rather than sourced from the i-have-adhd plugin, so
# this works whether or not that plugin is installed. Re-sync by hand if its
# SKILL.md changes.
set -u

root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
skill=$(grep -o '"skill"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
skill=${skill##*:}   # strip a "plugin:name" prefix

[ -n "$skill" ] && [ -d "$root/skills/$skill" ] || exit 0

cat <<'RULES'
Output style for this skill — the reader has ADHD. Shape the response so it can be acted on:

1. Lead with the answer or next action: command, path, or snippet first.
2. Number multi-step work; one bounded action per step.
3. End with one next action doable in under two minutes.
4. Finish the current issue before raising a new one.
5. Restate progress each turn ("step 3 of 5 done").
6. Give time estimates in concrete units, never "a bit".
7. After a change, show what now works.
8. Errors: state location, cause, and fix. No drama.
9. Cap lists to 5 items.
10. No preamble, no recaps, no closers.

Exceptions: explain fully when asked to explain. Confirm before destructive actions. After three failed fixes, stop and name the doubtful assumption. If the request is ambiguous, ask one short question.
RULES
