---
name: mfec-pptx-diagram
description: Turn a Mermaid diagram into a PowerPoint slide on the MFEC branded template, using officecli's native mermaid→shapes synthesizer. Produces real editable PowerPoint shapes and connectors (not a flat image) when the diagram type supports it, and can colour-code the path under discussion, annotate it in a separate accent colour, animate a packet travelling the route, stage captions step by step, and build the comparison table and takeaway box around it. Use when the user wants a diagram in a .pptx / PowerPoint deck, wants to export a mermaid diagram to slides, asks for an architecture/flow/sequence diagram they can edit in PowerPoint, or wants a slide to show data moving from A to B.
---

# Mermaid → MFEC PowerPoint diagram

`officecli` renders Mermaid straight into a slide. Write the Mermaid, run
one command — do not hand-place shapes and connectors.

Every deck starts as a copy of the MFEC template, so the diagram lands
inside MFEC branding — master, theme, fonts, colours — rather than on a
blank white slide.

```bash
cp ~/.claude/skills/mfec-pptx-diagram/assets/MFEC_PowerPoint_Template.pptx deck.pptx
officecli add deck.pptx / --type slide --prop layout="Title and Content" --prop title="Architecture"
officecli add deck.pptx '/slide[6]' --type diagram --prop render=native \
  --prop x=2cm --prop y=5cm --prop width=29.9cm --prop height=12.5cm \
  --prop mermaid="flowchart TD; A[Producer] --> B[(Topic)]; B --> C[Consumer]"
```

Copy the template from wherever this skill is installed — the path above is
the usual one; `assets/MFEC_PowerPoint_Template.pptx` beside this file is
the source of truth. Reach for `officecli create` only when the user asks
for an unbranded deck.

## Pick the render mode — this is the only real decision

| Want | Use | Constraint |
|---|---|---|
| Editable shapes in PowerPoint | `render=native` | **Only `flowchart`/`graph` and `sequenceDiagram`.** Other types are rejected with a clear message. |
| Any mermaid type (gantt, pie, class, state, er, …) | `render=image` | Embeds a PNG via headless Chrome. Not editable; mermaid source is stamped into alt-text so it can be regenerated. |

Default is `render=auto`, which prefers the browser/PNG path when a browser
exists — so **pass `render=native` explicitly whenever the user wants
editable shapes**, otherwise they may silently get a picture.

If a diagram must be editable but isn't a flowchart/sequence, say so and
offer either the image path or a flowchart reshaping of the same content —
don't quietly fall back.

## The template

16:9, 960 × 540 pt (33.87 × 19.05 cm). Its 5 slides are **samples, not
content** — Thai/English placeholder strings like `หัวข้อสไลด์ (Slide Title)`
and `[คำอธิบายหลักของหัวข้อย่อยนี้]` marking where real text goes. Treat each
as a shape to fill, and pick the one whose shape matches what you're
presenting:

| Path | Shape of the slide | Use when |
|---|---|---|
| `/slide[1]` | Title + subtitle | The cover — always fill this in |
| `/slide[2]` | Title, bullet column, **diagram/image box** | A diagram with commentary beside it |
| `/slide[3]` | Title + numbered points, each with sub-detail | Prose/bullet content, no diagram |
| `/slide[4]` | Comparison table, two options | Weighing A against B |
| `/slide[5]` | Specification table, label/value rows | Config, specs, parameters |

Two rules follow from that. **Every placeholder string gets overwritten or
its shape deleted** — a deck that ships with `[ระบุค่า]` still in it isn't
done. And **the user's content decides the slide count**: clone the matching
sample once per piece of content, then delete the untouched originals.

### What you change vs. what you leave

| Dynamic — you set it | Fixed — never touch it |
|---|---|
| Slide text, bullets, table cells | Fonts (Prompt / Prompt Medium / TH SarabunPSK) |
| Which sample is cloned, and how many | Theme colours, master, background art |
| The diagram itself | Title bar, logo, decorative freeforms |
| Page numbers and footers (below) | Their position and styling, which come from the layout |

Never restyle a copied shape — set its `text` and let the master supply the
rest. If a font or colour looks wrong, the wrong layout was cloned.

A slide you append lands at `/slide[6]`, not `/slide[1]` — run
`officecli get deck.pptx / --depth 1` before addressing any path.

### Copy slide 2 — it already has a diagram box

`--from` clones a whole branded slide, decorations and all. Shape ids are
renumbered on copy, so read them back rather than reusing the ones below:

```bash
officecli add deck.pptx / --from '/slide[2]'          # → /slide[6]
officecli get deck.pptx '/slide[6]' --depth 1        # find title + placeholder ids
officecli set deck.pptx '/slide[6]/shape[@id=100001]' --prop text="Kafka Architecture"
officecli remove deck.pptx '/slide[6]/shape[@id=100006]'   # the placeholder rectangle
officecli add deck.pptx '/slide[6]' --type diagram --prop render=native \
  --prop x=13.5cm --prop y=3.4cm --prop width=18.7cm --prop height=13.9cm \
  --prop mermaid="..."
```

That box is exactly where the placeholder sat — right of the bullet column.

For a diagram-only slide, add a fresh one and **name the layout**: the
default is `Title Slide`, which is the cover layout, not a content one.

```bash
officecli add deck.pptx / --type slide --prop layout="Title and Content" --prop title="Architecture"
```

Layouts available: `Title Slide`, `Title and Content`, `Two Content`,
`Blank`, `Title & Non bulleted text`, `Contents slide layout`. Then use
`x=2cm y=5cm width=29.9cm height=12.5cm`. Not `y=3.5cm` — that layout's
title placeholder is 104pt tall and runs to `y=4.66cm`, so a diagram starting
higher lands underneath it.

Both boxes are bounds, not a stretch — aspect is preserved and the diagram
centres inside. Diagram text inherits the master's Prompt / TH SarabunPSK.

### Page numbers and footers

The template's 5 slides carry **no** slide-number or footer shape — the
layouts define the slots, but nothing materialises them, so the deck ships
unnumbered. If the user wants numbering, add it; two commands per slide,
because officecli creates the placeholder but not the field inside it:

```bash
officecli add deck.pptx '/slide[6]' --type placeholder --prop phType=slidenum
officecli raw-set deck.pptx '/slide[6]' \
  --xpath "//p:sp[p:nvSpPr/p:nvPr/p:ph/@type='sldNum']/p:txBody/a:p" \
  --action prepend \
  --xml '<a:fld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" id="{A662FDBF-B848-43FF-B09D-5819394CBACC}" type="slidenum"><a:t>6</a:t></a:fld>'
```

`prepend`, not `append` — `<a:endParaRPr>` must stay last or the deck fails
`officecli validate`. The `<a:t>` is only a cached value; PowerPoint
recomputes the real number, so reordering slides stays safe. Same shape for
a footer with `phType=footer`, minus the field — set its `text` instead.

This works on any layout, including `Contents slide layout` (the one all 5
samples use) which defines no such slot — officecli writes an explicit
bottom-right position from the master. Number the whole deck or none of it;
half-numbered is worse than unnumbered.

Finally delete every sample slide the content doesn't need, **highest index
first** so the paths ahead don't shift:

```bash
officecli remove deck.pptx '/slide[5]'
officecli remove deck.pptx '/slide[4]'
```

`poster=true` resizes the slide and breaks the template's proportions —
leave it off for MFEC decks.

## Placing and adjusting

- Default: scaled to fit the slide, centred. Slide size never changes.
- Explicit box: `--prop x=2cm --prop y=2cm --prop width=15cm --prop height=10cm` (aspect always preserved).
- `--prop src=diagram.mmd` loads Mermaid from a file instead of inline.

**The box is not clamped.** Give `x+width > 33.87cm` or `y+height > 19.05cm`
and officecli places the group off the slide edge — nodes and labels are
simply cut off, and `officecli view issues` stays silent about it. Keep every
box inside `x+width ≤ 32cm` and `y+height ≤ 17.5cm` (leaving the title band
clear of the title band), and re-check the group's real geometry after the add — a
wide flowchart grows to fill the width you gave it.

Add returns one group path, e.g. `/slide[1]/group[1]`. The whole diagram
stays adjustable as a unit:

```bash
officecli set deck.pptx '/slide[1]/group[1]' --prop width=20cm --prop keepAspect=true
officecli remove deck.pptx '/slide[1]/group[1]'
```

Child font sizes re-bake on resize, so text stays proportional. A lone
`width` or `height` changes only that axis — add `keepAspect=true`, or pass
both for an exact box.

## Colour-code the diagram, and annotate in a colour of its own

A diagram on a slide is always being used to make a point, so **the point has
to be visually separable from the rest of the picture**. Two jobs, two
colour tracks:

- **The path/component being discussed** — recolour those nodes and edges.
- **Annotations** (numbered callouts, "retries happen here", latency labels) —
  a separate accent that appears *nowhere* in the diagram body, so a reader
  can tell commentary from architecture at a glance.

`classDef` and `style` in the Mermaid source are **ignored** by
`render=native` — every node comes back in officecli's shape-type default
(`#DAE8FC` rect, `#E1D5E7` cylinder, …). Colour after the add, per shape:

```bash
officecli get deck.pptx '/slide[6]/group[1]' --depth 1   # node + connector ids
officecli set deck.pptx '/slide[6]/group[@id=100000]/shape[@id=100002]' \
  --prop fill=#FF6B00 --prop line=#B44A00 --prop color=#FFFFFF
officecli set deck.pptx '/slide[6]/group[@id=100000]/connector[@id=100004]' \
  --prop color=#FF6B00 --prop lineWidth=2pt
```

Annotations are top-level textboxes, not diagram nodes — they must not look
like one:

```bash
officecli add deck.pptx '/slide[6]' --type textbox --prop text="① Retries here" \
  --prop x=3cm --prop y=13cm --prop width=7cm --prop height=1.4cm \
  --prop fill=#FFF4E5 --prop line=#FF6B00 --prop color=#7A3B00 --prop size=12pt
```

Suggested split — MFEC orange carries the emphasis, a muted tint carries the
commentary, everything else stays in the neutral defaults:

| Role | fill | line | text |
|---|---|---|---|
| Emphasised node / hot path | `#FF6B00` | `#B44A00` | `#FFFFFF` |
| Annotation callout | `#FFF4E5` | `#FF6B00` | `#7A3B00` |
| Secondary / deprecated path | `#F2F2F2` | `#9A9A9A` | `#5A5A5A` |
| Everything else | leave officecli's default | | |

Three rules keep it readable: **at most two accents per slide** (a third
reads as decoration), **numbers on the callouts** (①②③) matched to a marker
on the node so the eye can pair them, and **the flow-motion marker fill
distinct from both accents** if a packet is also animating — its default
`#FF6B00` collides with the emphasis colour above, so pass `--fill` when
both are on the same slide.

Recolouring diagram nodes is not the same as restyling template shapes —
the ban above is on the branded chrome, which still stays untouched.

## Make the flow readable — motion, steps, and the slides around it

A static box-and-arrow picture asks the audience to work out the direction for
themselves. Three devices fix that, in increasing cost.

### A packet that travels the route — `flow-motion.py`

PowerPoint will not animate a shape inside a group, and a native diagram *is*
a group — `officecli add --type animation` on the group or any of its nodes is
rejected outright. So the moving thing has to be a separate top-level shape
riding over the diagram. The bundled helper does that:

```bash
python3 ~/.claude/skills/mfec-pptx-diagram/assets/flow-motion.py \
  deck.pptx '/slide[6]' Producer Kafka Consumer
# → /slide[6]/shape[@id=100001]: 2 hop(s) Producer -> Kafka -> Consumer
```

It finds each node by its text (case-insensitive substring; an ambiguous or
missing name is an error listing what it did find), drops a marker on the first
one, and adds one motion leg per hop, each `trigger=afterPrevious`. Flags:
`--size` (cm, default 0.9), `--fill` (default `#FF6B00`), `--duration` (ms per
hop), `--loop` to run continuously while the slide is up.

Legs are cumulative on purpose: `animMotion` is written with `origin="layout"`,
so every leg is measured from the marker's *original* position, and hop 2 of a
three-node route reads `M 0.2067 0 L 0.4134 0 E`. Writing each hop as its own
`M 0 0 L …` sends the marker back to the start every time.

Run it after the diagram is placed and saved — it reads the node coordinates
out of the file.

### Reveal the story one step at a time

Entrance animations work on any top-level shape, so caption boxes can appear in
step with the marker:

```bash
officecli add deck.pptx '/slide[6]/shape[@id=100010]' --type animation \
  --prop effect=fade --prop class=entrance --prop trigger=afterPrevious --prop duration=400
```

`trigger=onClick` for presenter-paced, `afterPrevious` for hands-off. Order is
the order you add them. The diagram itself cannot be staged this way; it
arrives whole.

### Morph between two states

For "before / after" — a queue filling, a failover — duplicate the slide with
`--from`, move the marker on the copy, and set `--prop transition=morph` on the
second. PowerPoint tweens the shapes between them. Needs PowerPoint 2019 or
365; older versions fall back to a cut, so don't hang the explanation on it.

## Diagram, comparison, conclusion — the three-slide shape

One diagram rarely answers the question on its own. When the user is comparing
options or expects a verdict, build the deck as a short argument:

**1. The diagram slide** — the flow, animated as above. Title says what the
system does, not "Architecture".

**2. The comparison table** — clone `/slide[4]` (9×3) and fill it. Cells are
`tr[R]/tc[C]`, both 1-based; `table-row`/`table-cell` are not valid path
segments:

```bash
officecli add deck.pptx / --from '/slide[4]'
officecli query deck.pptx 'table' --compact          # → /slide[7]/table[@id=100008] [table 9x3]
officecli set deck.pptx '/slide[7]/table[@id=100008]/tr[1]/tc[2]' --prop text="Kafka"
officecli set deck.pptx '/slide[7]/table[@id=100008]/tr[1]/tc[3]' --prop text="RabbitMQ"
officecli set deck.pptx '/slide[7]/table[@id=100008]/tr[2]/tc[1]' --prop text="Ordering"
```

The table id is renumbered on clone, so read it back — `@id=6` is the id on the
sample, not on your copy. The same `query` reports the real grid (`9x3`); delete
the rows you don't fill — an empty row reads as
missing data. Use `/slide[5]`'s 6×2 tables instead for label/value specs.

**3. The result box** — one top-level textbox with the takeaway, not a
restatement of the diagram. On a `/slide[2]` clone the bullet column is already
there; on a diagram-only slide add one under the diagram:

```bash
officecli add deck.pptx '/slide[6]' --type textbox --prop text="Ordering is per-partition, so a single consumer group keeps per-key order." \
  --prop x=2cm --prop y=17.6cm --prop width=29.9cm --prop height=1.2cm
```

Skip any of the three the content doesn't need — a deck with an empty
comparison table is worse than one without it.

## Verify before claiming it worked

Four checks, all of them, every time — they catch different failures and none
of them subsumes the others. In particular `officecli view issues` reporting
zero does **not** mean the text fits; see the `autoFit=shape` trap below.

```bash
officecli get deck.pptx '/slide[6]' --depth 1     # shapes + connectors present?
officecli query deck.pptx ':contains("[")'        # leftover placeholders — must be empty
officecli view deck.pptx issues                   # text overflowing its own shape
python3 ~/.claude/skills/mfec-pptx-diagram/assets/check-layout.py deck.pptx   # off-slide, overlap, overfull
officecli validate deck.pptx                      # after any animation work
```

The `query` must come back empty. Every hit is a template placeholder still
sitting where the user's content belongs.

### Text that doesn't fit its shape — `view issues`

`issues` reports each text body whose lines need more height than the shape
gives them, with the fix baked in:

```
[O1] /slide[6]/shape[@id=100002]: text overflow: 9 lines at 18.0pt need 194pt,
     usable 21pt. suggest.height=7.15cm
```

Apply `suggest.height` when there is room below, otherwise shorten the text.
`--prop autoFit=shrink` is the last resort — it keeps the text inside but
shrinks it off the template's type scale, so a slide full of shrunk boxes
means too much content, not a font problem. Never set an explicit `fontSize`
to make text fit; the master owns the type scale.

It also flags a *text* shape crossing the slide edge. It flags nothing else:
not a picture, not a diagram group, not two shapes on top of each other, and
not any box left at the template's default `autoFit=shape`.

`issues` reports one pre-existing overflow on the template's `/slide[5]` spec
table — that's the template's, not yours. Ignore it, or delete that sample
slide.

### Text that grows past the slide — the `autoFit=shape` trap

Every text box in this template ships with `autoFit=shape` (OOXML
`spAutoFit`): PowerPoint resizes the box to its text instead of clipping.
That makes overflow invisible to both checks above. `view issues` skips
grow-to-fit shapes entirely, and the stored `height` is just the last cached
value, so a box holding three times its capacity reports **0 issues** and
`layout ok` — then renders halfway down the next slide's worth of space.

`check-layout.py` measures it the only reliable way: it copies the deck, turns
`autoFit` off on every grow-to-fit box, and reads back the height each one
actually asks for.

```
OVERFULL   /slide[7]/shape[@id=100091] '"Scenario 1 — ปิด R (INFO)…' needs 17.2cm, box is 8.0cm — runs 5.0cm off the slide bottom. Split it across slides
OVERFULL   /slide[4]/shape[@id=100019] '"1. โจทย์และข้อจำกัด…' needs 12.5cm, box is 10.7cm — grows into /slide[4]/shape[@id=100073] '"อ้างอิง: docs.confluent.'
grows       /slide[2]/shape[@id=100005] '"อาการ: L เข้ามาก่อน R…' needs 8.9cm, box is 8.0cm — 0.9cm past its box, still lands clear
```

`OVERFULL` fails the run; the lowercase `grows` lines are notes — a box that
spills a few millimetres and still lands clear of everything is not worth
failing over.

**The fix is fewer words, not a smaller font.** `--prop autoFit=shrink` and a
hand-set `fontSize` both keep the text inside by taking it off the template's
type scale, and a 9pt paragraph on a projector is not communication. Split the
content across two slides — that is almost always what an overfull box is
telling you.

### Budget the text before you write it

Measured against the master's 14pt, with `autoFit` off so the box cannot lie:

| Box | Size | Holds |
|---|---|---|
| `/slide[2]` bullet column | 9.98 × 8.04 cm | **14 wrapped lines** (15 overflows) |
| `/slide[3]` body column | 24.96 × 10.69 cm | **18 wrapped lines** (19 overflows) |

*Wrapped* lines, not paragraphs — one long sentence in the narrow slide-2
column is three or four of them, and Thai wraps sooner than Latin at the same
character count.

Count before you fill. Two numbered scenarios with three sub-points each do
not fit one column; that is two slides. If the user hands you more prose than
the budget allows, split it and say you did — silently shrinking it to fit is
the failure this whole section exists to prevent.

### Off the slide, or on top of something — `check-layout.py`

Bundled beside the template. It reads every top-level shape, group, picture
and table, and fails on two things `issues` cannot see:

- **OFF-SLIDE** — the element's box leaves the 33.87 × 19.05 cm slide. This is
  the usual way a diagram loses nodes: the group grew past the right or bottom
  edge and PowerPoint just clips it.
- **OVERLAP** — a diagram, picture or chart covering ≥10% of a text shape
  (or of another diagram) on the same slide. Template decoration behind text
  is not reported; that's design, not a collision.

```
OFF-SLIDE  /slide[6]/group[@id=100007] '(empty)' box=27.6,15.0 to 34.4,23.0cm slide=33.9x19.1cm
OVERLAP    /slide[6]/shape[@id=100005] 'TextBox 4' over /slide[6]/group[@id=100007] 'Diagram 100007' (90% of the smaller)
```

Exit code 1 means unshipped. Fix by moving or shrinking the *diagram* —
`officecli set deck.pptx '/slide[6]/group[1]' --prop x=... --prop width=... --prop keepAspect=true` —
never by nudging branded template shapes. On slide-2 clones the bullet column
runs to about `x=11.7cm`, so the diagram starts at `x=13.5cm`.

Group children are deliberately not bounds-checked: they use the group's own
coordinate space, so their coordinates mean nothing against the slide. The
group's box is what gets clipped, and that is what the script tests.

### Visual check

`officecli view deck.pptx screenshot -o out.png` (or `svg`), then read the
image — the only way to see a node label spilling past its own node outline.
Needs a headless browser; without one, both this and `render=image` are
unavailable and `render=auto` falls to native. Say so rather than implying you
looked at the slide.

## Shell gotchas

- Quote the whole Mermaid string; use `;` between statements for one-liners.
- Newlines inside `--prop text=` need `\\n`, not `\n`.
- Paths are 1-based and must be quoted: `'/slide[1]'`.

## Notes

- Unsure whether a Mermaid construct exists or how it's spelled? Query
  context7 (`/mermaid-js/mermaid`) rather than guessing — it carries versioned
  syntax docs, and a mermaid parse error surfaces as a failed `add` with no
  slide. Check its `Versions:` list against the mermaid your renderer bundles;
  newer syntax silently fails on an older parser.
- For a whole *deck* (multiple slides, layout, theming) rather than a
  diagram, load officecli's own deck skill first: `officecli load_skill pptx`.
- Mermaid already renders in GitHub, on claude.ai, and in a published
  Artifact — but **not** in the Claude Code terminal, which has no graphics
  protocol and prints the fence as literal text. Only reach for this skill
  when the target really is PowerPoint; reach for `whiteboard` when you
  just need to *see* a diagram to agree on it.
