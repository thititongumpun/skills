---
name: pptx-diagram
description: Turn a Mermaid diagram into a PowerPoint slide using officecli's native mermaid→shapes synthesizer. Produces real editable PowerPoint shapes and connectors (not a flat image) when the diagram type supports it. Use when the user wants a diagram in a .pptx / PowerPoint deck, wants to export a mermaid diagram to slides, or asks for an architecture/flow/sequence diagram they can edit in PowerPoint.
---

# Mermaid → PowerPoint diagram

`officecli` renders Mermaid straight into a slide. Write the Mermaid, run
one command — do not hand-place shapes and connectors.

```bash
officecli create deck.pptx                       # only if it doesn't exist
officecli add deck.pptx / --type slide --prop title="Architecture"
officecli add deck.pptx '/slide[1]' --type diagram --prop render=native \
  --prop mermaid="flowchart TD; A[Producer] --> B[(Topic)]; B --> C[Consumer]"
```

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

## Placing and adjusting

- Default: scaled to fit the slide, centred. Slide size never changes.
- Explicit box: `--prop x=2cm --prop y=2cm --prop width=15cm --prop height=10cm` (aspect always preserved).
- `--prop poster=true` grows the *slide* to the diagram's natural size — use for "export this diagram as a slide", not for a diagram inside a normal deck.
- `--prop src=diagram.mmd` loads Mermaid from a file instead of inline.

Add returns one group path, e.g. `/slide[1]/group[1]`. The whole diagram
stays adjustable as a unit:

```bash
officecli set deck.pptx '/slide[1]/group[1]' --prop width=20cm --prop keepAspect=true
officecli remove deck.pptx '/slide[1]/group[1]'
```

Child font sizes re-bake on resize, so text stays proportional. A lone
`width` or `height` changes only that axis — add `keepAspect=true`, or pass
both for an exact box.

## Verify before claiming it worked

```bash
officecli get deck.pptx '/slide[1]' --depth 1     # shapes + connectors present?
officecli view deck.pptx issues
```

For a visual check: `officecli view deck.pptx screenshot -o out.png` (or
`svg`), then read the image.

## Shell gotchas

- Quote the whole Mermaid string; use `;` between statements for one-liners.
- Newlines inside `--prop text=` need `\\n`, not `\n`.
- Paths are 1-based and must be quoted: `'/slide[1]'`.

## Notes

- For a whole *deck* (multiple slides, layout, theming) rather than a
  diagram, load officecli's own deck skill first: `officecli load_skill pptx`.
- Mermaid renders natively in Claude Code and GitHub already — only reach
  for this skill when the target really is PowerPoint.
