"""Godot-free self-play — the round loop of `tools/core_selfplay.gd` in Python
on the Rust core (NML-1073 M3-5).

WHAT THIS IS. `tools/core_selfplay.gd` plays whole AI-vs-AI training games on
the `BattleSim` substrate inside a Godot process. Everything it does that is a
RULE lives in `core/nml-core` already (state, menu, search, resolve, LOS,
mission scoring); what is left is ORCHESTRATION — build the armies, deploy them,
alternate activations, refresh the round, seize the markers, write the result.
That orchestration is what this module ports, and nothing else: every rule
question is asked of `nml_core`.

The three GDScript functions ported here, field for field:

  `_deploy_zone` (core_selfplay.gd:593-606)   — the 12"-deep zone deployment,
      drawing from the GAME's `RandomNumberGenerator` in the same order.
  `_capture`     (:608-637) over `BattleSim.capture` (battle_sim.gd:1274-1412)
      and `BattleSim.state_to_plain` (:1432-1518) — the plain round-1 state.
  `_play_one` / `_play_round` / `_seize` (:164-307, :419-434) — the round loop.

WHAT IT DOES NOT PRODUCE (deliberately, and named rather than faked):

  * `planner_positions[].board` / `.features` — `BattleSim.board_rows` and
    `AiMissionEval.features` are the two encoders the crate does not carry yet
    (recon items 9 and 10). The rows here carry side/round/seq/value/unit/kind/
    intent, which is what the M3-5 gate compares; the trainer's net inputs are a
    later step.
  * `planner_positions[].pair` / `.fork` — the E0b/E2 counterfactual sidecars.
    They resolve on CLONES under log-local generators (core_selfplay.gd:262-296)
    and never touch the game's dice stream, so leaving them out changes no game;
    it only leaves the corpus thinner.
  * `terrain` (the drawing list), `magic` (the cast telemetry) and
    `unknown_rules`. The terrain bank stores the act-header shape, not
    `SchoolTerrain`'s `pieces`; the magic ledger needs the spell registry's
    per-unit book and the unknown-rule tally needs the port's `Unimplemented`
    list, neither of which the seam exposes. All three are ABSENT keys here,
    never zero-filled ones: a `[]` would claim a coverage this does not have.

THE DICE. One `nml_core.Rng` per game, seeded with the game seed, exactly as
`_play_one` (:169-170) does: deployment draws first (p1 then p2, x then z per
unit), then the two `randi_range(1, 6)` of the opener roll-off, then every
played `resolve_stochastic`. A per-call seed would be a different game.

THE BOARD. `SchoolTerrain.generate(seed)` is a Godot layouter; M3-4 banked its
output for seeds 1..200 in the act-header terrain shape
(`tools/terrain_bank_dump.gd`), and this module reads the bank. A seed outside
the bank raises rather than inventing a board.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path
from typing import Any

import nml_core

from list_to_profile import _faction_from_path, profiles_from_army_forge_json

# core_selfplay.gd:20-23
IN2M = 0.0254
TABLE_W_IN = 72.0
TABLE_D_IN = 48.0
ROUNDS = 4
# game_unit.gd — `add_round_caster_points` caps the accumulation here.
CASTER_POINTS_CAP = 6
# terrain_rules.gd:20 — TerrainType.RUINS / FOREST are the two that give cover.
COVER_TYPES = (1, 2)
# separation_checker.gd — the trainer's units never carry a base size, so every
# model measures the shared default (see list_to_profile's module docstring).
DEFAULT_BASE_RADIUS_M = 0.016
# The zero reading of `SoloController.active_mod_net_of` (:5429-5431): the
# trainer never records a spell, so `mods` is this dict on every capture.
ZERO_MODS = {"hit": 0, "def": 0, "morale": 0, "range_in": 0.0, "advance": 0.0, "rush": 0.0}


def f32(x: float) -> float:
    """One `real_t` narrowing. Every `Vector3` component in the engine is a
    single, so a position written as `Vector3(a * IN2M, 0, b * IN2M)` is the f64
    product rounded ONCE — which is what `m.node.global_position` reads back and
    what the recorder writes out."""
    return struct.unpack("f", struct.pack("f", x))[0]


def _centre_f32(positions: list[list[float]]) -> list[float]:
    """`BattleSim._centre_of` / the `cover_of` lambda (core_selfplay.gd:618-628):
    a `Vector3` sum divided by the model count, all of it in SINGLE precision."""
    if not positions:
        return [0.0, 0.0, 0.0]
    c = [0.0, 0.0, 0.0]
    for p in positions:
        for k in range(3):
            c[k] = f32(c[k] + p[k])
    n = float(len(positions))
    return [f32(c[k] / n) for k in range(3)]


# ------------------------------------------------------------------ armies ---


def load_army(path: str | Path, player: int) -> list[dict[str, Any]]:
    """`_units_from_list` (core_selfplay.gd:437-495) as profiles, in the order
    the loader creates them — which IS `OPRArmyManager.game_units`' insertion
    order and therefore the capture order the whole state is indexed by."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    profiles = profiles_from_army_forge_json(data, _faction_from_path(path), player)
    return list(profiles.values())


# -------------------------------------------------------------- deployment ---


def deploy_zone(
    units: list[dict[str, Any]], z0_in: float, depth_in: float, rng: "nml_core.Rng"
) -> list[list[list[float]]]:
    """`_deploy_zone` core_selfplay.gd:593-606 — units spread evenly across the
    table's width, each dropped at a random spot in its own slot of the 12"-deep
    zone, models laid out 5 wide at 1" spacing.

    TWO draws per unit, x before z, and the units in list order: that order is
    the whole reason a Python port has to hold the game's own generator instead
    of seeding one per call."""
    n = len(units)
    out: list[list[list[float]]] = []
    for i, u in enumerate(units):
        x0 = (-TABLE_W_IN / 2.0 + 8.0) + (TABLE_W_IN - 16.0) * (float(i) + 0.5) / float(n)
        best_x = x0 + rng.randf_range(-3.0, 3.0)
        best_z = z0_in + rng.randf_range(1.0, depth_in - 3.0)
        models = []
        for m in range(int(u["model_count"])):
            models.append(
                [f32((best_x + float(m % 5)) * IN2M), 0.0, f32((best_z + float(m // 5)) * IN2M)]
            )
        out.append(models)
    return out


# ----------------------------------------------------------------- capture ---


def capture(
    units: list[dict[str, Any]],
    positions: list[list[list[float]]],
    reads: dict[str, dict[str, Any]],
    board: "nml_core.Board",
    objectives: list[list[float]],
) -> dict[str, Any]:
    """`_capture` (core_selfplay.gd:608-637) through `BattleSim.capture` and
    `BattleSim.state_to_plain(state, false)` — the plain state the search reads.

    Everything a live game would ask the `GameUnit` for comes from one of two
    places: the STATIC profile (`list_to_profile`) or the registry reads the
    Rust seam answers (`Core.capture_reads`). Nothing is defaulted silently."""
    us: dict[str, Any] = {}
    for u, pos in zip(units, positions):
        key = u["unit_id"]
        r = reads[key]
        centre = _centre_f32(pos)
        us[key] = {
            "player": 1 if key.startswith("p1_") else 2,
            "positions": pos,
            "alive": len(pos),
            "wounds": list(u["wounds_max"]),
            "radii": [u["base_radius"]] * len(pos),
            # `cover_of` is a SINGLE centroid probe (core_selfplay.gd:618-628),
            # not the arena's strict majority of models in cover.
            "in_cover": board.type_at(centre) in COVER_TYPES,
            "morale_bonus": r["morale_bonus"],
            "mods": dict(ZERO_MODS),
            "mods_base": dict(ZERO_MODS),
            "aircraft": r["aircraft"],
            "ambush_arrived_round": -1,
            "shaken": False,
            "fatigued": False,
            "activated": False,
            # `initialize_caster_points` game_unit.gd:417-422 — the build-time
            # grant is the whole Caster(X) rating; round 2+ refills on top.
            "casts": max(int(u["caster_value"]), 0),
            # The trainer never attaches heroes: its OPRUnit carries neither a
            # selectionId nor a joinToUnit, so capture's derivation finds none.
            "attached": [],
            "attached_to": "",
            "bands": {
                "advance": u["move_bands"]["advance"],
                "rush": u["move_bands"]["rush"],
            },
            "charge_no_difficult": r["charge_no_difficult"],
            # `_move_base_radius_of` act_recorder.gd:262-270: the unit's own
            # alive models plus attached heroes, floored at the shared default.
            "charge_probe_r": max(float(u["base_radius"]), DEFAULT_BASE_RADIUS_M),
        }
        if r["shroud"] is not None:
            us[key]["shroud"] = list(r["shroud"])
    state = {
        "round": 1,
        "rounds_total": ROUNDS,
        "scoring": "end",
        "objectives": [{"pos": p, "owner": 0} for p in objectives],
        "units": us,
    }
    # `state["los_blocked"]` is a live Callable in the trainer, and
    # `state_to_plain` records its answers as this matrix (battle_sim.gd:
    # 1492-1506). `resolve` refreshes it from the same board as models move.
    state["los_pairs"] = board.los_pairs(us)
    return state


# --------------------------------------------------------------- the board ---


def load_board(seed: int, bank_dir: str | Path) -> tuple["nml_core.Board", dict[str, Any]]:
    """One banked school board — `tools/terrain_bank_dump.gd` writes the act
    header's terrain object for `SchoolTerrain.generate(seed)`."""
    path = Path(bank_dir) / ("board_%d.json" % seed)
    if not path.exists():
        raise FileNotFoundError(
            "no banked board for seed %d (%s) — run tools/terrain_bank_dump.gd" % (seed, path)
        )
    with open(path, encoding="utf-8") as f:
        terrain = json.load(f)["terrain"]
    return nml_core.board(terrain), terrain


# ------------------------------------------------------------------- knobs ---

# `AiActRecorder._header_line` act_recorder.gd:144-150 resolves these from the
# planner's class statics; `tools/core_selfplay.gd` runs them at their defaults
# with NML_SIM_SPACING on and NML_SIM_CAST off, which is what a recorded header
# of this trainer says. `charge_gate` is the M3-5 addition: the trainer never
# stamps `state["charge_illegal"]`, so both menu sites skip the gate outright.
TRAINER_KNOBS = {
    "top_k": 6,
    "horizon": 2,
    "tail_cap_p1": 0,
    "tail_cap_p2": 0,
    "imagined_round_end": True,
    "depth_discount": 0.5,
    "seat_mode": 0,
    "playout_margin": 0.02,
    "playout_rich": True,
    "seam_cast": False,
    "seam_spacing": True,
    "seam_path": False,
    "charge_gate": False,
}

# `AiActRecorder.begin` :65-66 — the planner's per-activation class statics, all
# at their defaults in a trainer process.
TRAINER_STATICS = {
    "opener_seat": False,
    "playout_search": False,
    "fit_mode": False,
    "playout_net": {},
}


# ------------------------------------------------------------------- game ----


def _pick_for(core, state, player: int) -> dict[str, Any]:
    """`_pick_for` core_selfplay.gd:398-459 — the full planner for whichever side
    still has a living, un-activated unit; `{}` when the side is dry."""
    if not state.pool(player):
        return {}
    pick = core.plan_with_rollout(state, player, TRAINER_STATICS)
    return pick if pick.get("used") else {}


def _refill_round_caster_points(unit: dict[str, Any], profile: dict[str, Any]) -> int:
    """`_refill_round_caster_points` core_selfplay.gd:120-135 over
    `GameUnit.add_round_caster_points` (game_unit.gd:426-434). The GRANT is what
    it returns; the unit dict is updated in place.

    Note the Caster Group branch reads the LIVE GameUnit's alive models, which
    the trainer never kills (`BattleSim` edits the state dict, not the models) —
    so it resets to the unit's full model count, not to the sim's `alive`."""
    before = int(unit["casts"])
    if any(str(r).startswith("Caster Group") for r in profile["special_rules"]):
        unit["casts"] = int(profile["model_count"])
    elif int(profile["caster_value"]) > 0:
        unit["casts"] = min(before + int(profile["caster_value"]), CASTER_POINTS_CAP)
    return int(unit["casts"]) - before


def _round_start(plain: dict[str, Any], round_no: int, by_key: dict[str, dict]) -> int:
    """`_play_one`'s per-round reset (core_selfplay.gd:190-201): the round number,
    the expired spell modifiers (`BattleSim.reset_round_mods`), the activation and
    fatigue flags, and — from round 2 — the Caster(X) refill.

    Returns the tokens granted this round, which is the one number
    `_refill_round_caster_points` feeds the trainer's magic ledger — kept here so
    a caller that writes that ledger has it, though this port does not (see the
    module docstring)."""
    plain["round"] = round_no
    granted = 0
    for key, u in plain["units"].items():
        u["mods"] = dict(u.get("mods_base", ZERO_MODS))
        u["activated"] = False
        u["fatigued"] = False
        if round_no >= 2:
            granted += _refill_round_caster_points(u, by_key[key])
    return granted


def _play_round(core, state, opener: int, rng, log: list, round_no: int) -> tuple[Any, int]:
    """`_play_round` core_selfplay.gd:247-307 — strict one-for-one alternation, a
    dry side hands the tail to the other, and the NEXT round opens with whoever
    did NOT take the last activation."""
    turn = opener
    last_side = 0
    guard = state.units * 2 + 4
    while guard > 0:
        guard -= 1
        pick = _pick_for(core, state, turn)
        if not pick:
            other = 2 if turn == 1 else 1
            pick = _pick_for(core, state, other)
            if not pick:
                break
            turn = other
        action = pick["action"]
        log.append(
            {
                "side": turn,
                "round": round_no,
                "seq": len(log),
                "value": float(pick["expectation"]["before"]),
                "unit": pick["unit_key"],
                "kind": int(action["kind"]),
                "action": action,
                "intent": str(pick.get("intent", "")),
            }
        )
        state = core.resolve_stochastic_rng(state, action, rng)
        last_side = turn
        turn = 2 if turn == 1 else 1
    nxt = (2 if last_side == 1 else 1) if last_side != 0 else opener
    return state, nxt


def play_game(
    seed: int,
    list_p1: str | Path,
    list_p2: str | Path,
    repo_root: str | Path,
    bank_dir: str | Path,
    core=None,
    deploy_rng_seed: int | None = None,
) -> dict[str, Any]:
    """One full match for `seed` — `_play_one` core_selfplay.gd:164-244.

    `core` may be a `nml_core.Core` to reuse across games (the registries and the
    mechanics maps are the expensive part); its header is re-set per game anyway,
    because the board changes with the seed.

    `deploy_rng_seed` is the RED PROOF knob and nothing else: deployment then
    draws from a generator of its own while the game's generator is advanced by
    the SAME number of draws and discards them, so the opener roll-off and every
    die of every activation stay bit-identical and the ONLY thing that moved is
    where the models were put. A gate that could not tell that apart would be
    measuring the seed, not the deployment."""
    units1 = load_army(list_p1, 1)
    units2 = load_army(list_p2, 2)
    if not units1 or not units2:
        raise ValueError("empty army (%s / %s)" % (list_p1, list_p2))
    units = units1 + units2
    profiles = {u["unit_id"]: u for u in units}

    board, terrain = load_board(seed, bank_dir)
    if core is None:
        core = nml_core.load(str(repo_root))
    core.set_header({"profiles": profiles, "terrain": terrain, "knobs": TRAINER_KNOBS})
    reads = core.capture_reads()

    rng = nml_core.Rng(seed)
    # core_selfplay.gd:176 — three markers on the centre line, 16" apart.
    objectives = [[f32(-16.0 * IN2M), 0.0, 0.0], [0.0, 0.0, 0.0], [f32(16.0 * IN2M), 0.0, 0.0]]
    if deploy_rng_seed is None:
        pos1 = deploy_zone(units1, -TABLE_D_IN / 2.0, 12.0, rng)
        pos2 = deploy_zone(units2, TABLE_D_IN / 2.0 - 12.0, 12.0, rng)
    else:
        side = nml_core.Rng(deploy_rng_seed)
        pos1 = deploy_zone(units1, -TABLE_D_IN / 2.0, 12.0, side)
        pos2 = deploy_zone(units2, TABLE_D_IN / 2.0 - 12.0, 12.0, side)
        deploy_zone(units1, -TABLE_D_IN / 2.0, 12.0, rng)
        deploy_zone(units2, TABLE_D_IN / 2.0 - 12.0, 12.0, rng)
    plain = capture(units, pos1 + pos2, reads, board, objectives)
    state = core.state_of(plain)

    owners = [0, 0, 0]
    vp = [0, 0]
    # The d6 roll-off, P1 winning ties — and BOTH dice are drawn, left first.
    left = rng.randi_range(1, 6)
    right = rng.randi_range(1, 6)
    opener = 1 if left >= right else 2
    log: list[dict[str, Any]] = []
    rounds_log: list[dict[str, Any]] = []
    rounds_played = 0
    for round_no in range(1, ROUNDS + 1):
        plain = state.plain()
        _round_start(plain, round_no, profiles)
        state = core.state_of(plain)
        state, opener = _play_round(core, state, opener, rng, log, round_no)
        state, owners = core.playout_seize(state, owners)
        vp = core.vp_round_add(owners, vp)
        rounds_played = round_no
        rounds_log.append({"round": round_no, "owners": list(owners), "vp": list(vp)})
    vp = core.vp_end_bonus(owners, vp)

    p1 = sum(1 for o in owners if o == 1)
    p2 = sum(1 for o in owners if o == 2)
    # `_write_result` :700-706: Face-Off is END-scored, so the MARKERS decide.
    winner = "draw" if p1 == p2 else ("p1" if p1 > p2 else "p2")
    return {
        "schema": 1,
        "board_schema": 5,
        "rule_vocab": "v1d",
        "school_world": 2,
        "tool": "core_selfplay_py",
        "seed": seed,
        "dice_seed": seed,
        "grades": {"p1": "planner_core", "p2": "planner_core"},
        "mission": {
            "family": "face_off",
            "name": "duel",
            "rounds": ROUNDS,
            "deployment": "zone12",
            "symmetric": True,
            "objective_count": 3,
            "packs": [],
        },
        "armies": {"p1": str(list_p1), "p2": str(list_p2)},
        "opener": 0,
        "objectives": {"p1": p1, "p2": p2, "neutral": len(owners) - p1 - p2},
        "vp": {"p1": int(vp[0]), "p2": int(vp[1])},
        "scoring": "end",
        "winner": winner,
        "rounds_played": rounds_played,
        "rounds_log": rounds_log,
        "planner_positions": log,
        "planner_calib": [],
        "roster": [u["name"] for u in units],
    }


def main(argv: list[str]) -> int:
    import argparse
    import time

    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--army1", required=True)
    ap.add_argument("--army2", required=True)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--games", type=int, default=1)
    ap.add_argument("--repo", required=True, help="repo root — assets/solo/*.json live here")
    ap.add_argument("--bank", required=True, help="terrain bank directory")
    ap.add_argument("--out", default="", help="directory for core_s<seed>.json")
    ap.add_argument(
        "--deploy-rng-offset",
        type=int,
        default=0,
        help="RED PROOF: deploy from seed+OFFSET while the dice stay on seed",
    )
    a = ap.parse_args(argv)

    core = nml_core.load(a.repo)
    for g in range(a.games):
        seed = a.seed + g
        t0 = time.perf_counter()
        res = play_game(
            seed,
            a.army1,
            a.army2,
            a.repo,
            a.bank,
            core,
            deploy_rng_seed=(seed + a.deploy_rng_offset) if a.deploy_rng_offset else None,
        )
        res["wall_seconds"] = round(time.perf_counter() - t0, 3)
        if a.out:
            Path(a.out).mkdir(parents=True, exist_ok=True)
            with open(Path(a.out) / ("core_s%d.json" % seed), "w", encoding="utf-8") as f:
                json.dump(res, f)
        print(
            "[PY] RESULT seed=%d P1=%d P2=%d -> %s in %.1fs"
            % (
                seed,
                res["objectives"]["p1"],
                res["objectives"]["p2"],
                res["winner"],
                res["wall_seconds"],
            )
        )
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main(sys.argv[1:]))
