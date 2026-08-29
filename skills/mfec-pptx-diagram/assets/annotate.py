#!/usr/bin/env python3
"""Colour a native mermaid diagram by role, caption its nodes, and draw the
legend that explains the colours.

    python3 annotate.py deck.pptx '/slide[6]' \
      --role 'Stream=#C6F0C2:out_l,out_r' \
      --role 'Table=#AED9F5:info_tbl' \
      --note 'out_l=(ตัว trigger ของ main)' \
      --legend tr

`classDef`/`style` in the mermaid source are dropped by render=native, so the
fills have to be set on the shapes afterwards — and a caption cannot be a
diagram node (it would grow the layout and gain a border), so it is a separate
top-level textbox positioned from the node's real coordinates.

Every shape this adds is named `Annotation …`, which is what check-layout.py
keys on to allow it to sit over the diagram on purpose.
"""
import argparse
import re
import sys

from _diagram import CM, nodes, officecli, resolve, slide_size, title_bottom

NOTE_H = 0.75 * CM       # caption box height
NOTE_GAP = 0.15 * CM     # caption-to-node gap
NOTE_PAD = 2.0 * CM      # caption width beyond the node, to fit longer text
SWATCH = (1.1 * CM, 0.62 * CM)
ROW = 0.95 * CM
INSET = 1.0 * CM


def pair(text, what):
    if "=" not in text:
        sys.exit(f"--{what} wants NAME=VALUE, got {text!r}")
    return text.split("=", 1)


def add(deck, slide, kind, name, box, *props):
    x, y, w, h = box
    return officecli("add", deck, slide, "--type", kind,
                     "--prop", f"name={name}",
                     "--prop", f"x={int(x)}emu", "--prop", f"y={int(y)}emu",
                     "--prop", f"width={int(w)}emu", "--prop", f"height={int(h)}emu",
                     *props)


def grow_notes(deck, notes):
    """Give every caption the height its text actually needs.

    A caption is one line by default; a longer one silently clips, because
    autoFit=none is the only setting that does not lie about the box (see the
    autoFit=shape trap in SKILL.md). officecli knows the height each text body
    wants — ask it, then grow the box upwards so the caption keeps sitting on
    the node."""
    if not notes:
        return
    for line in officecli("view", deck, "issues").splitlines():
        m = re.search(r"(/slide\[\d+\]/shape\[@id=\d+\]).*?suggest\.height=([\d.]+)cm", line)
        if not m or m.group(1) not in notes:
            continue
        path, want = m.group(1), float(m.group(2)) * CM
        top = max(notes[path] - want, 0)      # never grow off the slide top
        officecli("set", deck, path, "--prop", f"height={int(want)}emu",
                  "--prop", f"y={int(top)}emu")
        print(f"grew {path} to {want/CM:.1f}cm")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("deck")
    ap.add_argument("slide", help="e.g. '/slide[6]'")
    ap.add_argument("--role", action="append", default=[], metavar="LABEL=#RRGGBB:n1,n2",
                    help="fill these nodes and give the colour a legend entry")
    ap.add_argument("--note", action="append", default=[], metavar="NODE=text",
                    help="unboxed caption above the node (flips below if it would "
                         "leave the slide)")
    ap.add_argument("--legend", choices=("tr", "tl", "br", "bl"),
                    help="draw the --role swatches in that corner")
    ap.add_argument("--note-size", type=int, default=11, help="caption pt")
    ap.add_argument("--note-color", default="#333333")
    args = ap.parse_args()

    if not (args.role or args.note):
        sys.exit("nothing to do — pass --role and/or --note")

    width, height = slide_size(args.deck)
    found = nodes(args.deck, args.slide)
    if not found:
        sys.exit(f"no diagram shapes under {args.slide} — add the diagram first")

    legend, notes = [], {}
    for spec in args.role:
        label, rest = pair(spec, "role")
        if ":" not in rest:
            sys.exit(f"--role wants LABEL=#RRGGBB:node,node — got {spec!r}")
        colour, names = rest.split(":", 1)
        targets = [n.strip() for n in names.split(",") if n.strip()]
        if not targets:
            sys.exit(f"--role {label!r} lists no nodes")
        for name in targets:
            path = resolve(found, name)[0]
            officecli("set", args.deck, path, "--prop", f"fill={colour}")
        legend.append((label, colour))
        print(f"{label}: {len(targets)} node(s) → {colour}")

    for spec in args.note:
        name, text = pair(spec, "note")
        _, x, y, w, h = resolve(found, name)
        nw = w + NOTE_PAD
        nx = min(max(x + w / 2 - nw / 2, 0), width - nw)
        ny = y - NOTE_H - NOTE_GAP
        if ny < 0:                       # no room above — sit under the node
            ny = y + h + NOTE_GAP
        out = add(args.deck, args.slide, "textbox", f"Annotation note {name}",
                  (nx, ny, nw, NOTE_H),
                  "--prop", f"text={text}", "--prop", "fill=none",
                  "--prop", "line=none", "--prop", f"size={args.note_size}pt",
                  "--prop", f"color={args.note_color}", "--prop", "align=center",
                  "--prop", "autoFit=none")
        m = re.search(r"(/slide\[\d+\]/shape\[@id=\d+\])", out)
        if m:
            notes[m.group(1)] = ny + NOTE_H      # bottom edge, to grow upwards
        print(f"note on {name!r} at y={ny/CM:.1f}cm")

    grow_notes(args.deck, notes)

    if args.legend:
        if not legend:
            sys.exit("--legend needs at least one --role to describe")
        sw, sh = SWATCH
        block_w, block_h = sw + 4.2 * CM, ROW * len(legend)
        lx = INSET if args.legend[1] == "l" else width - INSET - block_w
        top_edge = max(INSET, title_bottom(args.deck, args.slide) + 0.4 * CM)
        ly = top_edge if args.legend[0] == "t" else height - INSET - block_h
        for i, (label, colour) in enumerate(legend):
            top = ly + i * ROW
            add(args.deck, args.slide, "shape", f"Annotation legend {label}",
                (lx, top, sw, sh), "--prop", "geometry=roundRect",
                "--prop", f"fill={colour}", "--prop", "line=#7A7A7A",
                "--prop", "lineWidth=0.75pt")
            add(args.deck, args.slide, "textbox", f"Annotation legend {label} label",
                (lx + sw + 0.25 * CM, top - 0.05 * CM, 3.9 * CM, sh + 0.1 * CM),
                "--prop", f"text={label}", "--prop", "fill=none", "--prop", "line=none",
                "--prop", f"size={args.note_size}pt",
                "--prop", f"color={args.note_color}", "--prop", "autoFit=none")
        print(f"legend: {len(legend)} row(s) at {lx/CM:.1f},{ly/CM:.1f}cm")

    officecli("save", args.deck)


if __name__ == "__main__":
    main()
