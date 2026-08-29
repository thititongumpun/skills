"""Shared officecli plumbing for the mermaid-diagram helpers in this folder.

Imported by flow-motion.py and annotate.py — both need to find a native
diagram's nodes by their text and read back real slide coordinates.
"""
import re
import subprocess
import sys

UNITS = {"emu": 1, "cm": 360000, "pt": 12700, "in": 914400}
CM = 360000


def emu(value):
    m = re.match(r"^(-?[\d.]+)(emu|cm|pt|in)$", value or "")
    return float(m.group(1)) * UNITS[m.group(2)] if m else None


def officecli(*args):
    r = subprocess.run(("officecli",) + args, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"officecli {' '.join(args)}\n{r.stderr.strip() or r.stdout.strip()}")
    return r.stdout


def slide_size(deck):
    m = re.search(r"slideWidth=(\S+) slideHeight=(\S+)",
                  officecli("get", deck, "/", "--depth", "0"))
    return emu(m.group(1)), emu(m.group(2))


def nodes(deck, slide):
    """{node text: (path, x, y, width, height)} for one slide's diagram shapes.

    Diagram groups are synthesized with childOffset == offset, so the children
    already carry slide coordinates — unlike a hand-built group."""
    out = officecli("query", deck, "shape", "--compact",
                    "--fields", "x,y,width,height")
    found = {}
    for line in out.splitlines():
        col = line.split("\t")
        if len(col) < 7 or not col[0].startswith(slide + "/group["):
            continue
        box = [emu(v.split("=", 1)[1]) for v in col[3:7]]
        if any(v is None for v in box):
            continue
        found[col[2].strip('"')] = (col[0], *box)
    return found


def resolve(found, name):
    """Match a node by case-insensitive substring, insisting on exactly one."""
    hits = [k for k in found if name.lower() in k.lower()]
    if not hits:
        sys.exit(f"no diagram node matching {name!r}. Found: {sorted(found)}")
    if len(hits) > 1:
        sys.exit(f"{name!r} matches {hits} — use a longer, unique fragment")
    return found[hits[0]]


def centre(box):
    _, x, y, w, h = box
    return x + w / 2, y + h / 2


def title_bottom(deck, slide):
    """Bottom edge of the slide's title placeholder, or 0 if it has none.

    A legend dropped in a top corner lands on the title otherwise — the
    'Title and Content' layout's title runs to y=4.66cm."""
    for line in officecli("get", deck, slide, "--depth", "1").splitlines():
        if "isTitle=true" not in line:
            continue
        m = re.search(r" y=(\S+) width=\S+ height=(\S+)", line)
        if m and emu(m.group(1)) is not None and emu(m.group(2)) is not None:
            return emu(m.group(1)) + emu(m.group(2))
    return 0
