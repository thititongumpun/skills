---
name: whiteboard
argument-hint: "<requirements> | explain <repo|PR|task>"
description: Turn requirements or existing work into a diagram you can grab and rearrange. Two modes — design mode draws a proposed flow onto a live Excalidraw canvas you can edit by hand, reads your edits back, and compares solutions with pros/cons when more than one fits; explain mode reads work that already exists and publishes a shareable page so other people understand it. Never implements anything. Use when the user says "whiteboard this", "/whiteboard <requirements>", "draw this out", "diagram these requirements", "show me the flow", or "visualize this before we build it" — and for explain mode, "/whiteboard explain <repo/PR/task>", "explain what I'm working on", "document this for the team", "make a diagram to show other people", or "help them understand what I built". Needs Node, a browser, and the excalidraw MCP server for the live canvas; explain mode also needs the Artifact tool to publish.
---

# Whiteboard

Requirements in, one picture out, agreement before anyone writes code. You
draw the flow onto a canvas the user can grab and rearrange, then you read
their rearrangement back and say what changed. When the requirements
genuinely admit more than one design you show the trade-offs and make them
choose. **You stop at a confirmed design — this skill never implements
anything.**

## Two modes, and the audience is what separates them

**Design mode** — `/whiteboard <requirements>`, the default. Work that
doesn't exist yet. The audience is the user, the question is "did I
understand this correctly", and the output is a confirmed design. Phases 0-6
below.

**Explain mode** — `/whiteboard explain <repo, branch, PR, or task>`. Work
that already exists. The audience is *other people*, the question is "will
they understand this", and the output is a page you can send them. See
"Explain mode" near the end.

Pick by asking who reads the diagram. That one question settles everything
else — how much you may assume, what altitude to draw at, and where the
picture has to end up. Design mode is a conversation; explain mode is a
deliverable, and the person it's for is not in the room to ask.

If the user is vague ("whiteboard this repo"), ask which they want rather
than guessing. Drawing existing code as though it were a proposal wastes
their time and yours.

## Author in mermaid, hand over shapes

You still *write* mermaid — it's the compact thing you can revise, it
survives into the summary, and `pptx-diagram` consumes it later. But it is
no longer what the user looks at. `create_from_mermaid` converts it once
into real Excalidraw elements, and from that moment **the canvas is the
source of truth, not your mermaid**. The user is about to change it.

Only `flowchart`, `sequenceDiagram`, and `classDiagram` convert to editable
shapes at the pinned converter version. Everything else — ER, state, gantt,
pie, mindmap — lands as one flat image element the user cannot rearrange,
which defeats the point. Reshape it as a flowchart or say plainly that this
diagram type isn't adjustable. (The MCP's own bundled skill claims ER works.
It does not, at this version.)

Never hand-author element coordinates. Converting mermaid takes one call;
placing boxes by hand costs more tokens than the design did.

### Two rules that decide whether the diagram is readable at all

**Keep every node label short — three or four words.** The canvas ships only
the `Assistant` UI fonts; **Excalifont, which renders canvas text, isn't
bundled**, so text falls back to a wider font while the boxes were sized from
the narrower metrics. Labels overflow and clip about a character off each
end. `entrypoint.sh` is fine; `entrypoint.sh (from client/entrypoint.sh)`
renders as `ntrypoint.sh (from client/entrypoint.sh`. Overflow scales with
length, so short labels are the whole mitigation. Put the detail in your
prose, not in the box.

**Avoid `subgraph`.** Its title is container-bound text, which Excalidraw
re-centres inside the box on every render — so a subgraph around a single
node prints the title straight through that node's label, and a tall
subgraph drops its title into the middle of the diagram across the arrows.
You cannot fix it afterwards: `update_element` on a bound text's x/y is
silently reverted on the next sync. If grouping matters, say it in the
summary or encode it in the node names (`agent :9000`), don't draw a box
around it.

## The canvas carries the picture, the terminal carries the decision

Not a preference, a division of labour. The canvas gets anything spatial:
the flow, the boxes, the arrows the user wants to reroute. The terminal gets
anything the user has to *answer*: clarifying questions, and the final pick.

Pros/cons comparisons live **in the terminal only**, as `AskUserQuestion`
options — one per solution, each description carrying the trade in the
user's own terms. Don't try to draw a comparison table on the canvas; it's a
drawing surface, and a table drawn as rectangles is worse than a table.

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

## Phase 2: Start the canvas and tell them to open it

The canvas is the `excalidraw` MCP server. Check it's registered first; if
it isn't, print this and carry on with the `archify` skill for a static HTML
diagram (a mermaid fence if archify isn't installed either), saying plainly
that there's no adjustable canvas this run:

```bash
claude mcp add excalidraw --scope user \
  -e EXCALIDRAW_NO_AUTOSTART=1 -- npx -y mcp-excalidraw-server
```

**`EXCALIDRAW_NO_AUTOSTART=1` is not optional.** Without it, the MCP server
spawns the canvas the moment the agent connects — meaning an unauthenticated
listener on port 3000 at *every* session start, whether or not anyone is
drawing. That silently defeats the whole start-on-use lifecycle below.
Verified: registering without it left :3000 serving 200 immediately.

Start the canvas explicitly instead, which overrides the guard:

```bash
npx -y mcp-excalidraw-server start
```

It listens on `http://127.0.0.1:3000`. With the guard set, canvas tools fail
with exit code 3 (`auto-start disabled`) until you run that — that's the
design working, not an error to route around.

**Nothing opens the browser for them.** Say the URL out loud, every time.
Until a tab is open there is no frontend, and `create_from_mermaid`,
`export_to_image`, and screenshots all fail — the CLI exits 4 to tell you
so. A canvas nobody has open is a canvas nobody can edit.

`.whiteboard/` holds the exported scenes. Mention it for `.gitignore` once,
then drop it.

## Phase 3: Convert the mermaid, once

**`snapshot_scene` first, always.** `create_from_mermaid` replaces the whole
canvas — verified against 1.1.0, where converting onto a canvas holding two
existing rectangles left fourteen mermaid elements and no trace of them.
Upstream calls this fixed; the published build says otherwise. The snapshot
is what makes it recoverable, and `restore_snapshot` does bring the scene
back intact.

That single fact drives the rule that matters most in this skill: **never
convert mermaid after the user has started editing.** Their work is on that
canvas and the conversion will eat it. If a redraw is genuinely needed, say
what you're about to do, snapshot, and let them agree first.

Converted nodes keep their mermaid IDs — a node written `API[Refund API]`
becomes an element with id `API`. Use those ids to talk about the diagram
and to update single elements later without touching anything else.

**Then look at it before you hand it over.** `get_canvas_screenshot` and
actually read the image. `describe_scene` tells you the elements exist; it
cannot tell you the labels are clipped, the arrows cross, or a title is
printed through a node. Those are exactly the faults that make a user say
"it's hard to see", and they are invisible in the geometry — the stored
widths look fine while the render overflows.

If it's unreadable, fix it in the mermaid and reconvert **now**, before
they've touched anything. Once they start editing, reconverting eats their
work and you're stuck with whatever you shipped.

**Export as soon as it's worth keeping.** `export_scene` to a file the
moment the diagram is right, not only at Phase 6. The canvas is memory-only
and dies with the server — a session that ends, a crash, or the SessionEnd
hook takes the scene *and* every `snapshot_scene` with it, because snapshots
live in that same memory. The file on disk is the only thing that survives.

## Phase 4: Hand over, then read back what they changed

Say what's on the canvas in one sentence, give the URL, and invite them to
rearrange it — move boxes, reroute arrows, add a note, delete what's wrong.
Then **end your turn**.

**Do not write to the canvas while they're editing.** The frontend syncs by
replacing the entire scene, so an element you add inside their edit window
loses. Wait to be told they're done.

When they say so, wait ~1.5s for the 1200ms sync debounce, then
`describe_scene` and **say what changed in their words** — "you moved
Consumer below the DLQ and added a retry note next to it". That readback is
the whole point of the canvas being editable; it's also the only proof the
round trip worked. If `describe_scene` shows nothing moved, say that rather
than pretending you saw an edit.

Their rearrangement is feedback about the design, not just about layout. A
box they dragged out of the main flow is usually them telling you it doesn't
belong there. Ask about it.

Wrong or incomplete? Fix it with element-level updates by id, and loop. Do
not advance to the comparison or the summary while the picture is still
being corrected — getting it right *is* the deliverable.

## Phase 5: Let them pick with one keypress

Only when Phase 1 said several. Draw the options one at a time on the canvas
if they help, but the pros/cons and the pick both live in the terminal.

`AskUserQuestion`, one option per solution, each label the solution's name
and each description its one-line trade in the user's terms ("Simplest, but
the payment provider's outage becomes your outage"). **State your
recommendation and why before you ask** — a comparison with no
recommendation is you refusing to have an opinion. Their pick overrides it
without argument.

Add an "explain more" option only when a real question is still open.

## Phase 6: Export, shut the canvas down, summarize, stop

**The canvas is in memory and dies with the server. Export before you stop
it or the user's edits are gone.** `export_scene` to
`.whiteboard/<name>.excalidraw` first, unconditionally and without asking —
it's the only reopenable record of their arrangement, it costs nothing, and
it needs no browser tab. Losing an hour of layout because someone answered
"no thanks" to a prompt is not a tradeoff worth offering.

**Then ask what else they want out of it**, because that depends entirely on
where the diagram is going and you can't infer it. One `AskUserQuestion`,
multi-select, offering:

- **PNG** — for pasting into Slack, a ticket, or a doc. Cropped to content.
- **SVG** — for a README, a wiki, or anything that should stay crisp.
- **A shareable excalidraw.com link** — see the warning below.
- **Nothing more** — the `.excalidraw` file is enough.

Ask once, here, not per format. Both image exports go through
`export_to_image` **with a `filePath`**, written next to the scene file.

Two things that will bite:

- **PNG and SVG need the browser tab still open.** By Phase 6 the user has
  often closed it. Ask them to reopen `http://127.0.0.1:3000` before
  exporting, or the call fails with exit code 4. Don't stop the server and
  then discover you needed it.
- **`format: "png"` without a `filePath` returns a placeholder string**, not
  an image — the literal text `Base64 png data (N chars). Use filePath to
  save to disk.` Always pass a path for PNG.

The excalidraw.com link (`export_to_excalidraw_url`) **uploads the diagram to
a third party**. It's encrypted with a key that stays in the URL fragment, so
their server can't read it, but anyone with the link can. Say that in one
sentence before doing it and let them decide — the same rule as publishing an
artifact. Never offer it as the default.

Then stop the server (`mcp-excalidraw-server stop`). This is deliberate, not
tidiness — see the security note below. Don't leave an unauthenticated
listener running for days because a session ended untidily.

Then in the terminal: the confirmed design in prose, the mermaid fence, the
path to every file you wrote, the decisions made and why, and every open
question you did not resolve. If their edits changed the design rather than
just the layout, the mermaid you emit should reflect the *edited* version —
regenerate it from what's on the canvas, don't paste back what you wrote in
Phase 3.

**Then stop.** Don't start implementing, don't write a plan file, and don't
offer to "go ahead and build it" as a leading question. Say the design is
confirmed and that the next move is theirs.

## The canvas has no authentication — keep its life short

The MCP's canvas server binds `127.0.0.1` but ships **no auth and wildcard
CORS** (upstream #39, and PR #74 which would fix it is unmerged as of 1.1.0).
While it runs, any page the user visits can read or wipe the canvas.

That is why Phase 6 stops it, and why the registration carries
`EXCALIDRAW_NO_AUTOSTART=1`. Both halves are needed: the env var stops it
coming up at every session launch, and the explicit stop keeps it from
outliving the drawing. Start on use, export, shut down — exposure lasts the
minutes they're drawing, not until the next reboot. If the user asks to
leave it up, that's their call, but say the tradeoff once.

If you find :3000 already listening at the start of a session nobody asked
for, the registration is missing the env var. Fix the registration rather
than just stopping the process.

A `SessionEnd` hook stops the canvas as a backstop, because Phase 6 doesn't
always get reached — sessions get interrupted, run out of context, or are
killed. The canvas is spawned detached with no idle timeout and no owner
watchdog, so without that hook an abandoned session leaves it listening
indefinitely. **The hook is a net, not the plan**: still stop it explicitly
in Phase 6, and note it only exists for plugin installs — `npx skills add`
users have no hook, so for them Phase 6 is the only cleanup there is.

Never bind it to `0.0.0.0` to share a diagram. Explain mode's artifact is
the sharing mechanism.

## Explain mode: the diagram has to outlive the session

Same canvas, different ending — because localhost is not shareable. The
canvas server binds `127.0.0.1` and its scene lives in memory until the
process stops. A URL you send a colleague resolves to nothing on their
machine. So the canvas is where you and the user *agree* on the picture; it
is never the thing you hand over.

**Step 1 — read the work before drawing it.** Explain mode has a failure the
design mode doesn't: you can invent a plausible architecture instead of
reporting the real one, and the audience has no way to catch it. Read the
actual code, the actual PR diff, the actual task list. Trace one real path
end to end. Cite files. If you're summarizing a repo you have not read, say
so and read it first.

**Step 2 — pick the altitude, because the audience decides it.** Ask who
this is for if it isn't obvious; it changes the diagram more than any other
input.

- *Teammates who'll touch the code* — real module and service names, the
  actual data flow, where state lives, the failure paths. Filenames earn
  their place here.
- *Engineers outside the project* — the seams and the contracts, not the
  internals. What goes in, what comes out, what it depends on.
- *Managers or stakeholders* — the business flow in their vocabulary. No
  class names, no infrastructure. What the user does, what the system
  promises, where the work is now.

One altitude per diagram. Mixing them produces a picture that serves nobody
— the stakeholder drowns in `KafkaConsumer` and the teammate learns nothing.

**Step 3 — draft on the canvas and confirm, exactly as in Phases 2-4.** The
user is the fact-checker here, not the audience. Ask specifically: is this
accurate, and is anything missing that the reader will trip over.

**Step 4 — publish the confirmed version as an Artifact.** That's the
shareable, persistent surface — it survives the session and starts private
until the user shares it. Load the `artifact-design` skill before writing
the page, as its tool requires.

**Embed the canvas, not your mermaid.** The user edited the picture; the
page has to show what they ended up with. Call `export_to_image` with
`format: "svg"` and **no** `filePath` — that returns the SVG source inline,
which drops straight into the page.

Two traps here. `format: "png"` without a `filePath` does *not* return an
image; it returns the literal string `Base64 png data (N chars). Use
filePath to save to disk.`, which is useless to embed. And the export needs
an open browser tab like everything else on this canvas — if the user
already closed it, ask them to reopen before you publish.

Then give the user the URL and **say plainly that publishing put the content
on claude.ai**. It starts private, but it has left the machine, and work
code is the user's to disclose, not yours. If they'd rather not publish,
hand them the mermaid fence and the prose — that pastes into Confluence, a
README, or a PR description perfectly well.

**Step 5 — stop.** No implementation, same as design mode.

### If you publish mermaid instead of the canvas SVG

Only do this when the user never edited — the diagram is still exactly what
you authored. Then a plain ```mermaid fence is enough: the Artifact platform
detects the fence and injects its own bundled runtime. **Don't add a script
tag or a CDN import** — the validator rejects a page that already carries a
runtime, and the CSP blocks the CDN anyway.

The moment they've touched the canvas, the fence is a stale picture. Export
the SVG.

## Canvas recipe

Everything goes through the MCP; there is no HTML to write.

```
snapshot_scene            name it, before any mermaid conversion
create_from_mermaid       short labels, no subgraphs
describe_scene            confirm it landed, and what the element ids are
get_canvas_screenshot     LOOK at it — clipping is invisible in describe
export_scene              to a file, as soon as it's worth keeping
  -> hand over, end turn, let them edit
describe_scene            after ~1.5s, read their changes
update_element            fix single nodes by id, never a full redraw
export_to_image           format "svg", no filePath, inline for an artifact
export_scene              .whiteboard/<name>.excalidraw — always, first
  -> ask what else they want
export_to_image           format png|svg WITH filePath, next to the scene
export_to_excalidraw_url  only if asked; uploads to a third party
  -> then stop the server
```

Node ids come from the mermaid source: `API[Refund API]` becomes element
`API`. That is what makes `update_element` usable — you can move or relabel
one node without regenerating the diagram and destroying their layout.

If a call fails with exit code 4, no browser tab is open. Ask them to open
`http://127.0.0.1:3000`; don't retry blindly.

## Failure modes to avoid

- **Drawing before you understand.** A confident diagram of the wrong
  requirement is the one failure the user can't catch, because it looks
  exactly like you understood.
- **Converting mermaid onto a canvas they've edited.** This is the one that
  destroys work. `create_from_mermaid` replaces the whole scene. Snapshot
  first, and don't reconvert once they've started.
- **Writing to the canvas while they're editing.** The frontend syncs the
  entire scene, so your element vanishes and you won't be told. Wait until
  they say they're done.
- **Assuming a tab is open.** Nothing opens the browser for them. Mermaid
  conversion, SVG export, and screenshots all need one; exit code 4 is the
  canvas saying so. Ask, don't retry.
- **Forgetting to export before stopping.** The scene is in memory. Stop the
  server without `export_scene` and their rearrangement is simply gone.
- **Stopping the canvas before the image exports.** PNG and SVG render in
  the browser tab. Ask what they want, export it, *then* shut down — in that
  order, or you're restarting the server to fix your own mistake.
- **Asking whether to save the `.excalidraw`.** Always write it. The prompt
  is about what *else* they want, never about whether to keep their work.
- **Reporting an edit you didn't verify.** If `describe_scene` shows the
  same layout you drew, say nothing moved. Inventing "I see you moved X" is
  worse than the read-only canvas this replaced.
- **Handing over a diagram you never looked at.** `describe_scene` returning
  52 elements is not evidence anyone can read them. Screenshot it and look.
  Clipped labels don't show up in the geometry.
- **Long labels and subgraphs.** The two reliable ways to produce an
  unreadable canvas. See the rules above — both are renderer limits, not
  style preferences.
- **Trusting `snapshot_scene` as a backup.** Snapshots are in the same
  memory as the scene; whatever kills the canvas kills them too. Only an
  exported file is a backup.
- **A duplicate canvas on 3000** (upstream #75) — the agent and the human
  end up on different servers and neither sees the other. If `describe_scene`
  disagrees with what they say is on screen, suspect this first.
- **Manufacturing alternatives.** Two solutions because the problem has
  two, never because a comparison looks more thorough than an answer.
- **Comparing without recommending.** Lay out the trade-offs, then say
  which one you'd ship and why. "It depends on your priorities" is the
  answer you were asked to replace.
- **Advancing on an unconfirmed diagram.** Loop on Phase 4 until it's
  right. Everything downstream inherits the error.
- **Sliding into implementation.** Hard stop at the confirmed design, in
  both directions — no code, and no "shall I build it now?" nudge.

Explain mode adds four of its own:

- **Diagramming a repo you didn't read.** A plausible architecture drawn
  from the directory names is the worst thing this skill can produce: the
  user skims it, it looks right, and it goes to people who cannot check it.
  Read the code, trace one real path, name real files.
- **Handing over a localhost URL.** It resolves to nothing on their machine,
  and the scene dies with the process anyway. The canvas is for agreeing;
  the artifact is for sending.
- **Publishing your mermaid after they edited the canvas.** The page would
  show the diagram you drew, not the one they corrected — a stale picture
  presented as the agreed one. Export the SVG.
- **One diagram for every audience.** Pick an altitude and hold it. A
  picture that tries to serve a stakeholder and a maintainer at once serves
  neither.
- **Publishing without saying so.** The artifact starts private, but the
  content still left the machine. Say it in one sentence and let the user
  decide — their employer's code is not yours to upload quietly.
