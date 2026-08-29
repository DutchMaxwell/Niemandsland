"""NML-1147 — THE STAGE CENSUS: per act, WHICH stage of the twin's search first
parts from the recorded trace.

The pick census (NML-1146) counts first-pick divergences and buckets the unit
flips by margin. This tool opens the trace itself: recorded vs twin, the FIRST
diverging stage of `plan_with_rollout`'s pipeline — prefilter length, prefilter
index set, prefilter score drift, rank order (the tie-break chain's own
signature), pool order, rollout rs drift, argmax. Its PERMANENT zero-gates are
the order-stage invariants `rank_order=0, pool=0, argmax=0`: the tie-break
chain (sort score DESC / idx ASC, pool coverage->top-K, strict first-wins
argmax) is ported at parity, and any nonzero there means a REGRESSION, not a
finding.

Measured on qbg_ref (30.08.): rank_order/pool/argmax all 0; the drift lives
earlier — prefilter 1-ply scores on ~15% of acts (MOVE+HOLD rows only) and the
rollout blend rs on ~24% — both material (>=1e-3), both entering at candidate
RESOLVE. That anatomy is this wave's target (see the 30.08. wave section).

    ~/venvs/nmloutcome/bin/python core/nml-core-py/tools/pick_stage_census.py \
        --ref ~/selfplay_out/qbg_ref --jobs 10
"""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
from charge_gate import acts_of  # noqa: E402
from outcome_gate import pick_class, pick_key  # noqa: E402
from shoot_replay_gate import resolve_vintage_flag  # noqa: E402

#: The order-stage zero-gates, in report order. Any nonzero is a regression.
ZERO_GATES = ("rank_order", "pool", "argmax")


def _idx_map(rows, key: str) -> dict[int, float]:
    return {int(r["idx"]): float(r[key]) for r in (rows or [])}


def stage_diff(rec: dict, twin: dict) -> list:
    """The FIRST diverging stage between the recorded and the twin trace.
    Returns a list whose head is the stage name and whose tail carries drift
    magnitudes: `["prefilter_score_drift", max_abs_drift]`,
    `["rs_drift", max_abs_drift, n_bad_rows]`. Empty list = stages identical."""
    a_sc, b_sc = rec.get("scored") or [], twin.get("scored") or []
    if len(a_sc) != len(b_sc):
        return ["prefilter_len"]
    a, b = _idx_map(a_sc, "score"), _idx_map(b_sc, "score")
    if set(a) != set(b):
        return ["prefilter_idxset"]
    if any(a[i] != b[i] for i in a):
        return ["prefilter_score_drift", max(abs(a[i] - b[i]) for i in a)]
    if [int(r["idx"]) for r in a_sc] != [int(r["idx"]) for r in b_sc]:
        return ["rank_order"]
    if [int(x) for x in (rec.get("pool_idx") or [])] != \
       [int(x) for x in (twin.get("pool_idx") or [])]:
        return ["pool"]
    a_rs, b_rs = _idx_map(rec.get("rs"), "rs"), _idx_map(twin.get("rs"), "rs")
    if set(a_rs) != set(b_rs):
        return ["rs_idxset"]
    bad = [i for i in a_rs if a_rs[i] != b_rs[i]]
    if bad:
        return ["rs_drift", max(abs(a_rs[i] - b_rs[i]) for i in bad), len(bad)]
    if int(rec.get("best_idx", -1)) != int(twin.get("best_idx", -1)):
        return ["argmax"]
    return []


def census_one(job: tuple) -> dict:
    """One game, per-act stage diff. Runs in a worker; plain data only."""
    name, ref, repo, red = job
    head, lines = acts_of(Path(ref) / name / "acts.jsonl")
    eff = resolve_vintage_flag("auto", head, repo, "engage_fold")
    eff_ap = resolve_vintage_flag("auto", head, repo, "cond_ap")
    nml_core.set_legacy_no_cond_ap(not eff_ap)
    core = nml_core.load(repo)
    core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                     "knobs": dict(head.get("knobs", {}),
                                   engage_fold=(not eff) if red else eff)})
    out = {"name": name, "considered": 0, "agreed": 0, "declined": 0,
           "stages": [], "agree_clean": 0, "agree_drift": 0}
    for act in lines:
        rec = act.get("pick") or {}
        if not act.get("trace") or not rec.get("used"):
            continue
        out["considered"] += 1
        twin = core.plan_with_rollout(core.state_of(act["state"]),
                                      int(act["player"]), act["statics"])
        if not twin.get("used"):
            out["declined"] += 1
            continue
        why = pick_class(pick_key(int(act["player"]), rec.get("action")),
                         pick_key(int(act["player"]), twin.get("action")))
        rt, tt = act["trace"], twin["trace"]
        sd = stage_diff(rt, tt)
        if why == "none":
            out["agreed"] += 1
            if sd:
                out["agree_drift"] += 1
            else:
                out["agree_clean"] += 1
        out["stages"].append((why + ":" + (sd[0] if sd else "clean"),
                              sd[1:] if len(sd) > 1 else None))
    return out


def report(label: str, ref: Path, rows: list, secs: float, jobs: int) -> int:
    cons = sum(r["considered"] for r in rows)
    agree = sum(r["agreed"] for r in rows)
    clean = sum(r["agree_clean"] for r in rows)
    drifted = sum(r["agree_drift"] for r in rows)
    stages: dict[str, list] = {}
    for r in rows:
        for k, extra in r["stages"]:
            stages.setdefault(k, [0, []])
            stages[k][0] += 1
            if extra and len(stages[k][1]) < 6:
                stages[k][1].append(extra)
    gate_bad = sum(v[0] for k, v in stages.items() if k in ZERO_GATES)
    print()
    print("%s over %d games of %s (%.1fs wall, %d workers)"
          % (label, len(rows), ref.name, secs, jobs))
    print("  PICKS  : %d considered, %d agreed (%.1f%%), %d declined"
          % (cons, agree, 100.0 * agree / max(cons, 1), sum(r["declined"] for r in rows)))
    print("  AGREE  : %d stage-clean, %d agreed-with-drift (the drift the pick survived)"
          % (clean, drifted))
    for k in sorted(stages, key=lambda k: -stages[k][0]):
        v = stages[k]
        extra = ""
        vals = [e for e in v[1] if isinstance(e, list) and e]
        if vals:
            extra = "  max_drift~%.2e" % max(e[0] for e in vals)
        print("  %-24s %5d%s" % (k, v[0], extra))
    print("  ZERO-GATES: %s" % ("held (all 0)" if gate_bad == 0
                                else "FAILED, %d order-stage divergences" % gate_bad))
    return 0 if gate_bad == 0 else 1


def run(ref: Path, repo: str, limit: int, jobs: int, red: bool) -> int:
    games = sorted(d.name for d in ref.iterdir()
                   if d.is_dir() and (d / "acts.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no acts.jsonl under %s" % ref)
        return 1
    jobs = max(1, min(jobs, len(games)))
    jobargs = [(g, str(ref), repo, red) for g in games]
    t0 = time.perf_counter()
    with mp.get_context("spawn").Pool(jobs) as pool:
        rows = pool.map(census_one, jobargs)
    rc = report("STAGE CENSUS" + (" + RED --red-vintage" if red else ""),
                ref, rows, time.perf_counter() - t0, jobs)
    return rc


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of recorded arena game dirs")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--jobs", type=int, default=10, help="worker processes (spawn)")
    ap.add_argument("--red-vintage", action="store_true",
                    help="RED PROOF: replay every act with engage_fold inverted; the "
                         "order-stage zero-gates still hold, agreement must drop")
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.repo, a.limit, a.jobs, a.red_vintage)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
