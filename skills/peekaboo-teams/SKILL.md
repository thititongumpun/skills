---
name: peekaboo-teams
description: macOS only. Send a message to, find, or open a Microsoft Teams chat on the user's Mac desktop via the Peekaboo CLI (foreground). Do not use on Linux/Windows or remote servers. Use when the user asks to "ส่ง chat/ms team", message someone in Teams, scroll the Teams chat list, or open a named Teams chat.
---

# Peekaboo + Microsoft Teams (macOS)

Tested working on the user's Mac (Teams new client, process name `MSTeams`).

## Rules
- **macOS only.** Peekaboo, `osascript`, `screencapture`, `sips`, `pbcopy`/`pbpaste` exist only on macOS. If `uname` is not `Darwin` (Linux, Windows, SSH session on a server), don't use this skill — give the user the text to paste instead.
- **Never use the Peekaboo MCP** for Teams: it is background-only, Teams' AX tree is empty (web content), clicks fail and typed text can land in T3 Code's input. Use the CLI with `--foreground`.
- CLI is v4 via npx (no `peekaboo` in PATH). In zsh define a function, not a variable:
  `pk(){ npx -y @steipete/peekaboo "$@" 2>&1; }`
- Before **every** click/type/press, check the frontmost app is Teams; if not, stop — do not type:
  `osascript -e 'tell application "System Events" to get name of first process whose frontmost is true'` → must print `MSTeams`
- Sending is outward-facing: confirm the recipient + text with the user first, verify the draft by screenshot before Enter.
- Mask secrets (passwords → `<password>`, keys, tokens) in anything sent.
- Clean up `/tmp` screenshots and message files afterwards.

## v4 command quirks
| Want | Use |
|---|---|
| focus Teams | `pk app switch --to "Microsoft Teams" --foreground` |
| click | `pk click --at X,Y --global --foreground` (global screen points; `--foreground` required) |
| key / chord | `pk press return --foreground`, `pk press cmd+v --foreground`, `pk press shift+return --foreground` (`hotkey` was removed) |
| move pointer | `pk move --at X,Y --global --foreground` |
| scroll | move pointer over the pane first, then `pk scroll --direction down --amount 10 --app "Microsoft Teams" --foreground` (scroll with `--at` + `--foreground` is refused) |
| screenshot | `pk see` may fail (Bridge socket error) → use `screencapture -x /tmp/t.png; sips -Z 1710 /tmp/t.png` (Retina 2x → resize to logical points so image px = global points) |
| crop a region | `screencapture -x -R x,y,w,h /tmp/t.png` (global points). If you then `sips -Z N`, map back: `point = origin + px * (region_size / image_size)` |

Teams: Enter = send, Shift+Enter = new line.

## Send a message
1. `pk app switch --to "Microsoft Teams" --foreground`, check frontmost = `MSTeams`.
2. Screenshot, locate the chat row in the left sidebar, `pk click --at X,Y --global --foreground`.
3. Screenshot: header must show the intended chat name.
4. Click the message box (bottom centre, "Type a message").
5. Long / multi-line text: write it to `/tmp/teams_msg.txt`, then
   ```bash
   pbpaste > /tmp/clip_backup.txt
   pbcopy < /tmp/teams_msg.txt
   pk press cmd+v --foreground
   sleep 1.5; pbcopy < /tmp/clip_backup.txt; rm /tmp/clip_backup.txt
   ```
   Short text: `pk type "..." --foreground`.
6. Screenshot and Read it: header correct, draft text correct, pasted once.
7. `pk press return --foreground`, screenshot again to confirm it was sent, then remove temp files.

Wrong chat / bad draft: `pk press cmd+a --foreground` then `pk press delete --foreground` in the draft, then open the right chat.

## Find a chat that is not visible
1. `pk move --at 250,700 --global --foreground` (pointer over the chat list).
2. `pk scroll --direction down --amount 10 --app "Microsoft Teams" --foreground`.
3. `screencapture -x -R 70,180,360,850 /tmp/side.png; sips -Z 700 /tmp/side.png` and Read it. Repeat 2–3 until the name shows.
4. Convert the row's image position to global points (see crop formula), click it, screenshot the header to confirm.

**Preferred (faster, tested):** Teams search — `pk press cmd+e --foreground`, `pk type "<chat name>" --foreground`, screenshot, click the chat result row (top of the dropdown), then screenshot the header to confirm. `pk type` may print "Typing did not return an accepted outcome" even though the text landed — check the screenshot before retrying, don't type twice.
