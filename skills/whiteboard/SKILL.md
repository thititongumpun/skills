---
name: whiteboard
description: Turn a pile of requirements into a diagram you can actually look at — draws the flow as a live page in your browser, gets it confirmed or corrected, and when more than one design genuinely fits, shows the trade-offs side by side and asks you to pick. Stops at a confirmed design and never implements it. Use when the user says "whiteboard this", "/whiteboard <requirements>", "draw this out", "diagram these requirements", "show me the flow", "visualize this before we build it", or hands over a spec and wants to see the shape of it first. Needs Node, a browser on the same machine, and the superpowers plugin — degrades to a mermaid fence in the terminal without them.
---

# Whiteboard

Requirements in, one picture out, agreement before anyone writes code. You
draw the flow in the user's browser, they tell you what's wrong, you redraw.
When the requirements genuinely admit more than one design you show the
trade-offs and make them choose. **You stop at a confirmed design — this
skill never implements anything.**

## Write mermaid once, render it twice

The diagram is mermaid source. Always. It is the compact thing you can
revise, the thing that survives into the summary, and the thing
`pptx-diagram` consumes later.

That one source renders in two places:

- **In the browser** — inside `<pre class="mermaid">`, with the CDN module
  imported at the bottom of the fragment (see the recipe). It renders as a
  real diagram: the companion server sets no `script-src` CSP, and every
  push is a full page reload, so the module re-runs on every screen.
- **In the terminal summary** — as a ```mermaid fence. It does *not* render
  there, and that's fine. It's the copy-pasteable artifact, not the visual.

Hand-build HTML only where mermaid is the wrong tool — UI wireframes, which
is what `.mock-nav` / `.mock-sidebar` / `.mock-content` / `.placeholder`
are for. Never hand-author SVG boxes and arrows; you will spend more tokens
on coordinates than on the design.

If the CDN is unreachable the `<pre>` degrades to readable mermaid text.
Degraded, not broken — don't build a fallback path for it.

## The browser carries the picture, the terminal carries the decision

Not a preference, a division of labour. The browser gets anything spatial:
the flow, the boxes, the full pros/cons tables. The terminal gets anything
the user has to *answer*: clarifying questions, and the final pick.

So the comparison is deliberately duplicated. Full pros/cons on the page,
because that's where they can be read side by side. Then an
`AskUserQuestion` with one option per solution, because that's where a
choice costs one keypress instead of a typed paragraph. Do both. Showing
only the page makes them type; showing only the question makes them choose
blind.

## Phase 0: Read it back before you draw anything

Restate the requirements in your own words — actors, triggers, data,
boundaries, and what's explicitly out of scope. A diagram of a misread
requirement is worse than no diagram: it looks authoritative, so the user
trusts it instead of checking it.

Ask blocking questions in the terminal with `AskUserQuestion`, and only
blocking ones — a gap you can draw as an open question on the diagram is
not blocking. Never start the server just to ask a text question.

## Phase 1: Decide the shape — one solution or several

**Default to one.** You did the work; ship the answer.

Go to several only when the requirements contain a fork they cannot settle
themselves — a trade the *user* owns because it spends something they value
against something else they value: cost against latency, ship-this-week
against scale-next-year, build against buy, consistency against
availability. If you can pick the winner from the requirements alone, you
have already picked. Present it.

Three is the cap and two is usually right. Never include an option you
would argue against — a straw option is a fake choice that burns a screen
and teaches the user your comparisons are theatre.

## Phase 2: Start the server, in its own directory

```bash
SP=$(jq -r '.plugins["superpowers@claude-plugins-official"][0].installPath' \
  ~/.claude/plugins/installed_plugins.json)
WB="$SP/skills/brainstorming/scripts"
```

The `.plugins` prefix is load-bearing — without it the query returns
`null`. If `SP` is null or empty the plugin isn't installed: say so, hand
over the mermaid fence in the terminal, and carry on without the browser.
Don't vendor the server.

**Check for a live session before starting one.** `start-server.sh` is not
idempotent — a second run binds a second port while the user's tab keeps
watching the first. Take the newest session dir under
`.whiteboard/.superpowers/brainstorm/`; if its `state/server-info` exists,
`state/server-stopped` does not, and the pid in `state/server.pid` is
alive, reuse it. The URL is in `server-info`.

Otherwise:

```bash
"$WB/start-server.sh" --project-dir "$PWD/.whiteboard" \
  --idle-timeout-minutes 90 --open
```

Its own `--project-dir` on purpose: that keeps the `.last-port` and
`.last-token` files clear of a real `superpowers:brainstorming` session in
the same repo, so a whiteboard restart can't renegotiate the port a live
brainstorming tab is bound to. Yes, the path nests as
`.whiteboard/.superpowers/brainstorm/` — that's the script's own layout,
leave it. Mention `.whiteboard/` for `.gitignore` once, then drop it.

Capture `url`, `screen_dir`, and `state_dir` from the single JSON line it
prints. `SESSION_DIR` is the parent of `state_dir`.

## Phase 3: Draw

Write the fragment with a file-creation tool. **Never `cat`/heredoc** — it
dumps the entire page into the terminal.

Fresh semantic filename on every push, never reused: `flow.html`,
`solutions.html`, `flow-v2.html`. The server serves newest-by-mtime.

One diagram per screen when there's one solution. With several, use one
screen holding them stacked — each in a `.mockup` with its `.pros-cons`
directly beneath, then a single `.options` block at the bottom. `.split` is
for two small things; two flowcharts side by side are unreadable.

Then end your turn. Give them the **complete** URL including `?key=…`, one
sentence on what's on screen, and ask for a reaction. Re-share the full URL
every push, not just the first — a bare `host:port` is refused with a 403.

## Phase 4: Confirm or correct — loop here

The terminal reply is the answer. `$STATE_DIR/events` is a hint: JSONL
click records, wiped whenever a new filename appears in the content dir. No
file means they didn't click, which means nothing — not "no preference". A
click pattern contradicting their text is worth one question, not a
decision.

Wrong or incomplete? Redraw as `-v2` and loop. Do not advance to the
comparison or the summary while the diagram is still being corrected —
getting the picture right *is* the deliverable.

## Phase 5: Let them pick with one keypress

Only when Phase 1 said several. The screen already carries the full
pros/cons; now ask in the terminal.

`AskUserQuestion`, one option per solution, each label the solution's name
and each description its one-line trade in the user's terms ("Simplest, but
the payment provider's outage becomes your outage"). **State your
recommendation and why before you ask** — a comparison with no
recommendation is you refusing to have an opinion. Their pick overrides it
without argument.

Add an "explain more" option only when a real question is still open.

## Phase 6: Summarize, unload the screen, stop

Push a closing screen — the chosen diagram alone, no options — or, if the
conversation has moved back to text, the waiting screen:

```html
<div style="display:flex;align-items:center;justify-content:center;min-height:60vh">
  <p class="subtitle">Continuing in terminal...</p>
</div>
```

Never leave a resolved choice on screen while the terminal has moved on.

Then in the terminal: the confirmed design in prose, the mermaid fence, the
decisions made and why, and every open question you did not resolve. Leave
the server running — it dies on idle timeout, and again when Claude Code
exits, because the launcher registers the harness pid as its owner. Only
run `"$WB/stop-server.sh" "$SESSION_DIR"` if they ask.

**Then stop.** Don't start implementing, don't write a plan file, and don't
offer to "go ahead and build it" as a leading question. Say the design is
confirmed and that the next move is theirs.

## Screen recipe

Fragment only — no `<html>`, no CSS. The server wraps it.

```html
<h2>Refund flow — two ways to build it</h2>
<p class="subtitle">Read both diagrams, then pick at the bottom.</p>

<div class="mockup">
  <div class="mockup-header">A — refund synchronously in the checkout API</div>
  <div class="mockup-body">
    <pre class="mermaid">
flowchart LR
  U[Customer] --> API[Refund API]
  API --> PSP[Payment provider]
  PSP --> API
  API --> DB[(orders)]
  API --> U
    </pre>
  </div>
</div>
<div class="pros-cons">
  <div class="pros"><h4>Pros</h4><ul>
    <li>Customer sees the outcome immediately</li>
    <li>No queue, no worker, no retry state to own</li>
  </ul></div>
  <div class="cons"><h4>Cons</h4><ul>
    <li>Provider outage becomes a user-visible failure</li>
    <li>Your p99 is their p99</li>
  </ul></div>
</div>

<div class="mockup">
  <div class="mockup-header">B — queue it, settle in a worker</div>
  <div class="mockup-body">
    <pre class="mermaid">
flowchart LR
  U[Customer] --> API[Refund API]
  API --> Q[[refunds queue]]
  API --> U
  Q --> W[Refund worker]
  W --> PSP[Payment provider]
  W --> DB[(orders)]
  W --> N[Email customer]
    </pre>
  </div>
</div>
<div class="pros-cons">
  <div class="pros"><h4>Pros</h4><ul>
    <li>Provider outages retry instead of failing the request</li>
    <li>Checkout latency is yours again</li>
  </ul></div>
  <div class="cons"><h4>Cons</h4><ul>
    <li>A queue, a worker, and a DLQ to operate</li>
    <li>"Refunded" is now eventually true — the UI must say so</li>
  </ul></div>
</div>

<div class="options">
  <div class="option" data-choice="a" onclick="toggleSelect(this)">
    <div class="letter">A</div>
    <div class="content"><h3>Synchronous</h3>
      <p>Least to build. Their outage is your outage.</p></div>
  </div>
  <div class="option" data-choice="b" onclick="toggleSelect(this)">
    <div class="letter">B</div>
    <div class="content"><h3>Queued</h3>
      <p>Survives provider failures. One more moving part to run.</p></div>
  </div>
</div>

<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
  mermaid.initialize({
    startOnLoad: true,
    theme: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default'
  });
</script>
```

The theme probe matches the frame's own OS-aware light/dark, so the diagram
doesn't come out as a white slab on a dark page.

## Failure modes to avoid

- **Drawing before you understand.** A confident diagram of the wrong
  requirement is the one failure the user can't catch, because it looks
  exactly like you understood.
- **Two servers.** Check for a live session first. The second binds a
  different port and the user sits on a tab that never updates.
- **A URL without `?key=`.** Refused with a 403 page. Re-share the whole
  URL every push.
- **`cat`/heredoc into the content dir.** Dumps the page into the terminal.
  Use a file-creation tool.
- **Reusing a filename.** Newest-by-mtime still resolves, but the events
  file only clears on a *new* filename — so stale clicks survive into the
  next screen and read as fresh answers.
- **Treating `events` as the answer.** Terminal text is primary. A missing
  events file means they didn't click, not that they have no opinion.
- **Manufacturing alternatives.** Two solutions because the problem has
  two, never because a comparison looks more thorough than an answer.
- **Comparing without recommending.** Lay out the trade-offs, then say
  which one you'd ship and why. "It depends on your priorities" is the
  answer you were asked to replace.
- **Advancing on an unconfirmed diagram.** Loop on Phase 4 until it's
  right. Everything downstream inherits the error.
- **Sliding into implementation.** Hard stop at the confirmed design, in
  both directions — no code, and no "shall I build it now?" nudge.
