#!/usr/bin/env python3
"""Cross-fit b2 gate: member A selects a candidate, member B scores it, a shuffled-value control must fail.

A search leaf needs to rank the searcher's own selection above the incumbent's pick. The two members of the
shipped ensemble (the exported ONNX output [1], read by `tools/lab2_net.ShippedNet.member_values`) let one member
SELECT and the other SCORE, so a within-position ordering signal can be measured OFFLINE, before any paid A/B.
This is a cross-fit b2 gate with a shuffled-value control. It is NOT a strength number: read the shuffle control
even on a PASS, and never quote b2 alone -- a calibration-only proxy has passed offline and still lost the table
A/B, so a PASS here is necessary, not sufficient.

A corpus is a directory of `*.json` decision files, or one JSON file holding a list. Per decision:
    {"game": <cluster id>, "values_a": [...], "values_b": [...], "pick": <int>, "margin": <float>,
     "legal": [bool, ...]?}          # member A/B values per pool row; `pick` = the incumbent's row index
  * `best_a` = argmax of values_a over the LEGAL rows (ties -> lowest index);
  * `gain`   = values_b[best_a] - values_b[pick]     # member B scores A's selection against the incumbent;
  * `event`  = gain > margin                          # A's selection clears the incumbent's own margin.

Verdict: {n_decisions, event_rate, gain_mean, gain_lo95, red_event_rate, red_gain_lo95, pass}. event_rate and the
margin are in the corpus's native value units; gain_mean/gain_lo95/red_gain_lo95 are in POINTS (100 x the value
units, the repo's scoring convention), computed with `lab2_tree_probe.bootstrap_intervals` (game-cluster bootstrap,
Bonferroni K=5 order statistics). RED: per permutation member B's values are shuffled WITHIN each decision; a real
signal must vanish there. PASS iff gain_lo95 > 0 AND event_rate >= 0.20 AND red_gain_lo95 <= 0. Writes
GATE_CROSSFIT_<date>.json.

Identity: without `--members` (fewer than 2) the tool is a no-op (b1-only); no corpus is read.
Run:  python3 tools/crossfit_gate.py --corpus DIR --members 2 [--perms 10] [--resamples 100000] [--out F]
"""
from __future__ import annotations

import argparse
import datetime
import glob
import importlib.util
import json
import os
import random
import statistics

HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("lab2_tree_probe", os.path.join(HERE, "lab2_tree_probe.py"))
_lab = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_lab)

#: the event (A's pick beats the incumbent by more than its own margin) must be common enough to mean anything.
MIN_EVENT_RATE = 0.20


def canon(obj) -> str:
    return json.dumps(obj, sort_keys=True, ensure_ascii=True, allow_nan=True)


def load_corpus(path):
    """A directory of *.json decisions, or one JSON file holding a list; each item is normalized to the schema."""
    if os.path.isdir(path):
        items = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(path, "*.json")))]
    else:
        data = json.load(open(path))
        items = data if isinstance(data, list) else [data]
    out = []
    for i, d in enumerate(items):
        va, vb = d.get("values_a"), d.get("values_b")
        if not va or len(va) != len(vb or []):
            raise SystemExit("decision %d: values_a/values_b missing or of unequal length" % i)
        legal = d.get("legal")
        legal = [True] * len(va) if legal is None else [bool(x) for x in legal]
        if len(legal) != len(va):
            raise SystemExit("decision %d: legal has %d entries, values_a has %d" % (i, len(legal), len(va)))
        out.append({"game": d.get("game", i), "values_a": [float(x) for x in va], "values_b": [float(x) for x in vb],
                    "pick": int(d.get("pick", 0)), "margin": float(d.get("margin", 0.0)), "legal": legal})
    return out


def best_a(d) -> int:
    """Member A's pick: the highest values_a among the legal rows (ties -> lowest index); `pick` if none legal."""
    legal = d.get("legal")
    legal = [True] * len(d["values_a"]) if legal is None else legal
    rows = [i for i, ok in enumerate(legal) if ok]
    return max(rows, key=lambda i: d["values_a"][i]) if rows else d["pick"]


def decision_gain(d, values_b) -> float:
    """Member B's gain of A's selection over the incumbent pick (native value units)."""
    return values_b[best_a(d)] - values_b[d["pick"]]


def gains_by_game(decisions, per_decision_gain):
    """bootstrap_intervals' input: one cell, one cluster per game, the game's mean gain as the contrast value."""
    by = {}
    for d, g in zip(decisions, per_decision_gain):
        by.setdefault(str(d["game"]), []).append(g)
    return {"c1": {g: {"gain": statistics.fmean(v)} for g, v in by.items()}}


def interval(decisions, per_decision_gain, resamples, seed):
    return _lab.bootstrap_intervals(gains_by_game(decisions, per_decision_gain), resamples, seed)["gain"]


def gate(decisions, perms=10, resamples=100_000, seed=0):
    """The cross-fit verdict. `perms` shuffled-B permutations drive the RED control."""
    n = len(decisions)
    if n == 0:
        return {"n_decisions": 0, "event_rate": 0.0, "gain_mean": 0.0, "gain_lo95": 0.0, "red_event_rate": 0.0,
                "red_gain_lo95": 0.0, "perms": 0, "pass": False}
    gains = [decision_gain(d, d["values_b"]) for d in decisions]
    events = [g > d["margin"] for g, d in zip(gains, decisions)]
    real = interval(decisions, gains, resamples, seed)
    red_rates, red_los = [], []
    for p in range(max(perms, 1)):
        rng = random.Random((seed + 1) * 1_000_003 + p)
        shuffled = []
        for d in decisions:
            vb = list(d["values_b"])
            rng.shuffle(vb)
            shuffled.append(vb)
        rg = [decision_gain(d, vb) for d, vb in zip(decisions, shuffled)]
        red_rates.append(statistics.fmean([g > d["margin"] for g, d in zip(rg, decisions)]))
        red_los.append(interval(decisions, rg, resamples, seed + 1 + p)["lo95"])
    event_rate = statistics.fmean(events)
    red_gain_lo95 = statistics.fmean(red_los)
    v = {"n_decisions": n, "event_rate": event_rate, "gain_mean": real["point"], "gain_lo95": real["lo95"],
         "red_event_rate": statistics.fmean(red_rates), "red_gain_lo95": red_gain_lo95, "perms": max(perms, 1)}
    v["pass"] = bool(v["gain_lo95"] > 0 and event_rate >= MIN_EVENT_RATE and red_gain_lo95 <= 0)
    return v


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--corpus", required=True, help="a dir of *.json decisions, or one JSON file holding a list")
    ap.add_argument("--members", type=int, default=1, help="ensemble members needed for a cross-fit (>=2 run, else no-op)")
    ap.add_argument("--perms", type=int, default=10, help="shuffled-B RED permutations")
    ap.add_argument("--resamples", type=int, default=100_000)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default="", help="default GATE_CROSSFIT_<date>.json")
    a = ap.parse_args(argv)
    if a.members < 2:
        print("[crossfit] no --members (b1-only): nothing to cross-fit, no-op")
        return 0
    verdict = gate(load_corpus(a.corpus), a.perms, a.resamples, a.seed)
    out = a.out or ("GATE_CROSSFIT_%s.json" % datetime.date.today().isoformat())
    with open(out, "w") as fh:
        json.dump(verdict, fh, indent=1, sort_keys=True)
    print("[crossfit] " + canon(verdict))
    return 0 if verdict["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
