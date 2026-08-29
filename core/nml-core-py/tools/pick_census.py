"""NML-1146 — THE PICK CENSUS: per act, what does the twin pick where the table
picked something else, and how close was the call?

The outcome gate (D0) counts first-pick divergences and names the FIELD that
parted — `unit` dominates, and there the count stops. This tool turns that
number into a CAUSE: on every act whose recorded pick is a real planner pick
(`trace` present, `pick.used`), it seats the twin on the act's own recorded
state, lets `plan_with_rollout` pick for itself, and compares in
`outcome_gate`'s pick vocabulary. Where the field that parted is `unit`, it
records the recorded call's MARGIN — `expectation.after` minus the recorded
runner-up's `score` — whether the twin landed on that recorded runner-up (a
ONE-STEP SWAP is a tie signature: the same two candidates, the other order),
and the twin's own margin between its pick and its runner-up.

The buckets: `<1e-3` is a TIE the deterministic tie-break could own; `<1e-2`
and `<5e-2` are playout-noise territory; `>=5e-2` is the twin scoring the
position materially differently — the eval-content port's signature. Near-ties
point at the tie-break rung, big margins at the eval rung; that verdict, not a
count, is this tool's output.

`--red-vintage` replays every act a second time on the corpus's engage_fold
INVERTED (NML-1130) and demands STRICTLY LESS agreement. Agreement that does
not drop when the plan knobs are wrong would mean the census is measuring
something that does not listen to them.

    ~/venvs/nmloutcome/bin/python core/nml-core-py/tools/pick_census.py \
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
from shoot_replay_gate import (  # noqa: E402
    resolve_vintage_flag, vintage_report_line,
)

#: The margin buckets, in ascending order. A `None` (no runner-up on either
#: side) is reported as its own "none", never folded into "<1e-3".
BUCKETS = ("<1e-3", "<1e-2", "<5e-2", ">=5e-2")


def margin_bucket(m: float | None) -> str:
    """One margin into its bucket; `None` stays `None`."""
    if m is None:
        return "none"
    if m < 1e-3:
        return "<1e-3"
    if m < 1e-2:
        return "<1e-2"
    if m < 5e-2:
        return "<5e-2"
    return ">=5e-2"


def _margin(pick: dict) -> float | None:
    """`expectation.after` minus the runner-up's `score` — how close the call
    was. `None` when the pick carries no runner-up to subtract."""
    r = pick.get("runner_up") or {}
    e = pick.get("expectation") or {}
    if not r or not e:
        return None
    return float(e.get("after", 0.0)) - float(r.get("score", 0.0))


def flip_row(rec: dict, twin: dict) -> dict:
    """One UNIT-flip's anatomy: the recorded margin, whether the twin picked the
    recorded runner-up (one-step swap), and the twin's own margin."""
    return {"rec": margin_bucket(_margin(rec)),
            "swap": bool(rec.get("runner_up"))
                    and twin.get("unit_key") == rec["runner_up"].get("unit_key"),
            "twin": margin_bucket(_margin(twin))}


def red_holds(green: int, red: int) -> bool:
    """`--red-vintage`'s bar: the wrong vintage must agree STRICTLY less."""
    return red < green


def census_one(job: tuple) -> dict:
    """One game, both arms. Runs in a worker process; everything it returns is
    plain data, because a `State` does not cross a pipe."""
    name, ref, repo, red = job
    head, lines = acts_of(Path(ref) / name / "acts.jsonl")
    eff = resolve_vintage_flag("auto", head, repo, "engage_fold")
    eff_ap = resolve_vintage_flag("auto", head, repo, "cond_ap")
    nml_core.set_legacy_no_cond_ap(not eff_ap)
    core = nml_core.load(repo)
    arms = {"green": eff}
    if red:
        arms["red"] = not eff
    out: dict = {"name": name, "vintage": (eff, eff_ap), "arms": {}}
    for label, arm in arms.items():
        core.set_header({"profiles": head["profiles"], "terrain": head.get("terrain"),
                         "knobs": dict(head.get("knobs", {}), engage_fold=arm)})
        row = {"considered": 0, "agreed": 0, "declined": 0, "why": [], "flips": []}
        for act in lines:
            rec = act.get("pick") or {}
            if not act.get("trace") or not rec.get("used"):
                continue
            row["considered"] += 1
            twin = core.plan_with_rollout(core.state_of(act["state"]),
                                          int(act["player"]), act["statics"])
            if not twin.get("used"):
                row["declined"] += 1
                continue
            why = pick_class(pick_key(int(act["player"]), rec.get("action")),
                             pick_key(int(act["player"]), twin.get("action")))
            if why == "none":
                row["agreed"] += 1
            else:
                row["why"].append(why)
                if why == "unit":
                    row["flips"].append(flip_row(rec, twin))
        out["arms"][label] = row
    return out


def hist(values, keys) -> str:
    """One histogram line, in the given key order, zeros dropped."""
    c = {k: 0 for k in keys}
    for v in values:
        c[v] = c.get(v, 0) + 1
    return "  ".join("%s=%d" % (k, c[k]) for k in c if c[k])


def report(label: str, ref: Path, rows: list, secs: float, jobs: int) -> int:
    def arm(label: str) -> dict:
        return {"c": sum(r["arms"].get(label, {}).get("considered", 0) for r in rows),
                "a": sum(r["arms"].get(label, {}).get("agreed", 0) for r in rows),
                "d": sum(r["arms"].get(label, {}).get("declined", 0) for r in rows),
                "why": [], "flips": []}
    g, rd = arm("green"), arm("red")
    for r in rows:
        for tgt, lbl in ((g, "green"), (rd, "red")):
            if lbl not in r["arms"]:
                continue
            for k in r["arms"][lbl]["why"]:
                tgt["why"].append(k)
            tgt["flips"] += r["arms"][lbl]["flips"]
    n = max(g["c"], 1)
    print()
    print("%s over %d games of %s (%.1fs wall, %d workers) — vintage %s"
          % (label, len(rows), ref.name, secs, jobs,
             vintage_report_line({r["vintage"] for r in rows})))
    print("  PICKS  : %d considered, %d agreed (%.1f%%), %d declined by the twin"
          % (g["c"], g["a"], 100.0 * g["a"] / n, g["d"]))
    print("  div why: %s" % hist(g["why"], ("seat", "unit", "kind", "target", "length")))
    fl = g["flips"]
    print("  unit   : %d flips — recorded margin %s" % (len(fl), hist(
        [f["rec"] for f in fl], BUCKETS + ("none",))))
    print("           one-step swap (twin picked the recorded runner-up) %d/%d; "
          "twin's own margin %s" % (sum(1 for f in fl if f["swap"]), len(fl),
                                    hist([f["twin"] for f in fl], BUCKETS + ("none",))))
    rc = 0
    if rd["c"]:
        print("  RED vintage: %d/%d agreed (%.1f%%) — %s"
              % (rd["a"], rd["c"], 100.0 * rd["a"] / max(rd["c"], 1),
                 "held" if red_holds(g["a"], rd["a"]) else
                 "FAILED, the wrong vintage did not agree strictly less"))
        rc = 0 if red_holds(g["a"], rd["a"]) else 1
    return rc


def run(ref: Path, repo: str, limit: int, jobs: int, red: bool, out: Path) -> int:
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
    secs = time.perf_counter() - t0
    rc = report("PICK CENSUS" + (" + RED --red-vintage" if red else ""),
                ref, rows, secs, jobs)
    out.mkdir(parents=True, exist_ok=True)
    (out / "census.json").write_text(json.dumps(rows, indent=1))
    (out / "CENSUS_DONE").write_text("green agreed %d, red %d\n"
                                     % (sum(r["arms"]["green"]["agreed"] for r in rows),
                                        sum(r["arms"].get("red", {}).get("agreed", 0)
                                            for r in rows)))
    print("  wrote   : %s" % out)
    return rc


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of recorded arena game dirs")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--jobs", type=int, default=10, help="worker processes (spawn)")
    ap.add_argument("--red-vintage", action="store_true",
                    help="RED PROOF: replay every act with engage_fold inverted; "
                         "agreement must drop STRICTLY")
    ap.add_argument("--out", default=str(Path.home() / "selfplay_out/pick_census"))
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.repo, a.limit, a.jobs, a.red_vintage,
               Path(a.out).expanduser())


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
