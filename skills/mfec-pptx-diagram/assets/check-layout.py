#!/usr/bin/env python3
"""Geometry check for an MFEC deck: nothing off the slide, no diagram sitting
on top of slide text.

    python3 check-layout.py deck.pptx      # exit 1 if anything is wrong

Complements `officecli view <deck> issues`, which catches text overflowing its
own shape but sees neither shapes leaving the slide nor shapes colliding.
"""
import itertools
import re
import subprocess
import sys

UNITS = {"emu": 1, "cm": 360000, "pt": 12700, "in": 914400}
CM = 360000
SLOP = 1000          # ~0.003 cm — ignore rounding noise, not real overflow
MIN_OVERLAP = 0.10   # fraction of the smaller box before it counts


def emu(value):
    m = re.match(r"^(-?[\d.]+)(emu|cm|pt|in)$", value or "")
    return float(m.group(1)) * UNITS[m.group(2)] if m else None


def officecli(*args):
    return subprocess.run(("officecli",) + args,
                          capture_output=True, text=True).stdout


def slide_size(deck):
    m = re.search(r"slideWidth=(\S+) slideHeight=(\S+)",
                  officecli("get", deck, "/", "--depth", "0"))
    return (emu(m.group(1)), emu(m.group(2))) if m else (12192000, 6858000)


def elements(deck):
    """Top-level slide children. Group children are skipped on purpose: they
    live in the group's own coordinate space (childOffset/childExtent) and
    cannot be compared against slide coordinates."""
    out = officecli("query", deck,
                    "shape, group, picture, table, connector, chart",
                    "--compact", "--fields", "name,x,y,width,height")
    for line in out.splitlines():
        col = line.split("\t")
        if len(col) < 8 or re.search(r"/group\[[^\]]*\]/", col[0]):
            continue
        path, label, text = col[0], col[1].strip("[]"), col[2]
        props = dict(p.split("=", 1) for p in col[3:8])
        if not props.get("x"):      # groups report no geometry through query
            head = officecli("get", deck, path).splitlines()[0]
            m = re.search(r"x=(\S+) y=(\S+) width=(\S+) height=(\S+)", head)
            if not m:
                continue
            props.update(zip(("x", "y", "width", "height"), m.groups()))
        box = [emu(props[k]) for k in ("x", "y", "width", "height")]
        if any(v is None for v in box):
            continue
        yield path, label, props.get("name", ""), text, box


def main(deck):
    width, height = slide_size(deck)
    els = list(elements(deck))
    problems = []

    for path, _, _, text, (x, y, w, h) in els:
        if x < -SLOP or y < -SLOP or x + w > width + SLOP or y + h > height + SLOP:
            problems.append(
                f"OFF-SLIDE  {path} {text[:40]!r} "
                f"box={x/CM:.1f},{y/CM:.1f} to {(x+w)/CM:.1f},{(y+h)/CM:.1f}cm "
                f"slide={width/CM:.1f}x{height/CM:.1f}cm")

    # Only diagrams/pictures are checked for collisions: template decoration
    # legitimately sits behind text, and flagging it would bury the real hits.
    def is_diagram(e):
        return e[1] in ("picture", "chart") or e[2].startswith("Diagram")

    def is_text(e):
        return e[3] not in ("(empty)", "")

    for a, b in itertools.combinations(els, 2):
        if a[0].split("/")[1] != b[0].split("/")[1]:        # different slides
            continue
        if not (is_diagram(a) and (is_text(b) or is_diagram(b))
                or is_diagram(b) and is_text(a)):
            continue
        ax, ay, aw, ah = a[4]
        bx, by, bw, bh = b[4]
        ox = min(ax + aw, bx + bw) - max(ax, bx)
        oy = min(ay + ah, by + bh) - max(ay, by)
        if ox <= 0 or oy <= 0:
            continue
        frac = (ox * oy) / min(aw * ah, bw * bh)
        if frac >= MIN_OVERLAP:
            problems.append(
                f"OVERLAP    {a[0]} {(a[2] or a[3])[:25]!r} over "
                f"{b[0]} {(b[2] or b[3])[:25]!r} ({frac:.0%} of the smaller)")

    print("\n".join(problems) if problems else "layout ok")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
