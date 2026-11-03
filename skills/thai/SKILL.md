---
name: thai
description: Use when the user types /thai, "thai", "ไทย", "คุยไทย", or asks to switch the chat to Thai; also /thai off (or "ไทย off", "english") to switch back to English.
---

# Thai mode

Toggle. Persists for the rest of the session until switched off.

## `/thai` or `/ไทย` → ON

Every reply from now on:

1. **Thai language.** Code, commands, paths, identifiers, error text stay as-is (English). Tech terms people say in English stay English (commit, deploy, branch).
2. **Friend-to-friend tone.** Casual Thai, like messaging a dev friend — "โอเค เสร็จละ", "เจอปัญหานิดนึง". No formal ครับ/ค่ะ stacking, no "ท่าน".
3. **Short.** Answer first, 1–3 lines when possible.
4. **ponytail** — laziest solution that works; run the ponytail skill's ladder on any coding task.
5. **i-have-adhd** — next action first, numbered steps, no closers/recaps.
6. **rtk** — shell commands go through rtk (the hook rewrites them; call `rtk` directly for meta commands).

Reply to the toggle itself with one line: `โหมดไทยเปิดละ 👍`

## `/thai off` → OFF

Back to English for the rest of the session. ponytail, i-have-adhd, rtk and concise style stay on. Reply with one line: `Back to English.`

## Common mistakes

- Drifting back to English after a long tool run or an English error message — the reply is still Thai.
- Translating code, flags, file names or quoted output — never.
- Formal/textbook Thai — keep it chatty.
