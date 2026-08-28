#!/usr/bin/env python
"""NML-1073 M5 D8a — the objective-layout gate.

The twin must place objective markers exactly where the TABLE places them for the
same seed, and every layout either side produces must satisfy the rulebook. Three
checks, two of them against a GDScript-produced oracle:

(a) FIXTURE   `nml_core.objective_layout` versus `ObjectiveLayout.generate` run in
              the real engine (tools/objective_fixture.gd writes 50 layout seeds x
              3 missions on one pinned board). Count, first placer, placer order,
              sweep count and every marker position, exact — the positions are
              integer inches, so "within 0.05 in" is satisfied by equality and the
              gate reports the worst gap it actually saw.
(b) LEGALITY  every layout in (a) and (c), re-checked against the book independently
              of the generator that produced it: each marker over 9" from every
              OTHER marker, outside both deployment zones, off an impassable cell,
              inside the edge margin. A self-test, so a generator that drifted into
              placing illegal markers cannot pass by agreeing with itself.
(c) REPLAY    every act header in a corpus that carries an `objectives` stamp:
              re-derive the layout from the stamped INPUTS (layout seed + count
              spec) and that header's own board, and compare with the stamped
              positions. This is what makes the stamp a re-derivable record rather
              than a number to be trusted.

RED knobs (each must turn its own check red):
  --red-shift=N   move the twin's first marker N inches. (a) and (c) go red, (b)
                  stays green unless the shift also breaks a rule.
  --red-zone      grow both deployment zones 6" toward the centre before the
                  legality test. Markers the generator legally placed just outside
                  the real line are then INSIDE a zone, so (b) goes red — which is
                  what proves the zone half of the legality test bites at all.
                  (a) stays green: the two sides still agree, they are just both
                  measured against a rule that is not the game's.

Run:
  ~/venvs/nmld8a/bin/python core/nml-core-py/tools/objective_gate.py \
      --fixture core/nml-core/tests/fixtures/objective_layout.json \
      --corpus ~/selfplay_out/d8a_ref
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import sys

import nml_core

#: The harnesses deploy FRONT_LINE 12" zones — assets/solo/deployments.json.
FRONT_LINE_ZONES = {
    "zones": {
        "1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
        "2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]],
    }
}
#: `--red-zone`: the same style with each zone's inner edge pushed 6" toward the
#: centre. Nothing plays this — it exists to make the zone check fail on demand.
RED_ZONES = {
    "zones": {
        "1": [[[-36, -24], [36, -24], [36, -6], [-36, -6]]],
        "2": [[[-36, 6], [36, 6], [36, 24], [-36, 24]]],
    }
}
MARKER_GAP_IN = 9
EDGE_MARGIN_IN = 3
POSITION_TOL_IN = 0.05
CELL_IN = 3.0
CONTAINER = 3


def _cell_map(terrain):
    """The header/bank `terrain` object as {(cx, cz): type} plus the grid width, the
    way `SchoolTerrain.cell_of` indexes it.

    `n` is taken off `nml_core.board(...)`, NOT re-derived here: the grid is a SQUARE
    sized by `map_layout._calculate_grid_dimensions` (30 cells for a 6x4ft table, not
    the 24 a naive width/3 gives), and the first version of this gate got that wrong
    and reported four legal forest markers as sitting on impassable ground."""
    cells = {}
    for c in (terrain or {}).get("cells", []):
        cells[(int(c[0]), int(c[1]))] = int(c[2])
    return cells, nml_core.board(terrain).n()


def _in_poly(px, pz, poly):
    """The integer even-odd test of objective_layout.gd / objectives.rs — a point ON
    the boundary counts as INSIDE."""
    m = len(poly)
    inside = False
    for i in range(m):
        ax, az = int(poly[i][0]), int(poly[i][1])
        bx, bz = int(poly[(i + m - 1) % m][0]), int(poly[(i + m - 1) % m][1])
        if (bx - ax) * (pz - az) - (bz - az) * (px - ax) == 0 and (
            min(ax, bx) <= px <= max(ax, bx) and min(az, bz) <= pz <= max(az, bz)
        ):
            return True
        if (az > pz) != (bz > pz):
            d = bz - az
            lhs, rhs = (px - ax) * d, (pz - az) * (bx - ax)
            if (d > 0 and lhs < rhs) or (d < 0 and lhs > rhs):
                inside = not inside
    return inside


def legality_faults(positions, zones, cells, n, label):
    """Every way `positions` breaks the book, as a list of human-readable strings.
    Written HERE rather than called out of the port on purpose: a self-test that
    reuses the code under test proves only self-consistency."""
    faults = []
    polys = []
    for pk in ("1", "2"):
        for poly in (zones.get("zones", {}) or {}).get(pk, []) or []:
            polys.append(poly)
    for i, (x, z) in enumerate(positions):
        for j, (qx, qz) in enumerate(positions):
            if i >= j:
                continue
            gap = math.hypot(x - qx, z - qz)
            if gap <= MARKER_GAP_IN:
                faults.append("%s: markers %d,%d only %.3f\" apart" % (label, i, j, gap))
        for poly in polys:
            if _in_poly(int(x), int(z), poly):
                faults.append("%s: marker %d (%d,%d) inside a deployment zone" % (label, i, x, z))
                break
        if abs(x) > 36 - EDGE_MARGIN_IN or abs(z) > 24 - EDGE_MARGIN_IN:
            faults.append("%s: marker %d (%d,%d) inside the edge margin" % (label, i, x, z))
        cx = math.floor(x / CELL_IN + n / 2.0)
        cz = math.floor(z / CELL_IN + n / 2.0)
        if cells.get((int(cx), int(cz)), 0) == CONTAINER:
            faults.append("%s: marker %d (%d,%d) on an impassable cell" % (label, i, x, z))
    return faults


def _worst_gap(a, b):
    return max((max(abs(p[0] - q[0]), abs(p[1] - q[1])) for p, q in zip(a, b)), default=0.0)


def check_fixture(path, red_shift, red_zone):
    fx = json.load(open(path))
    terrain = {
        "cells": fx["cells"],
        "sandbox": [],
        "walls": [],
        "cell_params": {
            "table_size_feet": [fx["table_w_in"] / 12.0, fx["table_d_in"] / 12.0],
            "grid_rotation_degrees": 0.0,
            "grid_size_inches": CELL_IN,
            "inches_to_meters": 0.0254,
        },
    }
    zones = {"zones": fx["zones"]}
    cells, n = _cell_map(terrain)
    ok = bad = 0
    worst = 0.0
    faults = []
    for c in fx["cases"]:
        lay = nml_core.objective_layout(
            terrain, c["layout_seed"], c["count_spec"], zones, fx["table_w_in"], fx["table_d_in"]
        )
        got = [list(p) for p in lay["positions"]]
        if red_shift and got:
            got[0][0] += red_shift
        want = [list(p) for p in c["layout"]["positions"]]
        label = "%s seed %d" % (c["mission"], c["layout_seed"])
        same = (
            lay["count_roll"] == c["layout"]["count_roll"]
            and lay["first_placer"] == c["layout"]["first_placer"]
            and lay["placed_by"] == c["layout"]["placed_by"]
            and lay["swept"] == c["layout"]["swept"]
            and len(got) == len(want)
            and _worst_gap(got, want) <= POSITION_TOL_IN
        )
        if same:
            ok += 1
            worst = max(worst, _worst_gap(got, want))
        else:
            bad += 1
            if bad <= 3:
                faults.append("%s: table %s vs twin %s" % (label, want, got))
        faults += legality_faults(
            want, RED_ZONES if red_zone else zones, cells, n, "TABLE " + label
        )
    return ok, bad, worst, faults


def check_corpus(root, red_shift, red_zone):
    ok = bad = 0
    skipped = 0
    worst = 0.0
    faults = []
    for acts in sorted(glob.glob(os.path.join(root, "*", "acts.jsonl"))) + sorted(
        glob.glob(os.path.join(root, "acts.jsonl"))
    ):
        with open(acts) as f:
            head = json.loads(f.readline())
        stamp = head.get("objectives")
        if not stamp:
            skipped += 1
            continue
        terrain = head.get("terrain")
        cells, n = _cell_map(terrain)
        lay = nml_core.objective_layout(
            terrain, int(stamp["layout_seed"]), "d3+2", FRONT_LINE_ZONES
        )
        got = [list(p) for p in lay["positions"]]
        if red_shift and got:
            got[0][0] += red_shift
        want = [list(p) for p in stamp["positions"]]
        label = os.path.basename(os.path.dirname(acts))
        if (
            lay["count_roll"] == stamp["count_roll"]
            and lay["first_placer"] == stamp["first_placer"]
            and len(got) == len(want)
            and _worst_gap(got, want) <= POSITION_TOL_IN
        ):
            ok += 1
            worst = max(worst, _worst_gap(got, want))
        else:
            bad += 1
            faults.append("%s: stamped %s vs re-derived %s" % (label, want, got))
        faults += legality_faults(
            want, RED_ZONES if red_zone else FRONT_LINE_ZONES, cells, n, "STAMP " + label
        )
    return ok, bad, skipped, worst, faults


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fixture", default="")
    ap.add_argument("--corpus", default="")
    ap.add_argument("--red-shift", type=int, default=0)
    ap.add_argument("--red-zone", action="store_true")
    a = ap.parse_args()
    if not a.fixture and not a.corpus:
        ap.error("give --fixture and/or --corpus")
    rc = 0
    all_faults = []
    if a.fixture:
        ok, bad, worst, faults = check_fixture(a.fixture, a.red_shift, a.red_zone)
        print(
            "(a) FIXTURE  twin vs table: %d/%d identical, worst gap %.4f\" (tol %.2f\")"
            % (ok, ok + bad, worst, POSITION_TOL_IN)
        )
        all_faults += faults
        rc |= 1 if bad else 0
    if a.corpus:
        ok, bad, skipped, worst, faults = check_corpus(a.corpus, a.red_shift, a.red_zone)
        print(
            "(c) REPLAY   re-derived vs stamped: %d/%d identical, worst gap %.4f\", "
            "%d header(s) without a stamp" % (ok, ok + bad, worst, skipped)
        )
        all_faults += faults
        rc |= 1 if bad else 0
        rc |= 1 if ok + bad == 0 else 0
    print("(b) LEGALITY %d fault(s)" % len(all_faults))
    for f in all_faults[:20]:
        print("    " + f)
    rc |= 1 if all_faults else 0
    print("GATE " + ("GREEN" if rc == 0 else "RED"))
    return rc


if __name__ == "__main__":
    sys.exit(main())
