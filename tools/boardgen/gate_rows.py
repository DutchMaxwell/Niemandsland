#!/usr/bin/env python3
"""gate_rows.py OUT TAG BASE_TAG: the rows of the readability gate.

Reads OUT/<TAG>_y<yaw>_r<n>/manifest.json (the town under test) and OUT/<BASE_TAG>_y<yaw>_r<n>/manifest.json (the plain-table baseline, same instrument and seeds), written by
tools/boardgen/gate_run.sh. The baseline score of every model is the MEDIAN over its repeats; a row is one (preset, seed, yaw) and is the MEDIAN over the repeats of the town of
  - the median of the per-model ratio  after / before   (>= 0.9),
  - its 10th percentile                                  (>= 0.7: the bar),
  - the growth of the number of models below score 1     (<= 4).
Models whose disc is not wholly inside the 1600 x 900 frame are left out (their ring would read clamped border pixels). Exit status 1 when any row is under a bar.
"""
import glob, json, os, statistics as st, sys

out, tag, base_tag = sys.argv[1:4]
M = 30   # px margin of the frame


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
    for g in after[key]:
        s1 = scores(g)
        ratios = sorted(s1[i] / s0[i] for i in s0 if s0[i] > 0.05 and i in s1)
        if not ratios:
            continue
        b0 = sum(1 for i, v in s0.items() if v < 1.0 and i in s1)
        b1 = sum(1 for i, v in s1.items() if v < 1.0 and i in s0)
        p10s.append(ratios[len(ratios) // 10]); meds.append(st.median(ratios)); grows.append(b1 - b0); below.append((b0, b1))
    p10, med, grow = st.median(p10s), st.median(meds), st.median(grows)
    good = p10 >= 0.7 and med >= 0.9 and grow <= 4
    ok = ok and good
    lines.append("%-6s %-4s yaw %3d | below1 %d -> %d | ratio median %.2f | p10 %.2f [repeats %s] | %s" % (
        key[0], key[1], int(key[2]), below[0][0], st.median(b[1] for b in below), med, p10, " ".join("%.2f" % p for p in p10s), "PASS" if good else "FAIL"))
lines.append("GATE " + ("GREEN" if ok else "RED"))
print("\n".join(lines))
open(os.path.join(out, "%s_rows.txt" % tag), "w").write("\n".join(lines) + "\n")
sys.exit(0 if ok else 1)
