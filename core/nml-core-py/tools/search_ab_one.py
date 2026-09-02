#!/usr/bin/env python3
"""Play ONE search A/B game on the fast core: one seat searches DEEPER than
the other (deep_top_k/deep_horizon vs base top_k/horizon), so paired games
answer "does more search make the AI stronger?". Same harness shims and knobs
as residual_one.py: layout seed mapped +500000, tray seeded from the given
dice_seed, charge_gate off, hero_attach/dice/charge_landing table, movement
rigid, sighting model, cond_ap on, objectives rulebook, deployment arena,
sidecars off, NO net.

The deep seat's grade is stamped "planner_v0_deep", the other "planner_v0",
so ab_score.py scores the directory directly. Filename follows the arena
convention: arena_<p1grade>_vs_<p2grade>_s<seed>_d<dice>.json.
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

import nml_core  # noqa: E402
import selfplay  # noqa: E402

_orig_layout = nml_core.objective_layout
_orig_tray = nml_core.Tray
_DICE = {"v": 0}


def _layout(terrain, seed, mode, zones):
    return _orig_layout(terrain, seed + 500000, mode, zones)


def _tray(_seed):
    return _orig_tray(_DICE["v"])


nml_core.objective_layout = _layout
nml_core.Tray = _tray


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir")
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--dice-seed", type=int, required=True)
    ap.add_argument("--army1", required=True)
    ap.add_argument("--army2", required=True)
    ap.add_argument("--deep-player", type=int, choices=(1, 2), required=True)
    ap.add_argument("--deep-top-k", type=int, default=12)
    ap.add_argument("--deep-horizon", type=int, default=3)
    ap.add_argument("--base-top-k", type=int, default=6)
    ap.add_argument("--base-horizon", type=int, default=2)
    ap.add_argument("--repo", default=REPO)
    ap.add_argument("--bank", default=BANK)
    a = ap.parse_args()

    _DICE["v"] = a.dice_seed
    t0 = time.perf_counter()
    res = selfplay.play_game(
        a.seed,
        a.army1,
        a.army2,
        a.repo,
        a.bank,
        None,
        sidecars=False,
        top_k=a.base_top_k,
        horizon=a.base_horizon,
        deep_player=a.deep_player,
        deep_top_k=a.deep_top_k,
        deep_horizon=a.deep_horizon,
        charge_gate="off",
        hero_attach="table",
        dice="table",
        charge_landing="table",
        movement="rigid",
        sighting="model",
        cond_ap=True,
        objectives="rulebook",
        deployment="arena",
        dice_seed=a.dice_seed,
    )
    wall = time.perf_counter() - t0

    deep_knobs = {"top_k": a.deep_top_k, "horizon": a.deep_horizon}
    base_knobs = {"top_k": a.base_top_k, "horizon": a.base_horizon}
    if a.deep_player == 1:
        grades = {"p1": "planner_v0_deep", "p2": "planner_v0"}
        seat_knobs = {"p1": deep_knobs, "p2": base_knobs}
        stem = "arena_planner_v0_deep_vs_planner_v0_s%d_d%d.json" % (a.seed, a.dice_seed)
    else:
        grades = {"p1": "planner_v0", "p2": "planner_v0_deep"}
        seat_knobs = {"p1": base_knobs, "p2": deep_knobs}
        stem = "arena_planner_v0_vs_planner_v0_deep_s%d_d%d.json" % (a.seed, a.dice_seed)
    res["grades"] = grades
    res["armies"] = {"p1": a.army1, "p2": a.army2}
    res["wall_seconds"] = round(wall, 3)
    res["prescreen"] = {
        "tool": "search_ab_one", "deployment": "arena",
        "seed": a.seed,
        "dice_seed_used": a.dice_seed,
        "layout_seed_used": a.seed + 500000,
        "deep_player": a.deep_player,
        "knobs_by_seat": seat_knobs,
        "knobs": {"charge_gate": "off", "hero_attach": "table",
                  "dice": "table", "charge_landing": "table", "movement": "rigid",
                  "sighting": "model", "cond_ap": True, "objectives": "rulebook",
                  "engage_fold": True, "sidecars": False},
    }
    os.makedirs(a.out_dir, exist_ok=True)
    with open(os.path.join(a.out_dir, stem), "w", encoding="utf-8") as f:
        json.dump(res, f)
    print("[AB] %s seed=%d dice=%d deep_p%d winner=%s wall=%.1fs" % (
        stem, a.seed, a.dice_seed, a.deep_player, res["winner"], wall))
    return 0


if __name__ == "__main__":
    sys.exit(main())
