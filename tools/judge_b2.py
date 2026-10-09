#!/usr/bin/env python3
"""Offline b2 harness: judge (member A, the selector) vs leaf (member B, the scorer), with a shuffled-JUDGE control.

A new candidate selector -- the judge -- is only useful if the hand leaf can see the value of the cell the judge
picks. This is the same cross-fit b2 shape as `tools/crossfit_gate.py` (member A selects over the LEGAL rows, member
B scores the pick against the incumbent), but the RED control is different: `crossfit_gate` shuffles the LEAF,
whereas a judge must prove its *selection* carries signal, so here the JUDGE's values (member A) are permuted
WITHIN each decision. A real judge's advantage must vanish when its own ranking is destroyed; a corpus where the
judge cannot be shuffled (all judge values tied) leaves the control non-null and must FAIL.

A corpus is a directory of `*.json` decision files, or one JSON file holding a list. Per decision:
    {"game": <cluster id>, "values_a": [...], "values_b": [...], "pick": <int>, "margin": <float>,
     "legal": [bool, ...]?}    # values_a = JUDGE per pool row, values_b = LEAF; `pick` = the incumbent's row index
  * `best_a` = argmax of the JUDGE values over the LEGAL rows (ties -> lowest index);
  * `gain`   = leaf[best_a] - leaf[pick]   # the leaf scores the judge's selection against the incumbent;
  * `event`  = gain > margin.

Verdict: {n_decisions, event_rate, gain_mean, gain_lo95, judge_shuffle_event_rate, judge_shuffle_lo95, perms, pass}.
event_rate and the margin are in the corpus's native value units; gain_mean/gain_lo95 and judge_shuffle_lo95 are in
POINTS (100 x the value units, the repo's scoring convention), computed with `lab2_tree_probe.bootstrap_intervals`
(game-cluster bootstrap, Bonferroni K=5 order statistics). PASS iff gain_lo95 > 0 AND event_rate >= 0.20 AND
judge_shuffle_lo95 <= 0. Writes GATE_JUDGE_B2_<date>.json.

Identity: without `--members` (fewer than 2) there is no judge to test (b1-only) and the tool is a no-op; no corpus
is read. This is a necessary, not sufficient, gate -- read the shuffle control even on a PASS.

Run:  python3 tools/judge_b2.py --corpus DIR --members 2 [--perms 10] [--resamples 100000] [--out F]
"""
from __future__ import annotations

import argparse
import datetime
import importlib.util
import json
import os
import random
import statistics

HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("crossfit_gate", os.path.join(HERE, "crossfit_gate.py"))
cf = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(cf)


def judge_shuffle_gains(decisions, rng):
    """RED control: permute the JUDGE's values (member A) WITHIN each decision; the leaf still scores the pick."""
    out = []
    for d in decisions:
        va = list(d["values_a"])
        rng.shuffle(va)
        out.append(cf.decision_gain(dict(d, values_a=va), d["values_b"]))
    return out


def gate(decisions, perms=10, resamples=100_000, seed=0):
    """The judge verdict. `perms` shuffled-JUDGE permutations drive the RED control."""
    n = len(decisions)
    if n == 0:
        return {"n_decisions": 0, "event_rate": 0.0, "gain_mean": 0.0, "gain_lo95": 0.0,
                "judge_shuffle_event_rate": 0.0, "judge_shuffle_lo95": 0.0, "perms": 0, "pass": False}
    gains = [cf.decision_gain(d, d["values_b"]) for d in decisions]
    events = [g > d["margin"] for g, d in zip(gains, decisions)]
    real = cf.interval(decisions, gains, resamples, seed)
    red_rates, red_los = [], []
    for p in range(max(perms, 1)):
        rng = random.Random((seed + 1) * 1_000_003 + p)
        rg = judge_shuffle_gains(decisions, rng)
        red_rates.append(statistics.fmean([g > d["margin"] for g, d in zip(rg, decisions)]))
        red_los.append(cf.interval(decisions, rg, resamples, seed + 1 + p)["lo95"])
    event_rate = statistics.fmean(events)
    judge_shuffle_lo95 = statistics.fmean(red_los)
    v = {"n_decisions": n, "event_rate": event_rate, "gain_mean": real["point"], "gain_lo95": real["lo95"],
         "judge_shuffle_event_rate": statistics.fmean(red_rates), "judge_shuffle_lo95": judge_shuffle_lo95,
         "perms": max(perms, 1)}
    v["pass"] = bool(v["gain_lo95"] > 0 and event_rate >= cf.MIN_EVENT_RATE and judge_shuffle_lo95 <= 0)
    return v


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--corpus", required=True, help="a dir of *.json decisions, or one JSON file holding a list")
    ap.add_argument("--members", type=int, default=1, help="judge+leaf members needed (>=2 run, else no-op)")
    ap.add_argument("--perms", type=int, default=10, help="shuffled-judge RED permutations")
    ap.add_argument("--resamples", type=int, default=100_000)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--out", default="", help="default GATE_JUDGE_B2_<date>.json")
    a = ap.parse_args(argv)
    if a.members < 2:
        print("[judge_b2] no --members (b1-only): no judge to test, no-op")
        return 0
    verdict = gate(cf.load_corpus(a.corpus), a.perms, a.resamples, a.seed)
    out = a.out or ("GATE_JUDGE_B2_%s.json" % datetime.date.today().isoformat())
    with open(out, "w") as fh:
        json.dump(verdict, fh, indent=1, sort_keys=True)
    print("[judge_b2] " + cf.canon(verdict))
    return 0 if verdict["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
