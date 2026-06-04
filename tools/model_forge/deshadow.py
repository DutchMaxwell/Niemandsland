#!/usr/bin/env python3
"""Remove the soft contact shadow (and any off-white background) from a miniature render.

The image model bakes a grey contact/drop shadow under the figure as part of its "product shot"
style; TRELLIS then reconstructs that shadow as a flat disc base. The shadow is light grey
(~220-245) sitting on white and is CONNECTED to the white background, while the figure is a
separate, much darker island (boots ~80-150). So a flood-fill from the borders whitens background
+ shadow and stops at the figure — deterministic, no model, no geometry surgery.

Usage:  deshadow.py <in.png> <out.png> [white_thresh=205]
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw


def deshadow(src: Path, dst: Path, white_thresh: int = 205) -> dict:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    # Flood-fill background+shadow to pure white from all four corners. `thresh` is the max
    # per-channel distance from the seed colour that is still flooded; 255-white_thresh lets the
    # fill cross white -> light-grey shadow but stop at the darker figure.
    seed_thresh = 255 - white_thresh
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(im, seed, (255, 255, 255), thresh=seed_thresh)

    # Any remaining near-neutral light-grey that the flood missed (isolated shadow pockets not
    # touching a corner-connected region) -> white, but only if it is bright AND low-saturation
    # (so coloured/teal/bright-metal highlights on the figure are preserved).
    px = im.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            mn, mx = min(r, g, b), max(r, g, b)
            if mn >= white_thresh and (mx - mn) <= 12:  # bright + nearly neutral
                px[x, y] = (255, 255, 255)

    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst)
    return {"src": str(src), "dst": str(dst), "size": im.size}


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: deshadow.py <in.png> <out.png> [white_thresh]")
        raise SystemExit(1)
    thr = int(sys.argv[3]) if len(sys.argv) > 3 else 205
    print(deshadow(Path(sys.argv[1]), Path(sys.argv[2]), thr))
