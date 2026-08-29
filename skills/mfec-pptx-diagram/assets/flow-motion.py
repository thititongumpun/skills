#!/usr/bin/env python3
"""Animate a data packet travelling between nodes of a native mermaid diagram.

    python3 flow-motion.py deck.pptx '/slide[6]' Producer Kafka Consumer

Adds one marker shape at the first node and one motion-path leg per hop, each
triggered after the previous one. Node names are matched against the diagram
shapes' text (case-insensitive substring).

Why a script: PowerPoint refuses to animate shapes inside a group, so the
marker has to be a top-level shape, and each leg's path is expressed as a
slide-width fraction measured from the marker's ORIGINAL position — cumulative,
not per-hop. Both are easy to get wrong by hand.
"""
import argparse
import re
import sys

from _diagram import centre, nodes, officecli, resolve, slide_size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("deck")
    ap.add_argument("slide", help="e.g. '/slide[6]'")
    ap.add_argument("stops", nargs="+", help="node texts, in travel order")
    ap.add_argument("--size", type=float, default=0.9, help="marker Ø in cm")
    ap.add_argument("--fill", default="#FF6B00")
    ap.add_argument("--duration", type=int, default=1200, help="ms per hop")
    ap.add_argument("--loop", action="store_true",
                    help="repeat the whole run indefinitely")
    args = ap.parse_args()

    if len(args.stops) < 2:
        sys.exit("need at least two stops")

    width, height = slide_size(args.deck)
    found = nodes(args.deck, args.slide)
    points = [centre(resolve(found, s)) for s in args.stops]

    d = args.size * 360000
    x0, y0 = points[0]
    out = officecli("add", args.deck, args.slide, "--type", "shape",
                    "--prop", "geometry=ellipse",
                    "--prop", f"x={int(x0 - d / 2)}emu",
                    "--prop", f"y={int(y0 - d / 2)}emu",
                    "--prop", f"width={int(d)}emu",
                    "--prop", f"height={int(d)}emu",
                    "--prop", f"fill={args.fill}", "--prop", "line=none")
    marker = re.search(r"(/slide\[\d+\]/shape\[@id=\d+\])", out)
    if not marker:
        sys.exit(f"could not read the marker's path back from: {out.strip()}")
    marker = marker.group(1)

    # Each leg is measured from the marker's ORIGINAL position (animMotion is
    # written with origin="layout"), so offsets accumulate along the route.
    for i, (px, py) in enumerate(points[1:], 1):
        legs = [f"{(p[0] - x0) / width:.4f} {(p[1] - y0) / height:.4f}"
                for p in (points[i - 1], (px, py))]
        props = ["--prop", "class=motion", "--prop", "path=custom",
                 "--prop", f"d=M {legs[0]} L {legs[1]} E",
                 "--prop", "trigger=afterPrevious",
                 "--prop", f"duration={args.duration}"]
        if args.loop:
            props += ["--prop", "repeat=indefinite"]
        officecli("add", args.deck, marker, "--type", "animation", *props)

    officecli("save", args.deck)
    print(f"{marker}: {len(points) - 1} hop(s) "
          f"{' -> '.join(args.stops)}")


if __name__ == "__main__":
    main()
