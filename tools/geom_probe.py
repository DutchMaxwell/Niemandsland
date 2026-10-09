#!/usr/bin/env python3
"""Per-landing geometry signature probe over a recorded candidate-geometry corpus.

The judge sees the post-move state only; the candidate landing geometry is dropped. This tool asks whether the
landing geometry differs between the candidates of one decision: it computes a terrain-relative SIGNATURE per
recorded destination and counts distinct signatures per decision. The signature is a step function of the landing,
never the raw coordinate, so two open-ground cells 1 inch apart match while a cover edge 1 inch flips it:
    (kind, cover, difficult, dangerous)
Terrain is rebuilt from the recorded `terr` token rows (sandbox OBBs only -- the 3-inch base grid is not in the
token, so cover here is a lower bound). Landings are the recorded destinations (0-origin table inches); the dest-less
HOLD fallback and off-board rows are dropped. Shards missing the geom columns are skipped. Known limits: the first
containing OBB wins on overlap, and the OBB edge is inclusive.

Run:  python3 tools/geom_probe.py --corpus DIR [--limit N] [--out F]
"""
from __future__ import annotations

import argparse
import datetime
import glob
import json
import math
import os
import statistics
from collections import namedtuple

NONE, RUINS, FOREST, CONTAINER, DANGEROUS = 0, 1, 2, 3, 4
HOLD = 0  # sim::HOLD; the dest-less menu fallback sits at the actor's own centre
BOARD_IN = (72.0, 48.0)
FLAT_RS_TOL = 0.0019
GEOM_KEYS = ("side", "terr_ptr", "terr", "geom_ptr", "geom_kind", "geom_cell", "geom_x_in", "geom_y_in", "geom_rs")

Obb = namedtuple("Obb", "cx cy hw hh yaw kind")  # one sandbox terrain piece, centred table inches and radians


def gives_cover(kind):
    return kind in (RUINS, FOREST)


def is_difficult(kind):
    return kind == FOREST


def is_dangerous(kind):
    return kind == DANGEROUS


def point_in_obb(px, py, obb):
    """The point in the OBB's own frame (inverse yaw), inclusive of the edge."""
    dx, dy = px - obb.cx, py - obb.cy
    c, s = math.cos(-obb.yaw), math.sin(-obb.yaw)
    rx, ry = dx * c - dy * s, dx * s + dy * c
    return abs(rx) <= obb.hw and abs(ry) <= obb.hh


def kind_at(px, py, terrain):
    for obb in terrain:
        if point_in_obb(px, py, obb):
            return obb.kind
    return NONE


def signature(px, py, terrain):
    """The terrain-relative landing signature: a step function of the landing, not of the raw coordinate."""
    kind = kind_at(px, py, terrain)
    return (kind, int(gives_cover(kind)), int(is_difficult(kind)), int(is_dangerous(kind)))


def decode_terrain(terr_rows, side):
    """Rebuild the sandbox OBBs from the `terr` token rows, un-mirroring by the recorded side."""
    sgn = -1.0 if side == 2 else 1.0
    out = []
    for r in terr_rows:
        kind = RUINS if r[6] else FOREST if r[7] else CONTAINER if r[8] else DANGEROUS if r[9] else NONE
        out.append(Obb(sgn * float(r[0]) * 30.0, sgn * float(r[1]) * 30.0, float(r[2]) * 12.0, float(r[3]) * 12.0,
                       math.atan2(float(r[5]), float(r[4])), kind))
    return out


def decision_rows(z, d):
    """(terrain, landings) for decision `d`: sandbox OBBs plus the real destinations, centred world inches."""
    side = int(z["side"][d])
    terrain = decode_terrain(z["terr"][int(z["terr_ptr"][d]):int(z["terr_ptr"][d + 1])], side)
    landings = []
    for i in range(int(z["geom_ptr"][d]), int(z["geom_ptr"][d + 1])):
        if int(z["geom_cell"][i]) < 0 or int(z["geom_kind"][i]) == HOLD:
            continue
        landings.append((float(z["geom_x_in"][i]) - BOARD_IN[0] / 2.0, float(z["geom_y_in"][i]) - BOARD_IN[1] / 2.0,
                         float(z["geom_rs"][i])))
    return terrain, landings


def iter_npz(corpus):
    return sorted(glob.glob(os.path.join(corpus, "**", "*.npz"), recursive=True)) if os.path.isdir(corpus) else [corpus]


def probe(corpus, limit=0):
    """Distinct-signature stats: per decision, how many landings share a signature."""
    import numpy as np
    per_decision, flat_rs, n_landings, n_shards, n_skipped = [], [], 0, 0, 0
    for path in iter_npz(corpus):
        if limit and n_shards >= limit:
            break
        n_shards += 1
        z = np.load(path, allow_pickle=True)
        if any(k not in z for k in GEOM_KEYS):
            n_skipped += 1
            continue
        for d in range(len(z["side"])):
            terrain, landings = decision_rows(z, d)
            sigs = [signature(x, y, terrain) for (x, y, _rs) in landings]
            if not sigs:
                continue
            n_landings += len(sigs)
            per_decision.append(len(set(sigs)))
            rs = [rs for (_x, _y, rs) in landings if not math.isnan(rs)]
            if len(rs) >= 2 and max(rs) - min(rs) < FLAT_RS_TOL:
                flat_rs.append(len(set(sigs)))
    if not per_decision:
        return {"n_shards": n_shards, "n_shards_skipped": n_skipped, "n_decisions": 0, "n_landings": n_landings,
                "distinct_median": 0.0, "distinct_mean": 0.0, "single_signature_share": 0.0, "flat_rs_decisions": 0,
                "flat_rs_distinct_median": 0.0, "flat_rs_distinct_mean": 0.0}
    return {"n_shards": n_shards, "n_shards_skipped": n_skipped, "n_decisions": len(per_decision),
            "n_landings": n_landings, "distinct_median": float(statistics.median(per_decision)),
            "distinct_mean": float(statistics.fmean(per_decision)),
            "single_signature_share": float(statistics.fmean([c == 1 for c in per_decision])),
            "flat_rs_decisions": len(flat_rs),
            "flat_rs_distinct_median": float(statistics.median(flat_rs)) if flat_rs else 0.0,
            "flat_rs_distinct_mean": float(statistics.fmean(flat_rs)) if flat_rs else 0.0}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--corpus", required=True, help="a dir tree of *.npz decision shards, or one .npz file")
    ap.add_argument("--limit", type=int, default=0, help="stop after N shards (0 = all)")
    ap.add_argument("--out", default="", help="default GATE_GEOM_<date>.json")
    a = ap.parse_args(argv)
    verdict = probe(a.corpus, a.limit)
    with open(a.out or ("GATE_GEOM_%s.json" % datetime.date.today().isoformat()), "w") as fh:
        json.dump(verdict, fh, indent=1, sort_keys=True)
    print("[geom_probe] " + json.dumps(verdict, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
