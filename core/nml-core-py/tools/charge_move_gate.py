"""GATE D5-2 (NML-1073 M5) — the CHARGE MOVE, model by model, against the table's own.

WHAT IS BEING GATED, and why it is sharper than the melee gate. `melee_replay_gate`
scores a charge through the DICE it did or did not draw, so a landing error and an
engage-gate error look the same from outside. This tool asks the one question the
rung is actually about: given the state the table had, does the fast core put every
model of the charging unit where the table put it?

The table's answer is recorded. `scripts/solo/move_recorder.gd` writes one
`moves_calls.jsonl` line per `MovementPlanner.plan_unit_step` call with its full
input AND its returned `planned` array, stamped with the same `move_act_seq` the
act corpus uses. A charge call is the one with `allow_contact: true`. So for every
recorded CHARGE activation there is a per-model endpoint list to hold the port's
own landing against, in the planner's 0-origin INCH frame.

THREE BARS:

  END    — every model's endpoint within 0.05" of the recorded one (the base
           contact epsilon, `SeparationChecker.BASE_CONTACT_EPSILON_INCHES`), and
           the same number of models. This is the gate.
  CALL   — the `plan_unit_step` INPUT the port built from the `State` against the
           one the table recorded: the model positions, the rigid delta, the walls,
           and the size of every opts list. A landing can only be right by accident
           if the call is wrong, so the call is checked separately and its first
           differing field is named.
  BUDGET — the granted band (`reach_in` off the recorded rung line) against the
           port's own `budget_in`, which is where the p.11 difficult cap shows up.

WALLS. The act header's `terrain` block carries `walls` since rung D5-2a (#436),
in WORLD METRES;
`moves_calls.jsonl` has carried the same segments since M4-0a but in BOARD-LOCAL
INCHES. This tool feeds the act-header contract and prints what the port made of
it back in inches, so the two frames are proven against each other rather than
assumed (`--walls-check`, and it is on by default here).

THE RED. `--red-shift` moves every RECORDED endpoint by 0.06" — one hundredth past
the bar — and changes nothing else. Every act must part, which proves the
comparison is measuring endpoints at the stated tolerance and not waving them
through. `--red-no-walls` is the substantive one: plan the same charges on a board
with no wall segments at all and watch the routes that had to bend miss.

    PYTHONPATH=<module> python core/nml-core-py/tools/charge_move_gate.py \\
        --ref ~/selfplay_out/qbf_ref --limit 3
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
from melee_replay_gate import IN2M, header_walls_m  # noqa: E402
from shoot_replay_gate import read_game  # noqa: E402

#: `BattleSim.CHARGE`.
CHARGE_KIND = 3
#: `SeparationChecker.BASE_CONTACT_EPSILON_INCHES` — the endpoint bar.
BAR_IN = 0.05


def call_diff(got: dict, want: dict) -> str:
    """The FIRST field of the built `plan_unit_step` call that differs from the
    recorded one, or "" when they agree.

    `board_in`/`board_y_in` are compared with slack, not exactly: the port derives
    the board from `cell_params.table_size_feet * 12` (72.0) while the recorder
    wrote `half_extent * 2 / INCHES_TO_METERS` (71.99999854) — the same table
    through two arithmetic paths, 1.5e-6" apart, and neither number can move a
    cell index or a route.
    """
    gm, wm = got.get("model_pos") or [], want.get("model_pos") or []
    if len(gm) != len(wm):
        return "model_pos:len(%d vs %d)" % (len(gm), len(wm))
    worst = max((max(abs(a[0] - b[0]), abs(a[1] - b[1])) for a, b in zip(gm, wm)), default=0.0)
    if worst > BAR_IN:
        return "model_pos:%.3f" % worst
    gd, wd = got.get("delta") or [0, 0], want.get("delta") or [0, 0]
    if max(abs(gd[0] - wd[0]), abs(gd[1] - wd[1])) > BAR_IN:
        return "delta:%.3f" % max(abs(gd[0] - wd[0]), abs(gd[1] - wd[1]))
    if abs(float(got.get("board_in", 0)) - float(want.get("board_in", 0))) > 0.001:
        return "board_in"
    go, wo = got.get("opts") or {}, want.get("opts") or {}
    if bool(got.get("allow_contact")) != bool(want.get("allow_contact")):
        return "allow_contact"
    for f in ("difficult_cap_in", "charge_allowance"):
        if (go.get(f) or 0.0) != (wo.get(f) or 0.0):
            return "opts.%s(%s vs %s)" % (f, go.get(f), wo.get(f))
    if abs(float(go.get("clearance", 0)) - float(wo.get("clearance", 0))) > 1e-6:
        return "opts.clearance"
    if bool(go.get("zones_rest_only")) != bool(wo.get("zones_rest_only")):
        return "opts.zones_rest_only"
    cg, cw = go.get("charge_goal"), wo.get("charge_goal")
    if bool(cg) != bool(cw):
        return "opts.charge_goal:presence"
    if cg and max(abs(cg[0] - cw[0]), abs(cg[1] - cw[1])) > BAR_IN:
        return "opts.charge_goal:%.3f" % max(abs(cg[0] - cw[0]), abs(cg[1] - cw[1]))
    for f in ("radii", "zones", "avoid_cells", "avoid_fine", "forbid_cells",
              "charge_tgt_bases", "charge_slots"):
        lg, lw = len(go.get(f) or []), len(wo.get(f) or [])
        if lg != lw:
            return "opts.%s:len(%d vs %d)" % (f, lg, lw)
    lg, lw = len(got.get("walls") or []), len(want.get("walls") or [])
    if lg != lw:
        return "walls:len(%d vs %d)" % (lg, lw)
    return ""


def run(ref: Path, repo: str, limit: int, red_shift: bool, red_no_walls: bool,
        report_only: bool) -> int:
    games = sorted(d for d in ref.iterdir()
                   if d.is_dir() and (d / "moves_calls.jsonl").exists())
    if limit:
        games = games[:limit]
    if not games:
        print("no moves_calls.jsonl under %s" % ref)
        return 1

    t = {k: 0 for k in ("acts", "no_call", "declined", "end_equal", "call_equal",
                        "budget_equal", "models", "models_equal")}
    worst = 0.0
    reasons: dict[str, int] = {}
    firsts: list[str] = []
    walls_pairs = walls_games = 0
    walls_worst = 0.0
    no_walls_games = 0
    t0 = time.perf_counter()

    for d in games:
        head, lines, dice, seed = read_game(d)
        with open(d / "moves_calls.jsonl", encoding="utf-8") as f:
            mh = json.loads(f.readline())
            calls = [json.loads(x) for x in f if x.strip()]
        board = mh.get("board_in") or [0.0, 0.0]
        half = [board[0] * 0.5, board[1] * 0.5]
        walls, _src = header_walls_m(d, head)
        if not walls:
            no_walls_games += 1
        core = nml_core.load(repo)
        core.set_header({"profiles": head["profiles"],
                         "terrain": dict(head.get("terrain") or {},
                                         walls=[] if red_no_walls else walls)
                         if head.get("terrain") else None,
                         "knobs": dict(head.get("knobs", {}), hero_attach=True,
                                       charge_landing=True, movement=True)})
        if walls and not red_no_walls:
            walls_games += 1
            back = [[[(p[0] / IN2M) + half[0], (p[1] / IN2M) + half[1]] for p in w]
                    for w in walls]
            for g, w in zip(core.walls_in(), back):
                for pg, pw in zip(g, w):
                    walls_worst = max(walls_worst, abs(pg[0] - pw[0]), abs(pg[1] - pw[1]))
                    walls_pairs += 1
        for act in lines:
            k = int(act["act"])
            a = (act.get("pick") or {}).get("action") or {}
            if int(a.get("kind", -1)) != CHARGE_KIND or not a.get("charge"):
                continue
            rec = [c for c in calls if int(c["act"]) == k and c.get("allow_contact")]
            if not rec:
                # The table ran no charge move under this ordinal at all — class A
                # of the D5 recon (the adopted-charge re-gate to RUSH, or a forced
                # HOLD). D5-3 owns it; there is no landing to compare here.
                t["no_call"] += 1
                continue
            t["acts"] += 1
            got = core.charge_move(core.state_of(act["state"]), a["unit"], a["charge"])
            if got is None:
                t["declined"] += 1
                reasons["declined"] = reasons.get("declined", 0) + 1
                continue
            want = rec[-1]
            # The recorded rung line carries the band the call was granted.
            reach = float(want["rung"].split("reach_in=")[1].split()[0])
            if abs(reach - float(got["budget_in"])) <= 0.001:
                t["budget_equal"] += 1
            why = call_diff(got.get("call") or {},
                            dict(want, walls=(mh.get("walls") or [])
                                 if want.get("walls") == "header" else want.get("walls")))
            if not why:
                t["call_equal"] += 1
            else:
                reasons[why.split(":")[0]] = reasons.get(why.split(":")[0], 0) + 1
            end = [[(p[0] / IN2M) + half[0], (p[2] / IN2M) + half[1]] for p in got["end"]]
            pl = [[p[0] + (0.06 if red_shift else 0.0), p[1] + (0.06 if red_shift else 0.0)]
                  for p in (want.get("planned") or [])]
            if len(pl) != len(end):
                reasons["planned:len"] = reasons.get("planned:len", 0) + 1
                if len(firsts) < 3:
                    firsts.append("%s act %d [len] %d endpoints vs the table's %d"
                                  % (d.name, k, len(end), len(pl)))
                continue
            t["models"] += len(pl)
            gap = 0.0
            for g, w in zip(end, pl):
                one = max(abs(g[0] - w[0]), abs(g[1] - w[1]))
                gap = max(gap, one)
                if one <= BAR_IN:
                    t["models_equal"] += 1
            worst = max(worst, gap)
            if gap <= BAR_IN:
                t["end_equal"] += 1
            else:
                reasons["end"] = reasons.get("end", 0) + 1
                if len(firsts) < 3:
                    firsts.append("%s act %d [end] worst model %.3f\" off%s"
                                  % (d.name, k, gap, (" — call: " + why) if why else ""))

    label = "GATE D5-2 charge move"
    if red_shift:
        label = "RED D5-2 --red-shift (every recorded endpoint moved 0.06\")"
    if red_no_walls:
        label = "RED D5-2 --red-no-walls (the board's wall segments withheld)"
    print()
    print("%s over %d games, %d charge acts with a recorded charge move (%.1fs)"
          % (label, len(games), t["acts"], time.perf_counter() - t0))
    print("  END   : %d/%d acts land EVERY model within %.2f\" of the table's own endpoint"
          % (t["end_equal"], t["acts"], BAR_IN))
    print("        : %d/%d individual models within the bar; worst act %.4f\""
          % (t["models_equal"], t["models"], worst))
    print("  CALL  : %d/%d acts build the plan_unit_step call the table recorded"
          % (t["call_equal"], t["acts"]))
    print("  BUDGET: %d/%d acts grant the band the recorded rung line names"
          % (t["budget_equal"], t["acts"]))
    print("  aside : %d charge acts ran NO charge move on the table (D5-3's class A); "
          "%d declined" % (t["no_call"], t["declined"]))
    print("  first field to part: %s"
          % (", ".join("%s=%d" % kv for kv in sorted(reasons.items())) or "none"))
    if walls_games:
        print("  walls : %d endpoint pairs over %d games, worst |port inch - recorded inch| "
              "= %.6f\"" % (walls_pairs, walls_games, walls_worst))
    if no_walls_games:
        print("  WARN  : %d of %d games carry no wall segments at all — those routes bend "
              "only around Impassable cells" % (no_walls_games, len(games)))
    for f in firsts:
        print("  first : %s" % f)

    if red_shift or red_no_walls:
        ok = t["end_equal"] < t["acts"]
        print("  RED %s" % ("held — %d of %d acts part"
                            % (t["acts"] - t["end_equal"], t["acts"]) if ok else
                            "FAILED — every act survived the damage"))
        return 0 if ok else 1
    ok = t["acts"] > 0 and t["end_equal"] == t["acts"] and t["call_equal"] == t["acts"]
    if report_only:
        print("  REPORT ONLY — %d/%d acts short, exit 0 by request"
              % (t["acts"] - t["end_equal"], t["acts"]))
        return 0
    print("  %s" % ("PASS" if ok else
                    "FAIL — %d of %d acts do not land where the table landed"
                    % (t["acts"] - t["end_equal"], t["acts"])))
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of arena game dirs")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[3]))
    ap.add_argument("--limit", type=int, default=0, help="only the first N game dirs")
    ap.add_argument("--red-shift", action="store_true",
                    help="RED PROOF: move every RECORDED endpoint 0.06\" — one hundredth past "
                         "the bar — and nothing else; every act must part")
    ap.add_argument("--red-no-walls", action="store_true",
                    help="RED PROOF: plan the same charges with the board's wall segments "
                         "withheld; the routes that had to bend must miss")
    ap.add_argument("--report-only", action="store_true",
                    help="exit 0 even when acts are short (this tool is a GATE by default)")
    a = ap.parse_args(argv)
    return run(Path(a.ref).expanduser(), a.repo, a.limit, a.red_shift, a.red_no_walls,
               a.report_only)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
