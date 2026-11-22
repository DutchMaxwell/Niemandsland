#!/usr/bin/env python3
"""gate_rows.py OUT TAG BASE_TAG: the rows of the readability gate.

Reads OUT/<TAG>_y<yaw>_r<n>/manifest.json (the town under test) and OUT/<BASE_TAG>_y<yaw>_r<n>/manifest.json (the plain-table baseline, same instrument and seeds), written by
tools/boardgen/gate_run.sh. The baseline score of every model is the MEDIAN over its repeats; a row is one (preset, seed, yaw) and is the MEDIAN over the repeats of the town of
  - the median of the per-model ratio  after / before   (>= MED_BAR),
  - its 10th percentile                                  (>= P10_BAR),
  - HARD: no visible pawn below score 1 (the absolute floor),
  - HARD: no pawn hidden from all four quarter-turn views (a "pocket"; captures with views=4) but the KNOWN_POCKETS of ticket POCKETS,
    which are printed on every run: a NEW pocket is red.
Gate change 22.11.: every in-frame pawn carries its visible share (pixel masks); one under 0.4 has no score. The share of in-frame pawns at least 0.4
visible from the default view is a SOFT number (board style): printed, `WATCH` under VIS_WATCH, never red. Printed per row: pawns, off-frame, hidden, the old
collider ray's count (comparison only), the visible share, hidden from all views. The base is the plain table: the same capture with `board=none`.
Models whose disc is not wholly inside the 1600 x 900 frame are left out (their ring would read clamped border pixels). Exit status 1 when any row is under a bar.
"""
import glob, json, os, statistics as st, sys

out, tag, base_tag = sys.argv[1:4]
M = 30   # px margin of the frame
P10_BAR, MED_BAR = float(os.environ.get("P10_BAR", "0.60")), float(os.environ.get("MED_BAR", "0.75"))
VIS_WATCH = float(os.environ.get("VIS_WATCH", "0.70"))
# ticket POCKETS (lead 22.11.): legal ground spots no quarter view sees, (seed, cell x, cell z). Main s53 (2, 3): a one-cell street lane between an intact
# house row and a 6 in tier. Tower stage (roofskt/l1-towers) s67 (10, 3): an alley between an intact house and a city-wall buttress; s71 (4, 12): a pit between
# 3 / 6 in tiers and two buttresses. Printed on every run; any other pocket is red.
KNOWN_POCKETS = {("s53", 2, 3), ("s67", 10, 3), ("s71", 4, 12)}


def load(t):
    runs = {}
    for path in sorted(glob.glob(os.path.join(out, t + "_y*_r*", "manifest.json"))):
        for g in json.load(open(path))["gate"]:
            runs.setdefault((g["preset"], g["seed"], g.get("yaw", 0.0)), []).append(g)
    return runs


def in_frame(row):
    return M <= row[2] <= 1600 - M and M <= row[3] <= 900 - M


def scores(g):
    return {r[0]: r[1] for r in g["scores"] if in_frame(r)}


after, base = load(tag), load(base_tag)
ok = True
lines = []
for key in sorted(after, key=lambda k: (k[2], k[0], int(k[1].lstrip("s")))):
    if key not in base:
        continue
    per_model = {}
    for g in base[key]:
        for i, v in scores(g).items():
            per_model.setdefault(i, []).append(v)
    s0 = {i: st.median(v) for i, v in per_model.items()}
    p10s, meds, grows, below = [], [], [], []
    occl = st.median(g.get("occluded", 0) for g in after[key])
    for g in after[key]:
        s1 = scores(g)
        ratios = sorted(s1[i] / s0[i] for i in s0 if s0[i] > 0.05 and i in s1)
        if not ratios:
            continue
        b0 = sum(1 for i, v in s0.items() if v < 1.0 and i in s1)
        b1 = sum(1 for i, v in s1.items() if v < 1.0 and i in s0)
        p10s.append(ratios[len(ratios) // 10]); meds.append(st.median(ratios)); grows.append(b1 - b0); below.append((b0, b1))
    p10, med, grow = st.median(p10s), st.median(meds), st.median(grows)
    vis = [[v[1] for v in g["vis"]] for g in after[key] if "vis" in g]
    seen = st.median(sum(1 for s in v if s >= 0.4) / max(len(v), 1) for v in vis) if vis else 1.0
    cnt = lambda f: st.median(g.get(f, -1) for g in after[key])
    allv = max([st.median(g.get("hidden_all_views", -1) for g in v) for k, v in after.items() if k[:2] == key[:2]])   # the four views of any yaw of this seed
    pk = {(key[1], c[0], c[1]) for k, v in after.items() if k[:2] == key[:2] for g in v for c in g.get("pockets", [])}
    good = p10 >= P10_BAR and med >= MED_BAR and st.median(b[1] for b in below) == 0 and 0 <= allv <= len(pk & KNOWN_POCKETS) and not pk - KNOWN_POCKETS   # -1: no capture of this seed ran views=4: not green
    ok = ok and good
    lines.append("%-6s %-4s yaw %3d | pawns %d off-frame %d hidden %d (ray %d) | visible %.2f%s pockets %d (known %s) | below1 %d -> %d | ratio median %.2f | p10 %.2f n %d [repeats %s] | %s" % (
        key[0], key[1], int(key[2]), cnt("pawns"), cnt("offframe"), occl, cnt("ray"), seen, " WATCH" if seen < VIS_WATCH else "", allv, sorted(pk & KNOWN_POCKETS) or "-",
        below[0][0], st.median(b[1] for b in below), med, p10, len(ratios), " ".join("%.2f" % p for p in p10s), "PASS" if good else "FAIL"))
if not lines:
    ok = False   # no row matched the baseline (other seeds, presets or yaws): a gate that compared nothing is not green
    lines.append("no row of %s matches a row of %s" % (tag, base_tag))
lines.append("GATE " + ("GREEN" if ok else "RED"))
print("\n".join(lines))
open(os.path.join(out, "%s_rows.txt" % tag), "w").write("\n".join(lines) + "\n")
sys.exit(0 if ok else 1)
