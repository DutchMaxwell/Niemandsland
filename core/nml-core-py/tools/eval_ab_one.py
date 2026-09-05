#!/usr/bin/env python3
"""Play ONE eval-variant A/B game on the fast core: the CANDIDATE seat plays
`eval_variant=cand_variant` (the evolved-hand-eval lane's own seam), the other
seat plays the frozen `eval_variant=0`. Same harness shims and knobs as
`search_ab_one.py` (layout seed mapped +500000, tray seeded from the given
dice_seed, charge_gate off, hero_attach/dice/charge_landing table, movement
rigid, sighting model, cond_ap on, objectives rulebook, deployment arena,
sidecars off, NO net).

Doubles as the SEARCH-SENSITIVITY driver (DESIGN §6 step 1, RED-2): pass
`--deep-top-k`/`--deep-horizon` to put the candidate seat on a SECOND core at
that search depth instead of (or as well as — combined onto one core when
both are given) the eval-variant core, reusing `play_game`'s existing
`deep_player` pattern (PR #515). Today `--cand-variant` past 0 is refused by
the header parser (`acts::read_act_header` has no arm past 0 yet) — this tool
is the seam's own test harness, not a new eval.

Grade is "planner_v0" when neither knob moved off its default (the NULL run:
variant 0 vs variant 0, base search both sides); otherwise it is
"planner_v0_eval<cand_variant>" and/or "planner_v0_deep", so
`ab_score.py`-shaped scorers can tell which effect a row is measuring.
Filename always carries `--cand-player` explicitly (unlike `search_ab_one.py`,
whose two grades are never equal) because the NULL run's two grades ARE equal.
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

REPO = str(Path(__file__).resolve().parents[3])
PYDIR = str(Path(__file__).resolve().parents[1] / "python")
BANK = os.path.expanduser("~/selfplay_out/terrain_bank")

sys.path.insert(0, PYDIR)

import selfplay  # noqa: E402
import gen0_replay_one as gr  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--dice-seed", type=int, required=True)
    ap.add_argument("--army1", required=True)
    ap.add_argument("--army2", required=True)
    ap.add_argument("--cand-player", type=int, choices=(1, 2), required=True)
    ap.add_argument("--cand-variant", type=int, default=0,
                     help="eval_variant for the candidate seat (0 = the NULL run)")
    ap.add_argument("--base-top-k", type=int, default=6)
    ap.add_argument("--base-horizon", type=int, default=2)
    ap.add_argument("--deep-top-k", type=int, default=None,
                     help="SENSITIVITY red: candidate seat's search depth (default: unset -> off)")
    ap.add_argument("--deep-horizon", type=int, default=None)
    ap.add_argument("--repo", default=REPO)
    ap.add_argument("--bank", default=BANK)
    a = ap.parse_args()

    gr.G["dice"] = a.dice_seed
    deep_on = a.deep_top_k is not None or a.deep_horizon is not None
    kwargs = dict(
        sidecars=False,
        top_k=a.base_top_k, horizon=a.base_horizon,
        charge_gate="off", hero_attach="table", dice="table",
        charge_landing="table", movement="rigid", sighting="model",
        cond_ap=True, objectives="rulebook", deployment="arena",
        dice_seed=a.dice_seed,
    )
    if deep_on:
        kwargs.update(
            deep_player=a.cand_player,
            deep_top_k=a.deep_top_k if a.deep_top_k is not None else a.base_top_k,
            deep_horizon=a.deep_horizon if a.deep_horizon is not None else a.base_horizon,
        )
    if a.cand_variant != 0:
        kwargs.update(eval_variant_player=a.cand_player, eval_variant=a.cand_variant)

    t0 = time.perf_counter()
    with gr.armed(selfplay._pick_for):
        res = selfplay.play_game(a.seed, a.army1, a.army2, a.repo, a.bank, None, **kwargs)
    wall = time.perf_counter() - t0

    suffix = "".join([
        f"_eval{a.cand_variant}" if a.cand_variant != 0 else "",
        "_deep" if deep_on else "",
    ]) or ""
    cand_grade = "planner_v0" + suffix
    other_grade = "planner_v0"
    if a.cand_player == 1:
        grades = {"p1": cand_grade, "p2": other_grade}
    else:
        grades = {"p1": other_grade, "p2": cand_grade}
    res["grades"] = grades
    res["armies"] = {"p1": a.army1, "p2": a.army2}
    res["wall_seconds"] = round(wall, 3)
    res["prescreen"] = {
        **res.get("prescreen", {}),
        "tool": "eval_ab_one", "deployment": "arena",
        "seed": a.seed,
        "dice_seed_used": a.dice_seed,
        "layout_seed_used": a.seed + 500000,
        "cand_player": a.cand_player,
        "cand_variant": a.cand_variant,
        "knobs_by_seat": (
            {("p1" if a.cand_player == 1 else "p2"): {"eval_variant": a.cand_variant}}
            if a.cand_variant != 0 else None
        ),
        "knobs": {"charge_gate": "off", "hero_attach": "table",
                  "dice": "table", "charge_landing": "table", "movement": "rigid",
                  "sighting": "model", "cond_ap": True, "objectives": "rulebook",
                  "engage_fold": True, "sidecars": False},
    }
    # cand_player is always in the filename: unlike search_ab_one.py's two
    # grades (never equal), the NULL run's grades ARE equal on both seats.
    stem = "arena_%s_vs_%s_s%d_d%d_cand%d.json" % (
        grades["p1"], grades["p2"], a.seed, a.dice_seed, a.cand_player)
    os.makedirs(a.out_dir, exist_ok=True)
    with open(os.path.join(a.out_dir, stem), "w", encoding="utf-8") as f:
        json.dump(res, f)
    print("[AB] %s seed=%d dice=%d cand_p%d variant=%d winner=%s wall=%.1fs" % (
        stem, a.seed, a.dice_seed, a.cand_player, a.cand_variant, res["winner"], wall))
    return 0


if __name__ == "__main__":
    sys.exit(main())
