"""GATE S4 (position-solver ladder) — the PLAIN MOVE, model by model, against
the table's own — the CHARGE gate's twin (`charge_move_gate.py`) for the
NON-CHARGE moves: every recorded `allow_contact: false` `moves_calls.jsonl`
line, i.e. an ADVANCE or a RUSH (`AiDecision.Action` ai_decision.gd:16 — HOLD
and CHARGE are D5-2's and D5-3's rungs, not this one's).

THREE BARS, same meaning as the charge gate: END (every model's endpoint
within 0.05"), CALL (the `plan_unit_step` input the port built vs the one the
table recorded, first differing field named), BUDGET (the granted band vs the
port's own `budget_in`).

THE LADDER. A charge never enters `_execute_move`'s stall escalation, gate-
collapse ladder or boxed/sidestep escape (`not allow_contact` excludes it from
all three — step.rs:13-19); a plain move DOES, and `mv::step::plain_move`
does not port them (step.rs:654-658) — only the p.11 difficult-cap re-plan is
shared. So one activation can carry SEVERAL recorded plan_unit_step calls, one
per collapse round, each at a smaller `reach_in`; the port makes exactly one
(two if the p.11 cap fires). The RECORDED call held against the port's own is
therefore the one whose `reach_in` equals the port's `budget_in` — the round
the un-collapsed port's own decision corresponds to — not the ladder's last
(smallest) round, which only the un-ported escalation ever reaches. BUDGET
counts whether ANY recorded round matches; when none does, END/CALL still run
against the closest one (the ladder's last round) so a real miss stays visible
rather than silently dropped, but it is not scored as a budget pass.

THE TRIM. The recorder writes the PLAN call (input + the planner's OWN
`planned` endpoints), not `_execute_move`'s later distance-truth trim
(step.rs:477-490 — a model whose ROUTED trail runs longer than the granted
band is trimmed back to it). `plain_move` returns the trimmed `end`, so a
model recorded with a trail already longer than the port's own `budget_in`
was always going to move on to a different final resting point than its
recorded `planned` — that is not a miss, it is the recording predating the
trim. Such models are excused from END as "trimmed", counted separately.

THE RED. `--red-shift` moves every RECORDED endpoint 0.06" and changes
nothing else, same as the charge gate's.

PER-MODEL (S12). END already fails an act the moment ONE model of the unit
misses the bar (`gap` is the WORST model's own gap) — PER-MODEL is that same
fold, reported on its own line as the ladder's closing target: the share of
acts where EVERY model lands within 0.05", plus a histogram of the worst-
model gap (`GAP_BUCKETS`) and a breakdown by how many models the acting unit
carries. `--red-shift` reddens it exactly the way it reddens END, because
both read the same `score_end` output.

`--final` (S5a, #519) scores the gate on the NEXT recorded act's own
positions instead of the pre-gate `planned` field — a separate tool landing
from that PR, not this one. PER-MODEL's `GAP_BUCKETS`/`SIZE_GROUPS`
histogram is built so it can be pointed at that FINAL reading too once both
are in; wiring it there is a follow-up, not done in this file.

    PYTHONPATH=<module> python core/nml-core-py/tools/move_call_gate.py \\
        --ref ~/selfplay_out/qbg_ref --limit 3
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

import nml_core  # noqa: E402
from charge_move_gate import BAR_IN, call_diff  # noqa: E402
from melee_replay_gate import IN2M, header_walls_m  # noqa: E402
from shoot_replay_gate import (  # noqa: E402
    read_game, resolve_vintage_flag, vintage_report_line,
)

#: `AiDecision.Action` ai_decision.gd:16 — the two kinds this gate scores.
ADVANCE_KIND = 1
RUSH_KIND = 2
#: `OVERLAP_EPS_M` step.rs:47, in inches — the distance-truth trim's own
#: slack, so a trail exactly AT the budget is not flagged as trimmed.
TRIM_SLACK_IN = 0.0005 / IN2M

#: S12's worst-model-gap histogram for the PER-MODEL line. Order matters:
#: `gap_bucket` returns the FIRST one a gap qualifies for.
GAP_BUCKETS = ("le_bar", "le_0_5in", "le_2in", "le_6in", "gt_6in")

#: S12's per-model-count breakdown for the PER-MODEL line.
SIZE_GROUPS = ("1", "2-5", "6+")


def gap_bucket(gap_in: float) -> str:
    """Which `GAP_BUCKETS` slot one worst-model gap (inches) falls into."""
    if gap_in <= BAR_IN:
        return "le_bar"
    if gap_in <= 0.5:
        return "le_0_5in"
    if gap_in <= 2.0:
        return "le_2in"
    if gap_in <= 6.0:
        return "le_6in"
    return "gt_6in"


def size_group(n_models: int) -> str:
    """Which `SIZE_GROUPS` slot one acting unit's model count falls into."""
    if n_models <= 1:
        return "1"
    if n_models <= 5:
        return "2-5"
    return "6+"


def call_reach_in(c: dict) -> float:
    """The granted band off one recorded call's `rung` line."""
    return float(c["rung"].split("reach_in=")[1].split()[0])


def trail_len_in(pts: list) -> float:
    """One recorded model's ROUTED trail length, inches — the same quantity
    `_execute_move`'s distance truth (step.rs:483) trims against."""
    return sum(((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5 for a, b in zip(pts, pts[1:]))


def score_end(got_end: list, want_planned: list, want_trails: list | None,
              budget_in: float, red_shift: bool = False) -> tuple[float, int, int, int]:
    """One act's per-model END comparison, `got_end`/`want_planned` already in
    the SAME inch frame and the SAME length. `red_shift` moves every recorded
    endpoint 0.06" (the RED proof). A model whose recorded trail already ran
    longer than `budget_in` is excused as "trimmed" rather than scored (the
    distance-truth trim, see the module docstring) — never scored AND never
    counted toward the worst gap.

    Returns `(worst_gap_in, models_equal, models_scored, models_trimmed)`.
    """
    trails = want_trails or []
    worst, equal, scored, trimmed = 0.0, 0, 0, 0
    for i, (g, w) in enumerate(zip(got_end, want_planned)):
        if i < len(trails) and trail_len_in(trails[i]) > budget_in + TRIM_SLACK_IN:
            trimmed += 1
            continue
        gap = max(abs(g[0] - (w[0] + (0.06 if red_shift else 0.0))),
                   abs(g[1] - (w[1] + (0.06 if red_shift else 0.0))))
        worst = max(worst, gap)
        scored += 1
        if gap <= BAR_IN:
            equal += 1
    return worst, equal, scored, trimmed


def run(ref: Path, repo: str, limit: int, red_shift: bool, report_only: bool,
        engage_fold: str = "auto", cond_ap: str = "auto") -> int:
    games = sorted(d for d in ref.iterdir()
                   if d.is_dir() and (d / "moves_calls.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no moves_calls.jsonl under %s" % ref)
        return 1

    t = {k: 0 for k in ("acts", "no_call", "declined", "end_equal", "call_equal", "budget_equal",
                        "models", "models_equal", "models_trimmed", "acts_all_trimmed")}
    # S12 PER-MODEL — the same END fold, reported on its own with a histogram
    # of the worst-model gap and a breakdown by the acting unit's model count.
    per_model = dict.fromkeys(("acts", "equal") + GAP_BUCKETS, 0)
    groups = {g: {"acts": 0, "equal": 0} for g in SIZE_GROUPS}
    worst = 0.0
    reasons: dict[str, int] = {}
    firsts: list[str] = []
    vintage_seen: set[tuple[bool, bool]] = set()
    t0 = time.perf_counter()
    print(nml_core.__file__)

    for d in games:
        head, lines, dice, seed = read_game(d)
        with open(d / "moves_calls.jsonl", encoding="utf-8") as f:
            mh = json.loads(f.readline())
            calls = [json.loads(x) for x in f if x.strip()]
        board = mh.get("board_in") or [0.0, 0.0]
        half = [board[0] * 0.5, board[1] * 0.5]
        walls, _src = header_walls_m(d, head)
        core = nml_core.load(repo)
        eff_engage_fold = resolve_vintage_flag(engage_fold, head, repo, "engage_fold")
        eff_cond_ap = resolve_vintage_flag(cond_ap, head, repo, "cond_ap")
        vintage_seen.add((eff_engage_fold, eff_cond_ap))
        nml_core.set_legacy_no_cond_ap(not eff_cond_ap)
        core.set_header({"profiles": head["profiles"],
                         "terrain": dict(head.get("terrain") or {}, walls=walls)
                         if head.get("terrain") else None,
                         "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                       charge_landing=True, movement=True,
                                       engage_fold=eff_engage_fold)})
        for act in lines:
            k = int(act["act"])
            a = (act.get("pick") or {}).get("action") or {}
            kind = int(a.get("kind", -1))
            if kind not in (ADVANCE_KIND, RUSH_KIND) or "dest" not in a:
                continue
            rec = [c for c in calls if int(c["act"]) == k and not c.get("allow_contact")]
            if not rec:
                # The table ran no non-charge plan call under this ordinal at
                # all (a zero band, or the caller short-circuited) — no
                # landing to compare here.
                t["no_call"] += 1
                continue
            t["acts"] += 1
            state = core.state_of(act["state"])
            bands = state.move_bands(a["unit"])
            if bands is None:
                t["declined"] += 1
                continue
            got = core.plain_move(state, a["unit"], a["dest"],
                                   bands[0] if kind == ADVANCE_KIND else bands[1])
            if got is None:
                t["declined"] += 1
                reasons["declined"] = reasons.get("declined", 0) + 1
                continue
            matches = [c for c in rec if abs(call_reach_in(c) - got["budget_in"]) <= 0.001]
            if matches:
                t["budget_equal"] += 1
            else:
                reasons["budget"] = reasons.get("budget", 0) + 1
            want = matches[-1] if matches else rec[-1]
            why = call_diff(got.get("call") or {},
                            dict(want, walls=(mh.get("walls") or [])
                                 if want.get("walls") == "header" else want.get("walls")))
            if not why:
                t["call_equal"] += 1
            else:
                reasons[why.split(":")[0]] = reasons.get(why.split(":")[0], 0) + 1
            end = [[(p[0] / IN2M) + half[0], (p[2] / IN2M) + half[1]] for p in got["end"]]
            pl = want.get("planned") or []
            if len(pl) != len(end):
                reasons["planned:len"] = reasons.get("planned:len", 0) + 1
                if len(firsts) < 3:
                    firsts.append("%s act %d [len] %d endpoints vs the table's %d"
                                  % (d.name, k, len(end), len(pl)))
                continue
            gap, eq, scored, trimmed = score_end(end, pl, want.get("trails"),
                                                 got["budget_in"], red_shift)
            t["models_trimmed"] += trimmed
            t["models"] += scored
            t["models_equal"] += eq
            if scored == 0:
                t["acts_all_trimmed"] += 1
                continue
            worst = max(worst, gap)
            if gap <= BAR_IN:
                t["end_equal"] += 1
            else:
                reasons["end"] = reasons.get("end", 0) + 1
                if len(firsts) < 3:
                    firsts.append("%s act %d [end] worst model %.3f\" off%s"
                                  % (d.name, k, gap, (" — call: " + why) if why else ""))

            # S12 PER-MODEL — the SAME fold (`gap` is already the worst model's
            # own gap), reported on its own with a histogram and a breakdown by
            # how many models the acting unit carries.
            per_model["acts"] += 1
            per_model[gap_bucket(gap)] += 1
            if gap <= BAR_IN:
                per_model["equal"] += 1
            grp = size_group(len(pl))
            groups[grp]["acts"] += 1
            if gap <= BAR_IN:
                groups[grp]["equal"] += 1

    end_acts = t["acts"] - t["acts_all_trimmed"]
    label = "GATE S4 plain move"
    if red_shift:
        label = "RED S4 --red-shift (every recorded endpoint moved 0.06\")"
    print()
    print("%s over %d games, %d ADVANCE/RUSH acts with a recorded plan call, %s (%.1fs)"
          % (label, len(games), t["acts"], vintage_report_line(vintage_seen),
             time.perf_counter() - t0))
    print("  END   : %d/%d acts (%d excused, every model's trail already over budget) land "
          "every scored model within %.2f\"" % (t["end_equal"], end_acts, t["acts_all_trimmed"], BAR_IN))
    print("        : %d/%d individual models within the bar; %d trimmed models excused; worst act %.4f\""
          % (t["models_equal"], t["models"], t["models_trimmed"], worst))
    print("  CALL  : %d/%d acts build the plan_unit_step call the table recorded"
          % (t["call_equal"], t["acts"]))
    print("  BUDGET: %d/%d acts grant a band the recorded ladder actually tried"
          % (t["budget_equal"], t["acts"]))
    print("  aside : %d acts ran NO non-charge plan call on the table; %d declined"
          % (t["no_call"], t["declined"]))
    print("  first field to part: %s"
          % (", ".join("%s=%d" % kv for kv in sorted(reasons.items())) or "none"))
    for f in firsts:
        print("  first : %s" % f)
    print("  PER-MODEL: %d/%d acts put EVERY model of the acting unit within %.2f\" (S12's "
          "closing target)" % (per_model["equal"], per_model["acts"], BAR_IN))
    print("           : worst-model-gap buckets: %s"
          % ", ".join("%s=%d" % (b, per_model[b]) for b in GAP_BUCKETS))
    print("           : by unit size — %s"
          % ", ".join("%s models %d/%d" % (g, groups[g]["equal"], groups[g]["acts"])
                       for g in SIZE_GROUPS))

    if red_shift:
        ok = t["end_equal"] < end_acts and per_model["equal"] < per_model["acts"]
        print("  RED %s" % ("held — %d of %d acts part on END, %d of %d on PER-MODEL"
                            % (end_acts - t["end_equal"], end_acts,
                               per_model["acts"] - per_model["equal"], per_model["acts"])
                            if ok else "FAILED — every act survived the damage"))
        return 0 if ok else 1
    ok = t["acts"] > 0 and t["end_equal"] == end_acts and t["call_equal"] == t["acts"]
    if report_only:
        print("  REPORT ONLY — %d/%d acts short, exit 0 by request" % (end_acts - t["end_equal"], end_acts))
        return 0
    print("  %s" % ("PASS" if ok else
                    "FAIL — %d of %d acts do not land where the table landed"
                    % (end_acts - t["end_equal"], end_acts)))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of arena game dirs")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--red-shift", action="store_true",
                    help="RED PROOF: move every RECORDED endpoint 0.06\" — one hundredth past "
                         "the bar — and nothing else; the RED must part")
    ap.add_argument("--report-only", action="store_true",
                    help="exit 0 even when acts are short (this tool is a GATE by default)")
    ap.add_argument("--engage-fold", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: the header knob engage_fold (PR #446). 'auto' (default) "
                         "reads the corpus's OWN vintage; 'on'/'off' force it")
    ap.add_argument("--cond-ap", choices=("auto", "on", "off"), default="auto",
                    help="NML-1130: conditional AP. 'auto' (default) reads the corpus's OWN "
                         "vintage; 'on'/'off' force it")
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.repo, a.limit, a.red_shift, a.report_only,
               a.engage_fold, a.cond_ap)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
