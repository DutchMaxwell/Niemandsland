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

  * `planner_positions[].intent` — the planner's ORIGINAL intent SENTENCE
    (`AiPlanner`'s prose, "X: rush objective 1 — win 0.63 -> 0.62; over Y ..."),
    which the crate does not build: it is a report string, not a rule. The key is
    present and EMPTY here rather than absent, because that is what the M3-5 rows
    already carried. An ABSENT key would be the honest shape; the key stays for
    the corpus reader that already expects it.

THE RESULT FIELDS `terrain` AND `magic` (NML-1073 M3-9b).

  * `terrain` is the DRAWING list `tools/core_selfplay.gd:725` writes —
    `SchoolTerrain.generate(seed)["pieces"]`, one `[type, cx_in, cz_in, w_in,
    h_in, rot]` per placed piece. It is NOT derivable from the act-header terrain
    the M3-4 bank carried: that shape merges every footprint into a cell map and
    drops each piece's origin, size and rotation. So the BANK carries it now
    (`tools/terrain_bank_dump.gd` writes `pieces` next to `terrain`), and a board
    file without the key makes this module RAISE rather than write a guess.
  * `magic` is the cast telemetry (`_magic_init` / `_magic_tally` /
    `_spells_by_kind_tally` / `_magic_eligibility_tally`, core_selfplay.gd
    :33-131), ported field for field. The trainer runs with the cast sub-phase
    OFF (`seam_cast` below), so `casts`, `tokens_spent` and `spells_by_kind` are
    all zero — MEASURED zero, from the same token deltas and cast log the
    GDScript reads, not written zero.

THE ENCODER'S QUALITY/DEFENSE COLUMNS. Board columns 10 and 11 come off the
`GameUnit`'s `source_data` (battle_sim.gd:233-234). `tools/core_selfplay.gd`
used to hand every unit a BLANK `OPRApiClient.OPRUnit`, so its whole corpus read
that class's 4/4 defaults there; #392 fills the stats, and the DEFAULT here is
the unit's own quality/defense to match. `legacy_source_qd=True` reproduces the
pre-#392 reading and exists only to replay such a corpus.

THE SIDECARS (NML-1073 M3-9). `planner_positions[].board` / `.ids` /
`.features` / `.pair` / `.fork` are written, on the crate's own encoders
(`nml_core.Core.board_rows` / `.board_row_indices` / `.features`) and the crate's
cheap policy (`.policy_step`). The pair and the fork resolve on CLONES under
generators of their own — the pair's `game_seed * 100000 + seq` (+ 50000 for the
runner branch), the fork's `game_seed * 1000003 + seq (+ 500011) + rep * 70001` —
so the game's own dice stream is untouched and the played game is byte-identical
with `sidecars=False`.

THE DICE. One `nml_core.Rng` per game, seeded with the game seed, exactly as
`_play_one` (:169-170) does: deployment draws first (p1 then p2, x then z per
unit), then the two `randi_range(1, 6)` of the opener roll-off, then every
played `resolve_stochastic`. A per-call seed would be a different game.

THE BOARD. `SchoolTerrain.generate(seed)` is a Godot layouter;
`tools/terrain_bank_dump.gd` banks its output per seed — the act-header terrain
shape AND the drawing list — and this module reads the bank. A seed outside the
bank raises rather than inventing a board.
"""

from __future__ import annotations
import argparse
import contextlib

import hashlib

import json
import os
import re
import struct
import subprocess
from pathlib import Path
from typing import Any

import nml_core

from list_to_profile import (
    _faction_from_path,
    deploy_unit_specs,
    profiles_from_army_forge_json,
    selections_from_army_forge_json,
)


def _git_short_sha() -> str:
    """The short sha of the checkout this module runs from — the core build
    identity a corpus stamps as `core_commit` (Gen-1 recorder fix: Gen-0's
    rows could not say WHICH build had scored them). "unknown" when the tree
    is not a checkout (a wheel install) or git is unavailable — the stamp
    must never block a game."""
    try:
        return subprocess.run(
            ["git", "-C", str(Path(__file__).resolve().parent),
             "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, check=True, timeout=10,
        ).stdout.strip()
    except Exception:
        return "unknown"


#: Computed ONCE at import — every game this process writes stamps the same
#: sha, whatever the tree does afterwards.
_core_commit = _git_short_sha()


# core_selfplay.gd:20-23
IN2M = 0.0254
TABLE_W_IN = 72.0
TABLE_D_IN = 48.0
ROUNDS = 4
# game_unit.gd — `add_round_caster_points` caps the accumulation here.
CASTER_POINTS_CAP = 6
# `OPRApiClient.OPRUnit` :72-73 — the defaults a BLANK source_data carries, and
# so the quality/defense every pre-#392 trainer row was encoded with. Used only
# by `play_game(legacy_source_qd=True)`; see the module docstring.
SOURCE_DATA_QUALITY = 4
SOURCE_DATA_DEFENSE = 4
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


def load_selections(path: str | Path, player: int) -> dict[str, tuple[str, str]]:
    """The same list's `(selection_id, join_to_unit)` per unit key — the input
    `derive_attachment` needs and the profile deliberately does not carry."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return selections_from_army_forge_json(data, player)


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


def _arena_zones() -> dict[str, list[float]]:
    """arena_match.gd:940-947 — P1's zone front edge at -d/2, P2's at +d/2-12",
    both 12" deep across the full table width, in metres: the `[x, y, w, h]`
    Rect the Rust spot search scans."""
    w = TABLE_W_IN * IN2M
    return {
        "1": [-w / 2.0, -TABLE_D_IN / 2.0 * IN2M, w, 12.0 * IN2M],
        "2": [-w / 2.0, (TABLE_D_IN / 2.0 - 12.0) * IN2M, w, 12.0 * IN2M],
    }


def _arena_roll_off(rng: "nml_core.Rng") -> list[list[int]]:
    """`SoloController.roll_off` (solo_controller.gd:7517-7528) over the GAME
    stream: a d6 pair per attempt, TIES RE-ROLL (cap 100), every attempt kept.
    This is the stream topology the arena branch exists for (design §1): the
    roll-off is the game stream's FIRST consumer, exactly like `solo._rng` on
    the table, while deployment itself advances it NOT."""
    attempts: list[list[int]] = []
    while len(attempts) < 100:
        attempts.append([rng.randi_range(1, 6), rng.randi_range(1, 6)])
        if attempts[-1][0] != attempts[-1][1]:
            break
    return attempts


def _deploy_arena(
    seed: int,
    units1: list[dict[str, Any]],
    units2: list[dict[str, Any]],
    list_p1: str | Path,
    list_p2: str | Path,
    board: "nml_core.Board",
    objectives: list[list[float]],
    opener: int,
    interleave: bool = False,
) -> tuple[list[list[list[float]]], list[list[list[float]]], set[str], list[list[Any]]]:
    """The table's pre-game through the step-7 binding: `deploy_side` per side
    with the per-side stream `seed + slot` (arena_match.gd:486-488 — the game
    stream advances NOT), then `deploy_finish` in winner-first order (the FIRST
    finish runs on the first deployer's units ALONE, solo_controller.gd
    :9180-9188). Returns the capture positions in units order; a folded hero's
    models are its slice of the host's settled group, and a reserved (Ambush)
    unit has no placement — it starts off-table with no models, the round-2
    arrival being the declared in-game residual (design §1).

    `interleave` swaps the two whole-side `deploy_side` calls for ONE
    `deploy_interleaved` call — the rulebook's alternation (GF v3.5.1 p.6),
    same per-side streams, same finish. Returns the capture positions and the
    cross-side `[[slot, key], ..]` placement sequence (empty when off)."""
    zones = _arena_zones()
    sides: dict[str, dict[str, Any]] = {}
    reserved: dict[str, list[str]] = {}
    hero_fold: dict[str, tuple[str, int, int]] = {}
    roster: dict[str, list[dict[str, Any]]] = {}
    for slot, path in (("1", list_p1), ("2", list_p2)):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        roster[slot], fold = deploy_unit_specs(data, _faction_from_path(path), int(slot))
        hero_fold.update(fold)
    objs2 = [[o[0], o[2]] for o in objectives]
    sequence: list[list[Any]] = []
    if interleave:
        out = nml_core.deploy_interleaved(
            roster["1"], roster["2"], zones["1"], zones["2"], objs2, board,
            seed + 1, seed + 2, opener,
        )
        placed_by = {"1": out["side1"], "2": out["side2"]}
        sequence = [list(e) for e in out["sequence"]]
    else:
        placed_by = {
            slot: nml_core.deploy_side(
                roster[slot], zones[slot], objs2, board, seed + int(slot)
            )
            for slot in ("1", "2")
        }
    for slot in ("1", "2"):
        placed = placed_by[slot]
        sides[slot] = {
            "units": roster[slot], "placements": placed["placements"], "zone": zones[slot]
        }
        reserved[slot] = list(placed["reserved"])
    finished = nml_core.deploy_finish(sides, board, {}, opener)
    pos: dict[str, list[list[float]]] = {}
    for slot in ("1", "2"):
        for key in reserved[slot]:
            pos[key] = []  # held in reserve — off-table until it arrives
        for p in finished[slot]:
            pos[p["key"]] = [[f32(m[0]), 0.0, f32(m[1])] for m in p["models"]]
    for hero_key, (host_key, offset, count) in hero_fold.items():
        # A hero rides its host's group — including a host held in reserve,
        # where the slice of an empty list is empty too.
        pos[hero_key] = pos.get(host_key, [])[offset : offset + count]
    # The reserve KEYS ride out with the positions: `capture` needs them to
    # mark a unit dormant (battle_sim.gd:1483 asks `unit_in_reserve`), and an
    # empty placement list is not the same signal — a folded hero of a reserved
    # host has one too.
    return (
        [pos[u["unit_id"]] for u in units1],
        [pos[u["unit_id"]] for u in units2],
        {k for slot in ("1", "2") for k in reserved[slot]},
        sequence,
    )


# ----------------------------------------------------------------- capture ---


def derive_attachment(
    units: list[dict[str, Any]], selections: dict[str, tuple[str, str]]
) -> tuple[dict[str, list[str]], dict[str, str]]:
    """`BattleSim.capture`'s NML-1081 fallback (battle_sim.gd:1352-1369) over
    the trainer's own units, in capture order.

    An imported or AI army never calls `EquipmentDistributor.attach_hero_to_unit`
    (that is the multiplayer path), so runtime attachment is always empty and the
    table derives it from the LIST instead: one `selection_id -> unit key` index
    over BOTH armies — a later selection overwrites an earlier one with the same
    id, which is the table's behaviour and not a guard this port may add — then
    every unit whose `join_to_unit` names an indexed selection becomes that
    host's attached hero. The `attached` lists are appended in capture order,
    which is the order the recorded state carries them in.

    Returns `(attached, attached_to)` keyed by unit id, both filled for every
    unit — `[]` and `""` for a unit that neither joins nor is joined."""
    by_sel: dict[str, str] = {}
    for u in units:
        sel = selections.get(u["unit_id"], ("", ""))[0]
        if sel:
            by_sel[sel] = u["unit_id"]
    attached: dict[str, list[str]] = {u["unit_id"]: [] for u in units}
    attached_to: dict[str, str] = {u["unit_id"]: "" for u in units}
    for u in units:
        key = u["unit_id"]
        join = selections.get(key, ("", ""))[1]
        if not join or join not in by_sel:
            continue
        attached_to[key] = by_sel[join]
        attached[by_sel[join]].append(key)
    return attached, attached_to


def capture(
    units: list[dict[str, Any]],
    positions: list[list[list[float]]],
    reads: dict[str, dict[str, Any]],
    board: "nml_core.Board",
    objectives: list[list[float]],
    attached: dict[str, list[str]] | None = None,
    attached_to: dict[str, str] | None = None,
    reserved: set[str] | None = None,
    earliest: dict[str, int] | None = None,
) -> dict[str, Any]:
    """`_capture` (core_selfplay.gd:608-637) through `BattleSim.capture` and
    `BattleSim.state_to_plain(state, false)` — the plain state the search reads.

    Everything a live game would ask the `GameUnit` for comes from one of two
    places: the STATIC profile (`list_to_profile`) or the registry reads the
    Rust seam answers (`Core.capture_reads`). Nothing is defaulted silently."""
    us: dict[str, Any] = {}
    by_id = {u["unit_id"]: u for u in units}
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
            # `hero_attach="off"` (the default) is the M3-6b trainer: its OPRUnit
            # carries neither a selectionId nor a joinToUnit, so capture's
            # derivation finds none. `derive_attachment` fills these for
            # `hero_attach="table"` (NML-1073 D4).
            "attached": list(attached[key]) if attached is not None else [],
            "attached_to": attached_to[key] if attached_to is not None else "",
            "bands": {
                "advance": u["move_bands"]["advance"],
                "rush": u["move_bands"]["rush"],
            },
            "charge_no_difficult": r["charge_no_difficult"],
            # `_move_base_radius_of` act_recorder.gd:311-322, over
            # `SoloController._move_base_radius_m(_moving_models(u))` (:4735 /
            # :4915): the unit's own alive models PLUS its attached heroes',
            # floored at the shared default.
            #
            # NML-1127: this comment said "plus attached heroes" and the code
            # read the HOST's base alone. Inert while nothing joined — and no
            # longer, since NML-1105 gave the oracle a real attachment graph.
            # MEASURED on `m3_ref_v4` seed 27: three of thirteen units differ,
            # every one a host whose hero has the bigger base — `p2_1_zCo2G8c`
            # (Protector Sisters, 0.0125 m, floored to 0.016) carrying
            # `p2_0_BT_-pdh` at 0.02 m, recorded 0.02 and captured 0.016; same
            # for `p2_2_0Bc4px2` and `p1_3_njiIkJi`.
            #
            # LIMIT, deliberate and the same one `attached_hero_rules` carries:
            # the trainer stamps this ONCE at capture, while the recorder
            # re-stamps it per activation — so a hero that FALLS keeps its base
            # in the host's probe here. That is `state::ProfileDyn`'s rung.
            "charge_probe_r": max(
                [float(u["base_radius"]), DEFAULT_BASE_RADIUS_M]
                + [
                    float(by_id[h]["base_radius"])
                    for h in (attached or {}).get(key, ())
                    if h in by_id
                ]
            ),
        }
        if r["shroud"] is not None:
            us[key]["shroud"] = list(r["shroud"])
        if reserved is not None and key in reserved:
            # `BattleSim.capture`'s dormant arm (battle_sim.gd:1477-1489,
            # :1539-1544): ZERO table presence — no positions, no wounds, no
            # radii, `alive` already 0 — with the strength parked in
            # `dormant_*` for the arrival step and the earliest round it may
            # take. A tray node's position must never leak into the board
            # picture, which is why nothing here is a placeholder.
            us[key].update(
                wounds=[],
                dormant=True,
                dormant_models=int(u["model_count"]),
                dormant_wounds=list(u["wounds_max"]),
                earliest_arrival_round=(earliest or {}).get(key, 2),
            )
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


def load_board(
    seed: int, bank_dir: str | Path
) -> tuple["nml_core.Board", dict[str, Any], list]:
    """One banked school board — `tools/terrain_bank_dump.gd` writes both shapes
    `SchoolTerrain.generate(seed)` has: the act header's terrain object, and the
    `pieces` drawing list the result file carries as `terrain`.

    A bank written before `pieces` existed raises HERE rather than letting the
    result file carry a guessed drawing list."""
    path = Path(bank_dir) / ("board_%d.json" % seed)
    if not path.exists():
        raise FileNotFoundError(
            "no banked board for seed %d (%s) — run tools/terrain_bank_dump.gd" % (seed, path)
        )
    with open(path, encoding="utf-8") as f:
        board = json.load(f)
    if "pieces" not in board:
        raise KeyError(
            "banked board %s carries no `pieces` — re-run tools/terrain_bank_dump.gd "
            "(the result file's `terrain` is that drawing list and cannot be "
            "rebuilt from the header shape)" % path
        )
    return nml_core.board(board["terrain"]), board["terrain"], board["pieces"]


# ------------------------------------------------------------------- knobs ---

# `AiPlanner.ROLLOUT_TOP_K` / `.ROLLOUT_HORIZON_ROUNDS` ai_planner.gd:48/289 —
# the planner's own defaults, read by `top_k_default()` / `horizon()` (:52-56,
# :293-297) whenever `NML_TOP_K` / `NML_HORIZON` is unset.
ROLLOUT_TOP_K = 6
ROLLOUT_HORIZON_ROUNDS = 2


def _godot_int(s: str) -> int:
    """Godot's `int(String)`: a leading optional sign and digits, `0` when
    there is no such prefix — a non-numeric env value degrades to `0` rather
    than raising, exactly what `int(e)` does in ai_planner.gd:54/295."""
    m = re.match(r"^\s*([+-]?\d+)", s)
    return int(m.group(1)) if m else 0


def _env_knob(name: str, lo: int, hi: int, default: int) -> int:
    """`AiPlanner.top_k_default` / `.horizon` ai_planner.gd:49-56 / :290-297,
    ported (minus the `static var` cache, which only saves a repeated env
    read — the value cannot change mid-process either way): the env var
    UNSET (empty string) is the trainer's own default; SET is `int(e)` clamped
    to `[lo, hi]` — so e.g. `NML_TOP_K=0` clamps UP to `lo`, it is not a
    second way to ask for the default."""
    e = os.environ.get(name, "")
    if e == "":
        return default
    return max(lo, min(hi, _godot_int(e)))


def resolve_top_k(top_k: int | None) -> int:
    """`top_k`, else `NML_TOP_K` (ai_planner.gd:49-56), else `ROLLOUT_TOP_K`."""
    if top_k is not None:
        return top_k
    return _env_knob("NML_TOP_K", 1, 32, ROLLOUT_TOP_K)


def resolve_horizon(horizon: int | None) -> int:
    """`horizon`, else `NML_HORIZON` (ai_planner.gd:290-297), else
    `ROLLOUT_HORIZON_ROUNDS`."""
    if horizon is not None:
        return horizon
    return _env_knob("NML_HORIZON", 1, 3, ROLLOUT_HORIZON_ROUNDS)


#: `charge_gate` modes. "off" is `play_game`'s OWN default (unchanged — every
#: existing caller, replay and pinned-digest test stays byte-identical) and is
#: what the OLD planner-lane trainer does: `tools/core_selfplay.gd` never
#: stamps `state["charge_illegal"]`, so both planner menu sites read
#: `illegal_cb.is_valid()` as false (ai_planner.gd:1024/1308) and offer
#: charges the table would refuse. "table" wires the gate the ARENA wires —
#: `SoloController.charge_candidate_illegal` (solo_controller.gd:1450,
#: stamped at :3002/:3358/:3475/:3704) — through its pure twin
#: `gate::charge_illegal` (NML-1073 M2-0c), whose five inputs the capture
#: already carries per unit: `aircraft`, the rush `bands`, the melee `shroud`
#: pair, `charge_no_difficult` (the p.13 Strider/Flying exemption) and
#: `charge_probe_r` (the unit footprint), against the header board's difficult
#: ground. DEFECT_LEDGER row 2: the CLI (`main`, what a fresh self-play RUN
#: invokes — `nogodot_runner.sh` et al.) now defaults `--charge-gate` to
#: "table" instead, so a new teacher run started with no flag stops offering
#: charges the table would refuse; a direct `play_game(...)` caller (every
#: test and replay tool) is untouched.
CHARGE_GATE_MODES = ("off", "table")


def resolve_charge_gate(charge_gate: str) -> bool:
    """`charge_gate` as the crate's `Knobs.charge_gate` bit — the very thing the
    act line records per activation (act_recorder.gd:73) and the crate reads as
    `Tuning.charge_gate`. An unknown mode RAISES: a silently ungated trainer is
    what this rung exists to end."""
    if charge_gate not in CHARGE_GATE_MODES:
        raise ValueError(
            "charge_gate must be one of %s, not %r" % (list(CHARGE_GATE_MODES), charge_gate)
        )
    return charge_gate == "table"


#: `dice` modes. "expected" is the default and is what every corpus written
#: before this knob existed contains: no combat die at all, `sim.rs:148-174`
#: `apply_expected_wounds` filling wounds from a float EV. "table" is the rung
#: D1 builds — the shipped game's DICE TRAY, `_solo_tray_roll` in batch mode
#: (main.gd:7126-7180), drawn from a generator of its own that
#: `main.seed_tray_rng(_dice_seed)` seeds after deployment
#: (arena_match.gd:478), with `_dice_seed` defaulting to the game seed
#: (arena_match.gd:984-985).
#:
#: B3 SHIPS THE PLUMBING ONLY: the tray is built and seeded, the mode is
#: validated and stamped, and NOTHING reads the tray yet — so "table" plays
#: the identical game "expected" plays, byte for byte, and the two results
#: differ in exactly one string: `knobs["dice"]`. B4 (shooting) and B5 (melee)
#: add the consumers that deliberately break that.
DICE_MODES = ("expected", "table")

#: `objectives` modes (NML-1073 M5 D8a). "constant" is the default and is what
#: EVERY corpus written before this knob contains: the three hard-coded centre-line
#: markers `tools/core_selfplay.gd:177` and `tools/arena_match.gd:279` place, which
#: are identical in all 168 games of qbg_ref. "rulebook" runs the seeded generator
#: `core/nml-core/src/objectives.rs` mirrors from `scripts/solo/objective_layout.gd`:
#: D3+2 markers, a roll-off for the first placer, then alternating placement rejected
#: back to the book's constraints (outside both deployment zones, over 9" from every
#: other marker, off an impassable cell). The draw stream is a `GodotRng` seeded with
#: the LAYOUT seed — deliberately not the table's global RNG (the terrain layouter
#: consumes it a data-dependent number of times) and not `SoloController._rng`.
#: "doctrine" (NML-1140 step 9) keeps that draw for count and first placer — the
#: stream contract — and hands ONLY the candidate choice to `nml_core.doctrine_place`,
#: the twin's placement doctrine, which draws nothing. Which rung the doctrine
#: plays is a knob of its own. "mixed" (NML-1140 step 9b) splits that choice PER
#: SEAT — the placement A/B measures the doctrine's placement skill against the
#: rulebook draw in ONE game instead of a whole-board pair.
OBJECTIVES_MODES = ("constant", "rulebook", "doctrine", "mixed")

#: The doctrine rungs (design 5): "search" is the max^N mini-game the shipped
#: grade plays, "style" the middle rung without the eval. "random" needs no
#: knob — it IS "rulebook", the caller's own draw stream.
DOCTRINE_MODES = ("style", "search")


def resolve_doctrine_mode(doctrine_mode: str) -> str:
    """The validated `doctrine_mode`. An unknown rung RAISES: a stamp that claims
    a doctrine the game did not play is worse than no game."""
    if doctrine_mode not in DOCTRINE_MODES:
        raise ValueError(
            "doctrine_mode must be one of %s, not %r" % (list(DOCTRINE_MODES), doctrine_mode)
        )
    return doctrine_mode

def resolve_mixed_placement(doctrine_mode):
    """The per-seat placer spec `objectives="mixed"` plays: {"1": rung, "2": rung},
    "random" (the rulebook draw) allowed beside the doctrine rungs. A bare rung
    string means the doctrine sits seat 1 and the rulebook seat 2. Unknown words
    or shapes RAISE — the same rule every mode word here lives by."""
    spec = {"1": doctrine_mode, "2": "random"} if isinstance(doctrine_mode, str) else doctrine_mode
    if (
        not isinstance(spec, dict)
        or set(spec) != {"1", "2"}
        or set(spec.values()) - {"random", *DOCTRINE_MODES}
    ):
        raise ValueError(
            "mixed doctrine_mode must be a {'1': rung, '2': rung} dict with rung in %s, not %r"
            % (sorted({"random", *DOCTRINE_MODES}), doctrine_mode)
        )
    return spec


#: The catalog deployment style the harnesses play. Both `arena_match.gd` and
#: `core_selfplay.gd` deploy FRONT_LINE 12" zones, so the twin's legality test uses
#: the same polygons `assets/solo/deployments.json` gives that style.
FRONT_LINE_ZONES = {
    "zones": {
        "1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
        "2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]],
    }
}


def resolve_objectives(objectives: str) -> str:
    """The validated `objectives` mode. An unknown mode RAISES: a corpus whose file
    claims a rulebook layout while it played the three constants is worse than none."""
    if objectives not in OBJECTIVES_MODES:
        raise ValueError(
            "objectives must be one of %s, not %r" % (list(OBJECTIVES_MODES), objectives)
        )
    return objectives


def resolve_dice(dice: str) -> str:
    """The validated `dice` mode. An unknown mode RAISES rather than falling
    back to "expected": a corpus that silently recorded expected-value combat
    while its file claimed table dice is worse than no corpus."""
    if dice not in DICE_MODES:
        raise ValueError("dice must be one of %s, not %r" % (list(DICE_MODES), dice))
    return dice


_MISSION_CATALOG_CACHE: dict[str, dict[str, Any]] = {}


def resolve_mission(mission: str, repo_root: str | Path) -> dict[str, Any]:
    """The `assets/solo/missions.json` entry for `mission`; an unknown id
    RAISES rather than falling back to duel the way the table does."""
    catalog = _MISSION_CATALOG_CACHE.get(str(repo_root))
    if catalog is None:
        path = Path(repo_root) / "assets" / "solo" / "missions.json"
        catalog = json.loads(path.read_text(encoding="utf-8"))["missions"]
        _MISSION_CATALOG_CACHE[str(repo_root)] = catalog
    if mission not in catalog:
        raise ValueError("mission must be one of %s, not %r" % (sorted(catalog), mission))
    return catalog[mission]


def resolve_charge_landing(charge_landing: str) -> bool:
    """`charge_landing` as the bit `play_game` branches on. An unknown mode
    RAISES for the same reason `resolve_dice` does: a corpus whose header claims
    a rung it did not play is worse than no corpus."""
    if charge_landing not in CHARGE_LANDING_MODES:
        raise ValueError(
            "charge_landing must be one of %s, not %r"
            % (list(CHARGE_LANDING_MODES), charge_landing)
        )
    return charge_landing == "table"


def resolve_movement(movement: str) -> bool:
    """`movement` as the bit `play_game` branches on. An unknown mode RAISES for
    the same reason `resolve_charge_landing` does."""
    if movement not in MOVEMENT_MODES:
        raise ValueError("movement must be one of %s, not %r" % (list(MOVEMENT_MODES), movement))
    return movement == "table"


def charge_illegal_stamp(core, state) -> dict[str, bool]:
    """What THIS trainer stamps into `state["charge_illegal"]`, in the shape
    `AiActRecorder._charge_illegal_matrix` records (act_recorder.gd:204-222):
    `"attacker|victim" -> bool` for every ordered pair of alive opposite-side
    units at that pair's root gap. `{}` when the trainer runs `charge_gate=off`,
    which is exactly what the recorder writes for a caller whose Callable is
    invalid."""
    return core.charge_illegal_matrix(state)


#: `hero_attach` modes. "off" is the default and is what every corpus written
#: before this knob has: `tools/core_selfplay.gd` hands each unit a blank
#: `OPRApiClient.OPRUnit` whose `selection_id` / `join_to_unit` are unset
#: (M3-6b left them so deliberately), so `BattleSim.capture`'s NML-1081
#: derivation finds nothing and no hero is ever joined. "table" reads the two
#: fields off the Army-Forge list the way the table does and derives
#: `attached` / `attached_to` from them (`derive_attachment`), plus the one
#: PROFILE field that follows from attachment: `attached_hero_rules`, the alive
#: attached heroes' own rules, which is what `AiEv.rule_on_all_models`
#: (ai_ev.gd:79-83) quantifies over before a unit-wide rule may fire.
#:
#: LIMIT, deliberate: the trainer stamps the header profile once, at deployment,
#: and never rewrites it per activation the way `BattleSim.unit_profile_dyn`
#: does — so a hero that FALLS keeps voting here. That is the gap
#: `state::ProfileDyn` exists for and it belongs to a later rung, not to D4.
#:
#: "join" (NML-1127) is the middle mode, and it is what `tools/core_selfplay.gd`
#: has PLAYED since NML-1105: the roster JOIN without the activation FOLD. The
#: two are separate things on the table and the oracle records them separately —
#: the join is the GameUnit graph (`OPRArmyManager.attach_joined_heroes_of`),
#: which reaches the corpus as every host's `attached` / `attached_to` and
#: `attached_hero_rules`; the fold is `BattleSim.hero_fold`, which the harness
#: never sets, so its header stamps `hero_attach: false` while its states carry
#: attachment on every host. "off" and "table" could not describe that game
#: between them, which is why every M3 gate read 0/N against the v4 oracle.
HERO_ATTACH_MODES = ("off", "join", "table")

#: `charge_landing` modes (NML-1073 M5 D5-1). "off" is the default and is every
#: corpus written before this knob: a charge that lands within `MELEE_ENGAGE_IN`
#: of the target's base edge always fights. "table" adds the SECOND question the
#: shipped game asks — `main._run_ai_melee` (main.gd:8015-8022) hands the
#: residual base gap to `snap_charge(unit, target, last_move_remaining_in())`
#: (solo_controller.gd:8632-8657) and takes a NEGATIVE answer as "the charge
#: falls short, no fight": the snap is movement and must fit the move budget the
#: charge left over. On the 168-game reference that gate alone accounts for 53
#: of the 116 recorded charges the table never fought.
CHARGE_LANDING_MODES = ("off", "table")

#: `movement` modes (NML-1073 M5 D5-2). "rigid" is the default and is every
#: corpus written before this knob: a CHARGE translates the whole unit rigidly
#: toward the planner's `dest`, clamped to the band. "table" runs the table's
#: own charge move instead — `_charge_move` aims at the target's contact
#: boundary (solo_controller.gd:8582) and the M4 movement port solves the
#: per-model, arc-budgeted route around walls and terrain, so the arc the D5-1
#: engage gate subtracts is the arc the table actually walked.
MOVEMENT_MODES = ("rigid", "table")

#: `sighting` modes (NML-1073 M5 D6a-B4). "unit" is the default and is every
#: corpus written before this knob: `BattleSim._profiles_of`
#: (battle_sim.gd:714-749) fires the WHOLE unit. "model" is the table's own
#: rule (`main._run_ai_shooting` :3131-3134, GF Advanced Rules v3.5.1 p.8) —
#: per (member, weapon), only the models with both range and line of sight.
#: The crate has carried the header knob since D6a-B4 (`acts::Sighting`); this
#: is the trainer's way of reaching it, so a Godot-free corpus can be written
#: at the same sighting fidelity a recorded one is replayed at.
SIGHTING_MODES = ("unit", "model")


def resolve_sighting(sighting: str) -> str:
    """The validated `sighting` mode, as the header spells it. An unknown mode
    RAISES for the same reason `resolve_dice` does: a corpus whose header
    claims a rung it did not play is worse than no corpus."""
    if sighting not in SIGHTING_MODES:
        raise ValueError(
            "sighting must be one of %s, not %r" % (list(SIGHTING_MODES), sighting)
        )
    return sighting


#: `los` modes (NML-1160). "unit" is the default and every corpus written
#: before this knob: `capture` stamps `los_pairs` from `SchoolTerrain.
#: los_blocked` (`tools/core_selfplay.gd:675`), a unit-CENTRE to unit-CENTRE
#: probe, and fills NO per-unit `los` — so `AiPlanner._best_shoot`'s only sight
#: test (`BattleSim.sees`, which reads an absent row as "sees everything")
#: never refuses a target and `BattleSim.resolve` drops the volley one layer
#: later on the coarse matrix instead. An ARENA recording is the other way
#: round: `BattleSim.capture` fills `los` per unit from `SoloController.
#: _has_los` (`_solo_sighted_count(s, t, 9999) > 0`, main.gd:2338 — ANY model
#: of the shooter with a sight line to ANY model of the target) and stamps no
#: matrix at all. "model" gives the trainer the arena's answer on BOTH seams,
#: re-stamped once per played activation exactly as `capture` re-runs the
#: sweep, and the search underneath inherits it the way `clone_state` does.
LOS_MODES = ("unit", "model")


def resolve_los(los: str) -> bool:
    """`los` as the crate's `Knobs.los_model` bit. An unknown mode RAISES for
    the same reason `resolve_sighting` does: a corpus whose header claims a
    sight fidelity it did not play is worse than no corpus."""
    if los not in LOS_MODES:
        raise ValueError("los must be one of %s, not %r" % (list(LOS_MODES), los))
    return los == "model"
#: `menu_los` modes (NML-1161). "planner" is the default and every corpus
#: written before this knob: `AiPlanner._best_shoot` (ai_planner.gd:1372-1385)
#: filters targets on `BattleSim.sees` ALONE, while `BattleSim.resolve`
#: (:770-773) ANDs `sees` with `_los_clear`. On the TABLE the two agree, because
#: no real game stamps `state["los_blocked"]` and `_los_clear` is then true for
#: every pair. In SELF-PLAY they do not: `tools/core_selfplay.gd:675` stamps it,
#: so the menu offers shots the resolve silently drops — and a dropped volley
#: leaves a state bit-identical to plain HOLD, which the eval scores equal and
#: the argmax's first-wins tie-break hands to the do-nothing. "resolve" makes
#: the menu ask the resolve's whole question, so an unexecutable shot is never
#: offered as a tie with HOLD.
MENU_LOS_MODES = ("planner", "resolve")


def resolve_menu_los(menu_los: str) -> bool:
    """`menu_los` as the crate's `Knobs.menu_los` bit, which `plan::tuning_of`
    hands the menu as `Tuning::shoot_los`. An unknown mode RAISES for the same
    reason `resolve_charge_gate` does: a silently ungated menu is worse than
    no corpus."""
    if menu_los not in MENU_LOS_MODES:
        raise ValueError(
            "menu_los must be one of %s, not %r" % (list(MENU_LOS_MODES), menu_los)
        )
    return menu_los == "resolve"


#: `menu_wide` modes (W1, AUDIT_rulebook_flanks_2026-09-02 top-1). "off" is the
#: default and every corpus written before this knob: `menu::candidates` hangs
#: every shoot target on HOLD, so the search can only fire by STANDING STILL,
#: while `sim::resolve` has always fired a volley for ADVANCE too. "table" is
#: the TABLE's own answer — `AiPlanner.candidates_wide` (ai_planner.gd:
#: 1145-1157) has offered ADVANCE-then-shoot since 16.08., added because "the
#: policy could fire only by standing still ... it moved and stopped fighting".
MENU_WIDE_MODES = ("off", "table")


def resolve_menu_wide(menu_wide: str) -> bool:
    """`menu_wide` as the crate's `Knobs.menu_wide` bit, which `plan::tuning_of`
    hands the menu as `Tuning::wide_shoot`. An unknown mode RAISES for the same
    reason `resolve_menu_los` does."""
    if menu_wide not in MENU_WIDE_MODES:
        raise ValueError(
            "menu_wide must be one of %s, not %r" % (list(MENU_WIDE_MODES), menu_wide)
        )
    return menu_wide == "table"


#: `deployment` modes (NML-1152 step 8). "zone" is the default and is every
#: corpus written before this knob: the twin's own 12"-zone even spread
#: (`deploy_zone`, core_selfplay.gd:593-606), roll-off AFTER deployment, P1
#: winning ties. "arena" plays the TABLE's pre-game instead: roll-off FIRST
#: from the game stream with ties re-rolled, winner-first finish order, and
#: the Rust `deploy_side`/`deploy_finish` pipeline (design §3.2-3.3).
#: "interleaved" is "arena" plus the RULEBOOK's turn order (GF v3.5.1 p.6): the
#: roll-off winner places ONE unit, the opponent places one, alternating to the
#: end, Scouts in their own phase after both armies' normals, Ambush reserved —
#: `deploy_interleaved` instead of two whole-side `deploy_side` calls. Every
#: draw, spot and settle stays what "arena" produces (each side scores against
#: its OWN occupied); what changes is the cross-side ORDER, recorded as
#: `placement_sequence`.
DEPLOYMENT_MODES = ("zone", "arena", "interleaved")

#: `ambush` modes (SPEC_rule_ambush_arrival_2026-09-02 S3b). "off" is the
#: default and is every corpus written before this knob: a unit set aside by
#: `deploy_side` as `reserved` sits off-table for the whole game and never
#: acts, which is the residual `_deploy_arena`'s docstring has been declaring
#: since step 8. "table" plays the rule — a reserve unit enters the snapshot
#: DORMANT with its strength parked (battle_sim.gd:1477-1489, :1539-1544) and
#: ARRIVES at a round start from `earliest_arrival_round` on, through
#: `deployment::arrive_one` (main.gd:10096-10106, :10419-10485). The knob
#: exists because turning it on moves every arena game that owns an ambusher,
#: and a corpus recorded at one fidelity must never be replayed at another.
AMBUSH_MODES = ("off", "table")

#: `AMBUSH_BEACON_RADIUS_IN` (solo_controller.gd:9766) in metres. The registry
#: fields no `Ambush Beacon` entry at all (grepped, five books, zero hits), so
#: `beacon_radius_m`'s `unit_param` would return this fallback for every
#: carrier anyway — the `HIT_AND_RUN_MOVE_IN` precedent: a constant, named,
#: with the reason it is one.
AMBUSH_BEACON_RADIUS_M = 6.0 * IN2M


def resolve_ambush(ambush: str) -> bool:
    """`ambush` as the bit `play_game` branches on. An unknown mode RAISES for
    the same reason `resolve_dice` does."""
    if ambush not in AMBUSH_MODES:
        raise ValueError("ambush must be one of %s, not %r" % (list(AMBUSH_MODES), ambush))
    return ambush == "table"


def _arrive_reserves(plain, reads, board, objectives, opener: int, round_no: int) -> int:
    """The table's round-start ambush beat (`main._solo_round_start` :10096-10106
    through `_solo_alternate_ambush_arrivals` :10419-10485), over the PLAIN
    state — the same layer `_round_start` already works on.

    Players ALTERNATE, starting with the player that activates next (GF v3.5.1
    p.13, main.gd:10419-10424), ONE unit per turn (:10453). The arrival zone is
    the WHOLE table (:10428-10431), `occupied` seeds from every live model of
    BOTH sides at `radius + 0.005` m (`occupied_from_live_bases` :10196-10214),
    and a unit with no legal spot simply stays in reserve for a later round
    (:10019, :10091) — it is never force-placed.

    Arriving is DEPLOYMENT, not an activation: `activated` stays False, so the
    unit can act the same round (`_finish_reserve_arrival` :10118-10123). The
    `ambush_arrived_round` stamp is what stops it seizing or contesting this
    round (`score.rs:60`, `:74-93`). Returns how many units arrived.
    """
    units = plain["units"]
    zone = [-TABLE_W_IN * IN2M / 2.0, -TABLE_D_IN * IN2M / 2.0, TABLE_W_IN * IN2M, TABLE_D_IN * IN2M]
    objs = [[o[0], o[2]] for o in objectives]
    live = [(k, u) for k, u in units.items() if not u.get("dormant") and u["positions"]]
    occ = [
        {"pos": [p[0], p[2]], "radius": r + 0.005}
        for _, u in live
        for p, r in zip(u["positions"], u["radii"])
    ]
    queue = {1: [], 2: []}
    for key, u in units.items():
        if u.get("dormant") and u.get("earliest_arrival_round", -1) <= round_no:
            queue[int(u["player"])].append(key)
    turn, arrived = int(opener), 0
    while queue[1] or queue[2]:
        if not queue[turn]:
            turn = 3 - turn
            continue
        key = queue[turn].pop(0)
        turn = 3 - turn
        u = units[key]
        r = reads[key]
        side = int(u["player"])
        # A RESERVE enemy projects nothing (main.gd:10523); a reserve beacon
        # carrier likewise stands nowhere (`beacon_points` :9781+).
        enemies = [
            {"pos": [p[0], p[2]], "min_dist_m": reads[k]["repel_m"], "pad_m": rr}
            for k, ou in live
            if int(ou["player"]) != side
            for p, rr in zip(ou["positions"], ou["radii"])
        ]
        beacons = [
            {"pos": [p[0], p[2]], "radius_m": AMBUSH_BEACON_RADIUS_M}
            for k, ou in live
            if int(ou["player"]) == side and reads[k]["beacon"]
            for p in ou["positions"]
        ]
        spot = nml_core.arrive_one(
            zone, objs, occ, enemies, r["ring_m"], r["radius"], r["footprint"],
            r["base_r"], r["flying"], board, beacons,
        )
        if spot is None:
            continue
        n = int(u.get("dormant_models", 0))
        models = nml_core.place_models((spot[0], spot[1]), n)
        u["positions"] = [[f32(m[0]), 0.0, f32(m[1])] for m in models]
        u["wounds"] = list(u.get("dormant_wounds", []))
        u["radii"] = [r["base_r"]] * n
        u["alive"] = n
        u["dormant"] = False
        u["ambush_arrived_round"] = round_no
        for gone in ("dormant_models", "dormant_wounds", "earliest_arrival_round"):
            u.pop(gone, None)
        occ.append({"pos": spot, "radius": r["radius"]})
        live.append((key, u))
        arrived += 1
    return arrived



def resolve_deployment(deployment: str) -> str:
    """The validated `deployment` mode. An unknown mode RAISES for the same
    reason `resolve_dice` does: a corpus whose header claims a rung it did not
    play is worse than no corpus."""
    if deployment not in DEPLOYMENT_MODES:
        raise ValueError(
            "deployment must be one of %s, not %r" % (list(DEPLOYMENT_MODES), deployment)
        )
    return deployment


def resolve_hero_attach(hero_attach: str) -> bool:
    """The FOLD bit — `Seams::hero_attach` (io.rs) and the header's own
    `hero_attach` key. An unknown mode RAISES: a trainer that silently ignored
    the mode would write a corpus whose header claims a rule it did not play."""
    if hero_attach not in HERO_ATTACH_MODES:
        raise ValueError(
            "hero_attach must be one of %s, not %r" % (list(HERO_ATTACH_MODES), hero_attach)
        )
    return hero_attach == "table"


def hero_join(hero_attach: str) -> bool:
    """The JOIN bit — whether `derive_attachment` runs at all. "join" and
    "table" both join; only "table" also folds (see `HERO_ATTACH_MODES`)."""
    if hero_attach not in HERO_ATTACH_MODES:
        raise ValueError(
            "hero_attach must be one of %s, not %r" % (list(HERO_ATTACH_MODES), hero_attach)
        )
    return hero_attach != "off"


def hero_attach_of_corpus(acts_path) -> str:
    """The `hero_attach` MODE a recorded act corpus was played with, read off
    the corpus itself — a recording is self-describing and a gate should not
    have to be told twice.

    The header's `hero_attach` key is the FOLD alone (`act_recorder.gd:176`,
    stamped from `BattleSim.hero_fold_enabled()`). The JOIN shows up one line
    lower: the first act's state carries a non-empty `attached_to` on every
    joined hero. A corpus recorded before NML-1105 has neither and reads "off".
    """
    with open(acts_path, encoding="utf-8") as fh:
        header = json.loads(fh.readline())
        first = fh.readline()
    if bool(header.get("knobs", {}).get("hero_attach", False)):
        return "table"
    if not first.strip():
        return "off"
    units = json.loads(first).get("state", {}).get("units", {})
    return "join" if any(u.get("attached_to") for u in units.values()) else "off"


def vocab_version_of_corpus(acts_path) -> int:
    """NML-1134 — the RULE VOCABULARY version a recorded act corpus was slotted
    with, read off its own header. Same spirit as `hero_attach_of_corpus`: a
    recording is self-describing.

    The rule itself lives in ONE place, `nml_core.vocab_version_of_header`
    (core/nml-core/src/acts.rs) — the header's `knobs.rule_vocab_version` when it
    carries one, else version 2, because every corpus cut before the stamp
    existed was cut under version 2. This function only opens the file."""
    with open(acts_path, encoding="utf-8") as fh:
        return nml_core.vocab_version_of_header(json.loads(fh.readline()))


def resolve_vocab_version(flag, acts_paths):
    """`flag` verbatim (an int), unless it is "auto" — then the FIRST readable
    act corpus in `acts_paths` decides, exactly the way `resolve_hero_attach_mode`
    resolves its own. No readable corpus at all reads THIS BUILD's version, which
    is what a freshly played game is slotted with. Returns `(version, source)` so
    a gate can SAY which file decided."""
    if flag != "auto":
        return int(flag), None
    for path in acts_paths:
        if path is not None and Path(path).is_file():
            return vocab_version_of_corpus(path), str(path)
    return nml_core.RULE_VOCAB_VERSION, None


def resolve_hero_attach_mode(mode: str, acts_paths) -> str:
    """`mode` verbatim, unless it is "auto" — then the FIRST readable act corpus
    in `acts_paths` decides, because one reference directory is one recording
    session and one mode. No readable corpus at all reads "off", which is what
    every corpus written before NML-1105 is. Returns `(mode, source_path)` so
    the caller can SAY which file decided instead of asserting a mode."""
    if mode != "auto":
        return mode, None
    for path in acts_paths:
        if path is not None and Path(path).is_file():
            return hero_attach_of_corpus(path), path
    return "off", None


# `AiActRecorder._header_line` act_recorder.gd:144-150 resolves these from the
# planner's class statics; `tools/core_selfplay.gd` runs them at their defaults
# with NML_SIM_SPACING on and NML_SIM_CAST off, which is what a recorded header
# of this trainer says. `charge_gate` is the M3-5 addition, false HERE because
# that is the gateless default `tools/core_selfplay.gd` has: both menu sites
# then skip the gate outright. `play_game(charge_gate="table")` overrides it in
# its own per-game copy (D2) — see `CHARGE_GATE_MODES`.
# `top_k` / `horizon` here are the PLANNER's own defaults — a game recorded
# with a different mode (e.g. the OLD training corpus's
# `NML_TOP_K=2 NML_HORIZON=1`, farm/mass_wave_template.sh:9) goes through
# `play_game(top_k=..., horizon=...)`, which builds its OWN per-game copy of
# this dict (`resolve_top_k` / `resolve_horizon`) rather than mutating it.
TRAINER_KNOBS = {
    "top_k": ROLLOUT_TOP_K,
    "horizon": ROLLOUT_HORIZON_ROUNDS,
    "tail_cap_p1": 0,
    "tail_cap_p2": 0,
    "imagined_round_end": True,
    "depth_discount": 0.5,
    "seat_mode": 0,
    "playout_margin": 0.02,
    "playout_rich": True,
    "seam_cast": False,
    # NML-1157: a combat intent aimed at a JOINED HERO resolves to its HOST
    # (GF v3.5.1 p.14, `main._solo_combat_unit`). False here because the
    # RECORDED reference bundles were produced by the table, which lets wounds
    # land on the hero — 352 of qbg_ref+qag_ref's 16043 acts name one — so a
    # bundle replayed with the rule ON would part from its own dice.
    "hero_last": False,
    # NML-1157: the CASTER is read off the activating chain, not off the host
    # alone. False is the crate's default and what every earlier corpus carries.
    # Turning `seam_cast` on WITHOUT this still casts nothing: `Caster(X)` is a
    # hero rule and a joined hero never activates on its own.
    "cast_fold": False,
    "seam_spacing": True,
    "seam_path": False,
    "charge_gate": False,
    "menu_targets": False,
}

# `AiActRecorder.begin` :65-66 — the planner's per-activation class statics, all
# at their defaults in a trainer process. `fit_mode` is the ONE that a caller can
# move (NML-1142): it is `AiMissionEval.fit_mode`, the `eval_fit` bit of the
# `planner_v1`/`planner_v2` presets (solo_difficulty.gd:97/:109), and it is on
# for exactly as long as a net is armed on the core — see `_pick_for`.
TRAINER_STATICS = {
    "opener_seat": False,
    "playout_search": False,
    "fit_mode": False,
    "playout_net": {},
}

# NML-1158c — the exploration knob's OWN stream, seeded per activation as
# `game_seed * EXPLORE_SEED_STRIDE + seq`, the same shape as the sidecars'
# `PAIR_SEED_STRIDE` below but for a stream that feeds the PLAYED pick rather
# than a counterfactual clone. It is a stride of its own, disjoint from
# `PAIR_SEED_STRIDE` / `FORK_SEED_STRIDE`, so the three derived-seed families
# stay visually distinct in this file even though each seeds an independent
# `GodotRng` object and none can observe another's draws.
EXPLORE_SEED_STRIDE = 700001
# Expert-iteration step 2 — the playout-cap coin's own per-activation stream,
# `game_seed * CAP_SEED_STRIDE + seq`: a stride of its own, disjoint from every
# other derived-seed family here, so no stream can observe another's draws.
CAP_SEED_STRIDE = 700003


# ------------------------------------------------------------------- game ----


def _pick_for(
    core, state, player: int, net_player: int = 0, eps: float = 0.0, explore_seed: int = 0,
    cands: bool = False, cand_logits_fn: dict[int, Any] | None = None,
    policy_mode: str | None = None,
) -> dict[str, Any]:
    """`_pick_for` core_selfplay.gd:398-459 — the full planner for whichever side
    still has a living, un-activated unit; `{}` when the side is dry.

    The pool is the PLANNER's own filter (:431-436, player / activated / alive)
    unless the header's `hero_attach` FOLD seam is on. NML-1127: reading that
    seam here rather than folding unconditionally is what lets the harness play
    the oracle's "joined but not folded" game — see `HERO_ATTACH_MODES`.

    `eps` / `explore_seed` are the NML-1158c exploration knob, passed straight
    through to `Core.plan_with_rollout` — see `play_game`'s docstring and
    `EXPLORE_SEED_STRIDE` for where `explore_seed` comes from.

    `cands` is the expert-iteration opt-in (step 1): the binding then stamps
    `trace.cands` — the built candidates' content, build index order, joined
    by `trace.scored`'s `idx` — and writes nothing it did not write before.

    `cand_logits_fn` / `policy_mode` are the R4 seam at the harness boundary
    (NML-1164, DESIGN_policy_player §6): `{side: fn(state, menu, side) ->
    list[float] | None}`. A `player` with NO entry never makes any extra call
    and is byte-identical to before this seam existed. One WITH an entry
    always pays for one THROWAWAY `plan_with_rollout(cands=True)` call to name
    the exact menu the real search will score — Phase 0/1 (menu build) never
    depends on `top_k`/`horizon`, so this costs one shallow prefilter, not a
    second deep search — and hands it to the hook (one forward pass). A
    non-`None` result becomes `cand_logits` on the REAL call below; `None`
    (the hook declining for this one activation) discards the throwaway call
    and falls through to the plain call, same as no entry at all."""
    if not state.pool(player, bool(core.knobs().get("hero_attach", True))):
        return {}
    # NML-1142: `AiMissionEval.fit_mode` is per-ACTIVATION on the table and the
    # net is per-PROCESS, so the crate makes the caller say both. A trainer that
    # armed a net plays every activation with it — unless `net_player` names ONE
    # seat, which is the A/B seam described in `play_game`.
    fit = core.has_net() and net_player in (0, player)
    statics = dict(TRAINER_STATICS, fit_mode=True) if fit else TRAINER_STATICS
    hook = (cand_logits_fn or {}).get(player)
    logits = None
    if hook is not None:
        menu_pick = core.plan_with_rollout(state, player, statics, cands=True)
        if not menu_pick.get("used"):
            return {}
        logits = hook(state, menu_pick["trace"]["cands"], player)
    extra = {"cand_logits": logits, "policy_mode": policy_mode} if logits is not None else {}
    pick = core.plan_with_rollout(
        state, player, statics, eps=eps, explore_seed=explore_seed, cands=cands, **extra
    )
    return pick if pick.get("used") else {}


@contextlib.contextmanager
def forced_picks(fn):
    """Arm `fn` as `_pick_for` for the `with` block only, restoring whatever was
    armed before on the way out — including on an exception. A tool that wants
    every activation FORCED (the Gen-0 replay proofs, the shard exporter, the
    narrator) must go through this rather than assigning `_pick_for` bare: a
    bare assignment never restores, so it disarms the real planner for every
    game-playing test that runs later in the same process."""
    global _pick_for
    previous, _pick_for = _pick_for, fn
    try:
        yield
    finally:
        _pick_for = previous


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


def _shift_pieces(pieces: list, cells: int) -> list:
    """The terrain RED PROOF and nothing else: every drawn piece's centre moved
    `cells` 3" cells along +x. `0` returns the banked list unchanged, which is
    what every real game writes."""
    if not cells:
        return pieces
    out = []
    for p in pieces:
        q = list(p)
        q[1] = q[1] + cells * 3.0
        out.append(q)
    return out


# ------------------------------------------------------------------- magic ---


def _magic_init(units: list[dict[str, Any]], books: dict[str, list[float]]) -> dict[str, Any]:
    """`_magic_init` core_selfplay.gd:34-56 — the per-side seed counters, read
    off the BUILT rosters before any activation. `casts_current` at that point is
    `initialize_caster_points` (game_unit.gd:419-422), i.e. the profile's
    `caster_value` when positive, which is exactly what `capture` writes.

    `books_resolved` asks `SpellsRegistry.spells_for_unit` — a (system, faction)
    lookup that is NOT gated on Caster(X); the token test in front of it is."""
    magic: dict[str, Any] = {
        "granted": {"p1": 0, "p2": 0},
        "casters": {"p1": 0, "p2": 0},
        "books_resolved": {"p1": 0, "p2": 0},
        "casts": {"p1": 0, "p2": 0},
        "tokens_spent": {"p1": 0, "p2": 0},
        "caster_activations": {"p1": 0, "p2": 0},
        "in_range_activations": {"p1": 0, "p2": 0},
        "spells_by_kind": {
            "p1": {"damage": 0, "buff": 0, "debuff": 0},
            "p2": {"damage": 0, "buff": 0, "debuff": 0},
        },
    }
    for u in units:
        # `capture` (:189) reads the side off the unit id, and `_magic_init`
        # walks the two BUILT rosters — the same split, from the same place.
        key = "p1" if str(u["unit_id"]).startswith("p1_") else "p2"
        tokens = max(int(u["caster_value"]), 0)
        magic["granted"][key] += tokens
        if tokens > 0:
            magic["casters"][key] += 1
            if books.get(u["unit_id"]):
                magic["books_resolved"][key] += 1
    return magic


def _chain_casts(state, chain: dict[int, list[int]] | None, actor: int) -> int:
    """NML-1157 — the activating CHAIN's cast tokens: the acting unit plus its
    joined heroes. `Caster(X)` is a hero rule and a joined hero never activates
    on its own, so under `cast_fold` the pool that shrinks is the HERO's slot;
    reading the actor's alone booked every such cast as no cast at all."""
    c = state.casts()
    return sum(c[i] for i in chain[actor]) if chain is not None else c[actor]


def _magic_tally(magic: dict[str, Any], side_key: str, before: int, after: int) -> None:
    """`_magic_tally` core_selfplay.gd:66-69 — a POSITIVE token delta across the
    one PLAYED apply is the activation's cast event. The pair/fork resolves run
    on clones and never reach this call."""
    delta = before - after
    if delta > 0:
        magic["casts"][side_key] += 1
        magic["tokens_spent"][side_key] += delta


def _spells_by_kind_tally(
    magic: dict[str, Any], side_key: str, kinds: list[str], frm: int
) -> None:
    """`_spells_by_kind_tally` core_selfplay.gd:74-81 — the KINDS this
    activation stamped into the round's cast log, counted from the pre-apply
    mark. A kind the counter does not carry is skipped, exactly as the
    GDScript's `by_kind.has(kind)` does."""
    by_kind = magic["spells_by_kind"][side_key]
    for kind in kinds[max(frm, 0):]:
        if kind in by_kind:
            by_kind[kind] += 1


def _magic_eligibility_tally(
    magic: dict[str, Any], side_key: str, state, actor: int, max_range_in: float
) -> None:
    """`_magic_eligibility_tally` core_selfplay.gd:109-131 — the DENOMINATOR
    behind `casts`: how often a token-bearing unit activated at all, and how
    often it did so with a living enemy inside its longest spell range. Read
    PRE-apply, the same instant `casts_before` is read."""
    if state.casts()[actor] <= 0:
        return
    magic["caster_activations"][side_key] += 1
    if max_range_in <= 0.0:
        return
    if state.enemy_within(actor, max_range_in):
        magic["in_range_activations"][side_key] += 1


def _round_start(
    plain: dict[str, Any],
    round_no: int,
    by_key: dict[str, dict],
    magic: dict[str, Any] | None = None,
) -> int:
    """`_play_one`'s per-round reset (core_selfplay.gd:190-206): the round number,
    the round's EMPTY cast log, the expired spell modifiers
    (`BattleSim.reset_round_mods`), the activation and fatigue flags, and — from
    round 2 — the Caster(X) refill.

    Returns the tokens granted this round, and books them per side into `magic`
    when one is given — `_refill_round_caster_points` (:100) does exactly that."""
    plain["round"] = round_no
    plain["cast_events"] = []
    granted = 0
    for key, u in plain["units"].items():
        u["mods"] = dict(u.get("mods_base", ZERO_MODS))
        u["activated"] = False
        u["fatigued"] = False
        if round_no >= 2:
            got = _refill_round_caster_points(u, by_key[key])
            granted += got
            if magic is not None:
                magic["granted"]["p%d" % int(u["player"])] += got
    return granted


def _aux_alive_wounds(state, profiles: dict[str, dict]) -> dict[str, Any]:
    """The KataGo-style AUX targets (expert-iteration step 2) at ONE point in
    the game: models alive per side (`State.alive_models`) and wounds taken
    per side — the profile's per-model `wounds_max` total minus what the plain
    state still carries, a dead (or routed, wounds-cleared) unit therefore
    counting its full health. Monotone as the game grinds on, which is what
    the value head's aux loss wants."""
    alive = state.alive_models()
    wounds = {"p1": 0, "p2": 0}
    for key, u in state.plain()["units"].items():
        wounds["p%d" % int(u["player"])] += (
            sum(profiles[key]["wounds_max"]) - sum(u["wounds"])
        )
    return {"alive": {"p1": int(alive[0]), "p2": int(alive[1])}, "wounds": wounds}


# ---------------------------------------------------------------- sidecars ---

# `tools/core_selfplay.gd:262-268` and `:309-318` — the three log-local dice
# formulas, written once here because a guessed seed is a silent lie.
PAIR_SEED_STRIDE = 100000
PAIR_RUNNER_OFFSET = 50000
FORK_SEED_STRIDE = 1000003
FORK_RUNNER_OFFSET = 500011
FORK_REP_STRIDE = 70001
# `NML_FORK_SALT` (core_selfplay.gd:304-306) shifts ONLY the fork dice.
FORK_REPS = 3


def _local_rng(seed: int, skip: int) -> "nml_core.Rng":
    """One sidecar generator. `skip` is the RED PROOF knob and nothing else: it
    advances the stream by that many draws before the clone is resolved, so the
    seeds, the clone points and the played game all stay exactly as they were and
    the ONLY thing that moved is which dice the counterfactual saw."""
    r = nml_core.Rng(seed)
    for _ in range(max(skip, 0)):
        r.randf()
    return r


def _fork_run_activations(core, state, turn: int, frng) -> tuple[Any, int]:
    """`_fork_run_activations` core_selfplay.gd:402-419 — the bare alternation of
    a fork branch. Both branches step with the SAME cheap policy, which is what
    keeps the outcome DELTA a fair comparison (and the fork near-free)."""
    last = 0
    guard = state.units * 2 + 4
    while guard > 0:
        guard -= 1
        action = core.policy_step(state, turn, True)
        if action is None:
            other = 2 if turn == 1 else 1
            action = core.policy_step(state, other, True)
            if action is None:
                break
            turn = other
        state = core.resolve_stochastic_rng(state, action, frng)
        last = turn
        turn = 2 if turn == 1 else 1
    return state, last


def _fork_playout(core, pre_state, action, turn: int, round_no: int, owners0, frng):
    """`_fork_playout` core_selfplay.gd:363-396 — play ONE branch (this action
    from this pre-pick state) to GAME END on clones and report the final marker
    count per side.

    The VP ledger the GDScript keeps here is deliberately not kept: it computes
    `vp` round by round and then returns the MARKERS ("fork labels score like the
    mission — END for Face-Off"), so the ledger is dead weight in both."""
    owners = list(owners0)
    state = core.resolve_stochastic_rng(pre_state, action, frng)
    next_turn = 2 if turn == 1 else 1
    state, last = _fork_run_activations(core, state, next_turn, frng)
    opener = (2 if last == 1 else 1) if last != 0 else next_turn
    state, owners = core.playout_seize(state, owners)
    for r in range(round_no + 1, ROUNDS + 1):
        state = state.refresh_round(r)
        state, last = _fork_run_activations(core, state, opener, frng)
        if last != 0:
            opener = 2 if last == 1 else 1
        state, owners = core.playout_seize(state, owners)
    return {
        "p1": sum(1 for o in owners if o == 1),
        "p2": sum(1 for o in owners if o == 2),
    }


def _pair_block(core, state, pick, runner, seed: int, seq: int, skip: int) -> dict:
    """E0b, `_play_round` core_selfplay.gd:281-294 — the CHOSEN and the REJECTED
    candidate each resolved on a clone, both end boards logged. The generator is
    log-local, so the game's dice stream never moves."""
    lrng = _local_rng(seed * PAIR_SEED_STRIDE + seq, skip)
    st_ch = core.resolve_stochastic_rng(state, pick["action"], lrng)
    lrng.seed(seed * PAIR_SEED_STRIDE + seq + PAIR_RUNNER_OFFSET)
    for _ in range(max(skip, 0)):
        lrng.randf()
    st_ru = core.resolve_stochastic_rng(state, runner["action"], lrng)
    return {
        "chosen": core.board_rows(st_ch),
        "runner": core.board_rows(st_ru),
        "chosen_ids": core.board_row_indices(st_ch),
        "runner_ids": core.board_row_indices(st_ru),
    }


def _fork_block(core, state, pick, runner, turn: int, round_no: int, owners, seed: int,
                seq: int, salt: int, skip: int) -> dict:
    """E2-v2, `_play_round` core_selfplay.gd:295-319 — ONE fork per round, played
    to GAME END, THREE playouts per branch (a single playout flips sign in 3 of 4
    forks under re-dicing, probe 14.08.), per-run points kept."""
    c_runs: list[dict[str, int]] = []
    r_runs: list[dict[str, int]] = []
    for rep in range(FORK_REPS):
        base = seed * FORK_SEED_STRIDE + seq + rep * FORK_REP_STRIDE + salt
        frng = _local_rng(base, skip)
        c_runs.append(_fork_playout(core, state, pick["action"], turn, round_no, owners, frng))
        frng.seed(base + FORK_RUNNER_OFFSET)
        for _ in range(max(skip, 0)):
            frng.randf()
        r_runs.append(_fork_playout(core, state, runner["action"], turn, round_no, owners, frng))
    return {"chosen_runs": c_runs, "runner_runs": r_runs}


def _play_round(
    core,
    state,
    opener: int,
    rng,
    log: list,
    round_no: int,
    seed: int = 0,
    owners: list[int] | None = None,
    sidecars: bool = True,
    fork_salt: int = 0,
    sidecar_skip: int = 0,
    magic: dict[str, Any] | None = None,
    spell_reach: dict[str, float] | None = None,
    tray=None,
    dice_tally: dict[str, int] | None = None,
    roll_log: list | None = None,
    net_player: int = 0,
    eps: float = 0.0,
    act_cores: dict[int, Any] | None = None,
    cap_core=None,
    cap_share: float = 0.0,
    record_cands: bool = False,
    los_model: bool = False,
    cand_logits_fn: dict[int, Any] | None = None,
    policy_mode: str | None = None,
) -> tuple[Any, int]:
    """`_play_round` core_selfplay.gd:247-307 — strict one-for-one alternation, a
    dry side hands the tail to the other, and the NEXT round opens with whoever
    did NOT take the last activation.

    `cand_logits_fn` / `policy_mode` are `_pick_for`'s R4 seam, threaded
    through unchanged to both activation picks below — see its docstring.

    `eps` (NML-1158c) is the exploration knob: each activation's `_pick_for`
    draws its coin/index from `seed * EXPLORE_SEED_STRIDE + seq`, a stream of
    its own that the sidecars below never touch and that never touches `rng`
    or `tray`. `eps=0.0` (the default) takes zero draws — see `play_game`.

    With `sidecars`, every row also carries the board, the roster indices, the
    feature vector and — on a runner-bearing pick — the E0b pair; the ROUND's
    `round_no`-th runner-bearing pick additionally carries the E2 fork. All of it
    resolves on clones under generators of their own: `rng`, the game's stream, is
    advanced ONLY by the played activation, so `sidecars=False` plays the same
    game die for die.

    `tray` is the SECOND stream — the `nml_core.Tray` seeded from `dice_seed`
    (see `DICE_MODES`). It is `None` under `dice="expected"`; under
    `dice="table"` (D1-B4) the played resolve draws its SHOOTING dice from it
    in the table's own order, and `dice_tally` collects the unported branches
    those activations hit (see `Core.resolve_with_tray`). Since D1-B5a/B5b
    nothing is left for a later block: melee, impact AND morale (the test, its
    Fearless recovery and No Retreat's self-wounds) draw from the tray in the
    table's own order — verified by replay, every tray face matches.

    `roll_log` is the OUTCOME GATE's seam (NML-1073 M5 D0) and nothing else:
    when a list is passed, this round appends ONE entry per played activation —
    the `report["rolls"]` that activation drew, `[]` when it drew none or the
    tray is off. It is opt-in because the played game must not change: nothing
    here reads it back, and it is deliberately NOT hung on the log row, which
    `result_digest` hashes."""
    turn = opener
    last_side = 0
    forked = False
    rp_count = 0
    # SEARCH A/B: the ACTING player's core — the deep seat plans on its own
    # core (deeper search), the other seat and every default caller on the
    # base one. Planning only reads the state; the resolve stays on the base
    # core, whose knobs differ in the search pair alone.
    cores = {**{1: core, 2: core}, **(act_cores or {})}
    # `state["units"]` is keyed by unit key and the crate's per-unit lists by
    # capture index; the roster never changes shape inside a game.
    at = {k: i for i, k in enumerate(state.keys())}
    # NML-1157: the CASTER of an activation may be a JOINED HERO, whose tokens
    # live in its own roster slot (`Seams::cast_fold`, `sim::caster_of`). The
    # magic ledger counts the CHAIN so a hero's cast is not booked as no cast.
    # One `plain()` per round; attachment never changes inside a game.
    chain: dict[int, list[int]] | None = None
    if magic is not None:
        plain_units = state.plain()["units"]
        chain = {
            at[k]: [at[k]] + [at[h] for h in v["attached"] if h in at]
            for k, v in plain_units.items()
        }
    guard = state.units * 2 + 4
    while guard > 0:
        guard -= 1
        # `seq` is read BEFORE the pick — NML-1158c's dedicated stream is
        # `seed * EXPLORE_SEED_STRIDE + seq`, and `seq` is this activation's
        # own ordinal (`len(log)` before its row is appended) exactly as the
        # pair/fork formulas above already read it after the fact.
        seq = len(log)
        explore_seed = seed * EXPLORE_SEED_STRIDE + seq
        # PLAYOUT-CAP (expert-iteration step 2): the per-activation coin off
        # its own generator — `rng` and the sidecars never see a draw, and off
        # it takes zero draws, exactly like `eps=0.0`. The fallback pick below
        # is the SAME activation, so it rides the same coin.
        use_cap = False
        if cap_core is not None:
            use_cap = nml_core.Rng(seed * CAP_SEED_STRIDE + seq).randf() < cap_share
        planning = cap_core if use_cap else cores[turn]
        # R4 kwargs ride ONLY when armed: a tool that swaps in its own
        # `_pick_for`-shaped callable via `forced_picks` (game_narrator,
        # gen0_replay_one/shards, stats_mode, charge_landing_census) carries
        # the PRE-seam signature, and an unconditional kwarg would break every
        # one of them even at `cand_logits_fn=None` — the exact TypeError the
        # full suite caught (`_pick() got an unexpected keyword argument`).
        pf_kw = ({"cand_logits_fn": cand_logits_fn, "policy_mode": policy_mode}
                 if cand_logits_fn is not None or policy_mode is not None else {})
        pick = _pick_for(planning, state, turn, net_player, eps, explore_seed,
                         cands=record_cands, **pf_kw)
        if not pick:
            other = 2 if turn == 1 else 1
            pick = _pick_for(
                cap_core if use_cap else cores[other], state, other, net_player, eps, explore_seed,
                cands=record_cands, **pf_kw,
            )
            if not pick:
                break
            turn = other
        action = pick["action"]
        row = {
            "side": turn,
            "round": round_no,
            "seq": seq,
            "value": float(pick["expectation"]["before"]),
            "unit": pick["unit_key"],
            "kind": int(action["kind"]),
            "action": action,
            "intent": str(pick.get("intent", "")),
        }
        if eps > 0.0:
            # NML-1158c: present only on a game the knob actually rode —
            # TRUE only when the coin fired on THIS pick. Omitted at eps=0.0
            # (every corpus written before this knob existed, and the
            # default still) so every vintage digest and field-by-field gate
            # against the Godot oracle stays untouched, exactly like
            # `knobs["deployment"]` only riding the arena branch.
            row["explored"] = bool(pick.get("explored", False))
        if cap_share > 0.0:
            # True = the cap core planned this act (value-only row).
            row["cap"] = use_cap
        if record_cands:
            # Expert-iteration step 1: the planner's own menu — `trace.cands`
            # in build index order, `trace.scored[i].idx` joining into it —
            # plus the argmax's build index (`trace.scored[best_idx].idx`,
            # which at eps=0 is the played candidate). Absent by default, so
            # every vintage row stays byte-identical.
            # Gen-1 recorder fix: the per-candidate scores the trace already
            # computed are KEPT, as arrays parallel to `list` — `scored[i]`
            # is candidate i's hand prior score, `rs[i]` its rollout/search
            # value, None where the pool never rolled it. Parallel arrays
            # rather than inline keys: fewer lines, and `list` stays the
            # exact cand_plain shape `row["action"]` compares against.
            trace = pick["trace"]
            score_of = {e["idx"]: e["score"] for e in trace["scored"]}
            rs_of = {e["idx"]: e["rs"] for e in trace["rs"]}
            row["cands"] = {
                "list": trace["cands"],
                "best": trace["scored"][trace["best_idx"]]["idx"],
                "scored": [score_of[i] for i in range(len(trace["cands"]))],
                "rs": [rs_of.get(i) for i in range(len(trace["cands"]))],
            }
        if sidecars:
            # `AiMissionEval.features(state, player, BattleSim.reply_threat(
            # state, player), true)` — the RICH vector, which is what
            # `tools/core_selfplay.gd:274` logs. `incoming=None` lets the seam
            # compute that reply threat itself, the same default the GDScript has.
            row["features"] = core.features(state, turn, None, True)
            row["board"] = core.board_rows(state)
            row["ids"] = core.board_row_indices(state)
            runner = pick.get("runner_up") or {}
            if runner.get("action") is not None:
                row["pair"] = _pair_block(core, state, pick, runner, seed, seq, sidecar_skip)
                rp_count += 1
                if not forked and rp_count >= round_no and owners:
                    forked = True
                    row["fork"] = _fork_block(
                        core, state, pick, runner, turn, round_no, owners,
                        seed, seq, fork_salt, sidecar_skip,
                    )
        log.append(row)
        # core_selfplay.gd:322-333 — the ONE played apply per activation is the
        # only resolve the magic ledger sees; every read below is PRE-apply.
        side_key = "p%d" % turn
        actor = at[pick["unit_key"]]
        if magic is not None:
            casts_before = _chain_casts(state, chain, actor)
            events_before = len(state.cast_event_kinds())
            _magic_eligibility_tally(
                magic, side_key, state, actor,
                (spell_reach or {}).get(pick["unit_key"], 0.0),
            )
        if tray is None:
            state = core.resolve_stochastic_rng(state, action, rng)
            if roll_log is not None:
                roll_log.append([])
        else:
            state, report = core.resolve_with_tray(state, action, rng, tray)
            if roll_log is not None:
                roll_log.append(report["rolls"])
            if dice_tally is not None:
                dice_tally["activations"] = dice_tally.get("activations", 0) + 1
                dice_tally["rolls"] = dice_tally.get("rolls", 0) + len(report["rolls"])
                if report["unported"]:
                    dice_tally["unported_acts"] = dice_tally.get("unported_acts", 0) + 1
                for name in report["unported"]:
                    dice_tally[name] = dice_tally.get(name, 0) + 1
        if los_model:
            # NML-1160: `BattleSim.capture` re-runs the whole `_has_los` sweep
            # before EVERY activation (battle_sim.gd:1563-1576) — the models
            # have moved, so the sight rows have. This is that cadence: once
            # per PLAYED activation, never inside the search, where a clone
            # inherits the answer exactly as `clone_state` does.
            state = core.restamp_los(state)
        if magic is not None:
            _magic_tally(magic, side_key, casts_before, _chain_casts(state, chain, actor))
            _spells_by_kind_tally(magic, side_key, state.cast_event_kinds(), events_before)
        last_side = turn
        turn = 2 if turn == 1 else 1
    nxt = (2 if last_side == 1 else 1) if last_side != 0 else opener
    return state, nxt


def play_from_state(
    core,
    plain: dict[str, Any],
    profiles: dict[str, dict],
    opener: int,
    rng,
    tray=None,
    roll_log: list | None = None,
    dice_tally: dict[str, int] | None = None,
    net_player: int = 0,
) -> dict[str, Any]:
    """NML-1073 M5 D0 — the round loop from a GIVEN state instead of from two
    army lists and a seed, so a recorded game's own DEPLOYMENT can be the
    starting position.

    `play_game` owns everything BEFORE round 1: it loads the lists, derives the
    attachment, draws the board out of the bank, deploys both sides out of the
    game's own generator and rolls the opener off. None of that is reproducible
    from a recorded arena game — the table deployed by its OWN mission rule and
    rolled its OWN opener, and both are already IN the corpus (the first act
    line's state, and `arena_*.json`'s `opener`). This entry therefore starts
    where the recording starts and asks the caller for exactly those two
    things; the header, the profiles and every fidelity knob are the caller's
    too, because a gate replaying a corpus must set them to that corpus's own
    vintage.

    Everything from there down is `play_game`'s round loop VERBATIM and shared
    with it in code, not copied: `_round_start`, `_play_round`,
    `playout_seize`, `vp_round_add`, `vp_end_bonus`, the marker count and the
    Face-Off END verdict. Sidecars are off — a gate that judges the RESULT has
    no use for the counterfactual blocks and they cost more than the game.

    `rng` is the game's own stream, `tray` the SECOND one (see `_play_round`);
    `roll_log`, when given, collects the rolls per activation so a caller can
    hold the twin's dice stream against the table's recorded one.

    THE OBJECTIVES KNOB (NML-1073 M5 D8a) is honoured here by INHERITANCE, and
    that is the only reading that can be right. `play_game` PLACES the markers —
    three centre-line constants under `objectives="constant"`, the seeded
    rulebook layout (`nml_core.objective_layout`) under `"rulebook"` — because a
    fresh game has no board to copy. A game replayed from a recorded state has
    one: `plain["objectives"]` IS the layout the table played, count, positions
    and starting ownership together, whichever mode wrote it. Re-deriving it
    would be strictly worse — it could only ever disagree with the recording.
    So the marker COUNT comes off the state (D3+2 is 3 to 5 markers, not the 3
    every pre-D8a corpus carries) and so does each marker's starting owner.

    Returns the RESULT FIELDS an outcome comparison needs and no more —
    `winner`, `objectives`, `vp`, `rounds_played`, the per-round ledger and the
    activation log. It is deliberately NOT a `play_game` result dict: it has no
    armies, no terrain drawing list and no seed, because a game started from a
    recorded state has no honest value for any of them.

    THE FITTED EVAL (NML-1142) arrives by INHERITANCE, like the header and every
    fidelity knob: the net is armed on the CORE (`Core.load_net`), and
    `_pick_for` reads `core.has_net()`, so a caller that armed one plays every
    activation of this game with the fitted leaf and one that did not plays the
    hand eval — byte-identical to every call written before the net existed.
    There is deliberately no `net` parameter here: `play_game` has one only
    because it may CREATE the core; this entry is always handed one.
    `net_player` is the exception and is threaded, because it is not a property
    of the core but of the match — the head-to-head A/B seam described in
    `play_game`, `0` (both seats, the table's reading) by default."""
    state = core.state_of(plain)
    markers = plain.get("objectives") or []
    if not markers:
        raise ValueError("the recorded state carries no objectives to play for")
    owners = [int(m.get("owner", 0)) for m in markers]
    vp = [0, 0]
    log: list[dict[str, Any]] = []
    rounds_log: list[dict[str, Any]] = []
    rounds_played = 0
    for round_no in range(1, ROUNDS + 1):
        p = state.plain()
        _round_start(p, round_no, profiles)
        state = core.state_of(p)
        state, opener = _play_round(
            core, state, opener, rng, log, round_no, sidecars=False,
            tray=tray, dice_tally=dice_tally, roll_log=roll_log,
            net_player=net_player,
        )
        state, owners = core.playout_seize(state, owners)
        vp = core.vp_round_add(owners, vp)
        rounds_played = round_no
        rounds_log.append({"round": round_no, "owners": list(owners), "vp": list(vp)})
    vp = core.vp_end_bonus(owners, vp)
    p1 = sum(1 for o in owners if o == 1)
    p2 = sum(1 for o in owners if o == 2)
    return {
        "winner": "draw" if p1 == p2 else ("p1" if p1 > p2 else "p2"),
        "objectives": {"p1": p1, "p2": p2, "neutral": len(owners) - p1 - p2},
        "vp": {"p1": int(vp[0]), "p2": int(vp[1])},
        "rounds_played": rounds_played,
        "rounds_log": rounds_log,
        "planner_positions": log,
    }


def play_game(
    seed: int,
    list_p1: str | Path,
    list_p2: str | Path,
    repo_root: str | Path,
    bank_dir: str | Path,
    core=None,
    deploy_rng_seed: int | None = None,
    sidecars: bool = True,
    fork_salt: int = 0,
    sidecar_skip: int = 0,
    legacy_source_qd: bool = False,
    terrain_shift_cells: int = 0,
    top_k: int | None = None,
    horizon: int | None = None,
    charge_gate: str = "off",
    menu_targets: bool = False,
    hero_last: bool = False,
    cast_fold: bool = False,
    hero_attach: str = "off",
    dice: str = "expected",
    charge_landing: str = "off",
    movement: str = "rigid",
    ambush: str = "off",
    sighting: str = "unit",
    los: str = "unit",
    menu_los: str = "planner",
    deep_menu_los: str | None = None,
    menu_wide: str = "off",
    deep_menu_wide: str | None = None,
    engage_fold: bool = True,
    dangerous_end_morale: bool = True,
    cond_ap: bool | None = None,
    vocab_version: int | None = None,
    objectives: str = "constant",
    deployment: str = "zone",
    doctrine_mode: str = "search",
    dice_seed: int | None = None,
    net: str | Path | None = None,
    net_player: int = 0,
    fit_blend: float = 0.5,
    explore: float = 0.0,
    fit_mode: str = "blend",
    deep_player: int = 0,
    deep_top_k: int | None = None,
    deep_horizon: int | None = None,
    record_cands: bool = False,
    eval_variant_player: int = 0,
    eval_variant: int = 0,
    record_aux: bool = False,
    cap_share: float = 0.0,
    cap_top_k: int = 6,
    cap_horizon: int = 2,
    cand_logits_fn: dict[int, Any] | None = None,
    policy_mode: str | None = None,
    mission: str = "duel",
) -> dict[str, Any]:
    """One full match for `seed` — `_play_one` core_selfplay.gd:164-244.

    `cand_logits_fn` / `policy_mode` are the R4 seam (NML-1164,
    DESIGN_policy_player §6): `{side: fn(state, menu, side) -> list[float] |
    None}`, threaded to every activation's `_pick_for` — see its docstring
    for the throwaway-menu-call contract. Both default to `None`, which never
    touches `_pick_for`'s new branch and is byte-identical to every call
    written before this seam existed.

    `core` may be a `nml_core.Core` to reuse across games (the registries and the
    mechanics maps are the expensive part); its header is re-set per game anyway,
    because the board changes with the seed.

    `top_k` / `horizon` are the two research seams `AiPlanner.top_k_default` /
    `.horizon` read off `NML_TOP_K` / `NML_HORIZON` (ai_planner.gd:49-56,
    290-297): `None` here reads the SAME env vars the same way
    (`resolve_top_k` / `resolve_horizon`), so a caller that sets nothing gets
    exactly what the Godot trainer would. The resolved pair is stamped into the
    result's `knobs` so a corpus documents which mode wrote it — the OLD
    training corpus's `NML_TOP_K=2 NML_HORIZON=1` looks like any other run.

    `charge_gate` is the THIRD such seam (NML-1073 D2) and the only one that
    changes a RULE: "off" (the default HERE — direct callers, replays and the
    pinned-digest tests are unaffected) reproduces `tools/core_selfplay.gd`,
    which stamps no `state["charge_illegal"]` and therefore lets the planner
    offer charges against aircraft, past the rush band and through difficult
    ground; "table" wires the arena's own gate instead. DEFECT_LEDGER row 2
    moves the OTHER default: `main`'s `--charge-gate` (a fresh self-play RUN
    with no flag) now resolves to "table", because that entry point is where
    a new teacher game is actually started; a caller of this function keeps
    getting exactly what it asked for, nothing implied. It is stamped into
    the result's `knobs` alongside the search pair — see `CHARGE_GATE_MODES`.

    `hero_attach` is the D4 rung: "off" (the default) is byte-identical to every
    corpus written before it, "join" joins the heroes the list joins and folds
    nothing (what `tools/core_selfplay.gd` plays since NML-1105), "table" joins
    AND folds — see `HERO_ATTACH_MODES`. Only the FOLD reaches the header knob;
    the mode string is stamped into the result's `knobs` alongside the search
    pair.

    `dice` is the FOURTH (NML-1073 M5 D1-B3) and the deepest: "expected" (the
    default) keeps the expected-value combat every corpus so far was written
    with; "table" is the rung with the shipped game's real dice tray. B3 ships
    the PLUMBING ONLY — the tray is constructed and seeded from `dice_seed`,
    the mode is stamped into `knobs`, and no consumer reads the tray yet, so
    "table" and "expected" play the identical game and differ in that one
    stamped string alone. B4/B5 add the consumers. See `DICE_MODES`.

    `objectives="doctrine"` (NML-1140 step 9) is the rulebook draw with the
    candidate choice replaced: count and first placer stay on the layout stream,
    `nml_core.doctrine_place` picks the cells from the two armies' profiles, and
    the stamp gains the rung under `"doctrine"` beside `"mode": "rulebook"`.
    `doctrine_mode` picks that rung — see `DOCTRINE_MODES`.

    `sidecars` writes the pair/fork counterfactual blocks (NML-1073 M3-9); they
    resolve on clones under generators of their own, so the PLAYED game is
    identical with them off. `fork_salt` is `NML_FORK_SALT` (label-noise probes:
    same game, re-diced playouts) and `sidecar_skip` the M3-9 red proof — see
    `_local_rng`.

    `legacy_source_qd` encodes board columns 10/11 as the blank
    `OPRApiClient.OPRUnit` 4/4 that every PRE-#392 trainer row carries; the
    default is the unit's own quality/defense, which is what the fixed GDScript
    trainer writes. It exists to replay an old corpus, and as the red proof that
    the two readings are not the same file.

    `terrain_shift_cells` is the terrain RED PROOF: the drawing list is written
    with every piece centre moved that many 3" cells along +x, so a gate that
    could not tell the board apart would be reading a shape, not a board.

    `deploy_rng_seed` is the RED PROOF knob and nothing else: deployment then
    draws from a generator of its own while the game's generator is advanced by
    the SAME number of draws and discards them, so the opener roll-off and every
    die of every activation stay bit-identical and the ONLY thing that moved is
    where the models were put. A gate that could not tell that apart would be
    measuring the seed, not the deployment.

    `deployment` (NML-1152 step 8) picks the PRE-GAME: "zone" (the default) is
    the twin's own even spread above and stays byte-identical to every corpus
    written before this knob existed; "arena" plays the table's pre-game
    instead — the roll-off drawn FIRST from the game stream with ties re-rolled
    (stream topology, design §1), winner-first finish order, and the Rust
    `deploy_side(seed + slot)` / `deploy_finish` pipeline feeding `capture`. A
    reserved (Ambush) unit starts off-table with no models — the round-2
    arrival is the declared in-game residual, not something this knob fakes.
    "interleaved" is "arena" with the rulebook's TURN ORDER (GF v3.5.1 p.6):
    one `deploy_interleaved` call alternates the two sides' queues winner-first
    instead of draining each side whole, Scouts in their own phase after both
    armies' normals. Same per-side streams, same spots, same finish — only the
    order changes — and the game record carries `placement_sequence`, the
    cross-side fact `deployment_gate.py`'s interleave class reads.
    The stamp rides ONLY the arena branch, exactly like `objectives_layout`:
    a "zone" game records the same object it did before this knob existed, an
    arena game must say so (NML-1147a).

    `engage_fold` (PR #446, D5-4) and `cond_ap` (PR #448, NML-1103) are plain
    bools/`None`, not a mode string: neither has a "table" reading to fall
    back to here (this call GENERATES a game, it does not replay a recorded
    one). `engage_fold` rides the header knob the way every replay gate does,
    and its default (True) is the twin's OWN default, so a caller that passes
    nothing sees no change. `cond_ap` is inverted onto
    `nml_core.set_legacy_no_cond_ap` — but that flag is a PROCESS GLOBAL, and
    several existing test files (`test_selfplay.py`, `test_sidecars.py`,
    `test_rows.py`) already manage it themselves around a `play_game` call
    (an `autouse` fixture sets it for `m3_ref_v2`'s known LEGACY corpus, the
    sibling of `rules.LEGACY_PREFIX_RULES`). `cond_ap` therefore defaults to
    `None` — "do not touch it" — and only calls `set_legacy_no_cond_ap` when
    a caller passes an explicit bool; `None` is otherwise indistinguishable
    from every call site written before this parameter existed. NML-1130's
    own callers (the gates under `tools/`) always resolve `auto`/`on`/`off`
    to a concrete bool before they ever reach here (there is no header for
    this function to read a vintage off, so `auto` resolves against
    `vintage_knobs({}, ...)`).

    `explore` (NML-1158c, `--explore` below) is the POLICY WAVE's exploration
    knob: with probability `explore` per activation, the twin picks uniformly
    among the prefilter's rolled top-K pool instead of the argmax. The coin
    and the index both draw from a stream of their own, seeded per activation
    as `seed * EXPLORE_SEED_STRIDE + seq` — never `rng` (the game's dice),
    never a layout or deployment seed — so an explored game is still
    reproducible from its seed and a `deployment="arena"` or `dice="table"`
    game explores the identical activations a `deployment="zone"` one would.
    `0.0` (the default) takes zero draws in the crate (`Search::run`), and a
    row carries no `explored` key at all under it — every corpus written
    before this knob existed, and every vintage digest / Godot field-by-field
    gate, replays byte for byte. `explore > 0.0` puts an `explored` key on
    every played row, TRUE only where ITS OWN coin fired; the result's
    `knobs["explore"]` stamp always says what the whole game was played with
    (NML-1147a pattern, alongside `fit_blend`).

    `record_cands` is the expert-iteration opt-in (step 1): True asks every
    `_pick_for` for the binding's `cands=True` and stamps each played row
    with `row["cands"] = {"list": [...], "best": idx}` — the planner's built
    candidates' full content in build index order (`trace.scored[i].idx`
    joins into the list) plus the argmax's build index. Gen-1 recorder fix:
    the scores the trace already computed ride along as arrays PARALLEL to
    `list` — `cands["scored"][i]` is candidate i's hand prior score,
    `cands["rs"][i]` its rollout/search value, None where the pool never
    rolled it — and the header stamps `core_commit`, the short sha of the
    checkout the core was built from. False (the default) writes the rows
    byte for byte as every corpus before this flag did, stamps neither, and
    nothing joins `knobs` — the keys ride the rows and the header alone.

    `deep_player` (the SEARCH A/B seam) is the per-seat counterpart of
    `top_k`/`horizon`: seat 1 or 2 plays ITS activations with a SECOND core
    built off the same header payload but carrying `deep_top_k`/`deep_horizon`
    instead of the base pair, so one seat searches deeper on the same board.
    State objects are core-independent (`state_of`/`resolve_*` take them as
    arguments), so the two cores share one game; the other seat keeps the base
    core and every caller that passes nothing (0, the default) plays the
    identical game the pre-knob code did. A deep game whose deep pair EQUALS
    the resolved base pair digests byte-identically to a plain game — the
    proof that the second core really sees the same header — and when the
    pair parts, the result stamps both seats' resolved depths as
    `knobs_by_seat` (the NML-1147a pattern: the stamp rides only a game whose
    deep pair actually differs).

    `eval_variant_player` / `eval_variant` (evolved-eval lane, step 2) are
    `deep_player`'s counterpart for the HAND EVAL instead of the search pair:
    seat 1 or 2 plays on a second core whose header carries `eval_variant` in
    place of 0. Today only variant 0 exists (`Knobs::eval_variant` has no
    registered arm past it — `set_header` refuses any other value), so every
    caller that passes nothing plays the identical game the pre-knob code
    did; this is the seam a future generation registers a real variant into,
    not a new eval. Shares the deep-player core when both target the same
    seat. Stamped into `knobs_by_seat` the same way, only when it moved.

    `record_aux` (expert-iteration step 2) hangs the KataGo-style AUX targets —
    models alive per side, wounds taken per side (`_aux_alive_wounds`) — on
    every `rounds_log` entry and on the result beside `objectives`. Opt-in
    because `result_digest` hashes `rounds_log`: a default game must stay
    byte-identical to every corpus written before the flag existed.

    `cap_share` (playout-cap randomization, same step) generalises the
    per-SEAT second core to per-ACTIVATION: when > 0, one extra core built
    with `cap_top_k`/`cap_horizon` off the same header joins the seats' cores,
    and each activation's coin — a stream of its own, seeded
    `seed * CAP_SEED_STRIDE + seq` — hands it the pick with probability
    `cap_share`, stamping `row["cap"]` (True = cap core planned the act, a
    value-only row; False = the seat's full-search core, the policy target).
    0.0, the default, builds no core, draws no coin, stamps no key."""
    units1 = load_army(list_p1, 1)
    units2 = load_army(list_p2, 2)
    if not units1 or not units2:
        raise ValueError("empty army (%s / %s)" % (list_p1, list_p2))
    units = units1 + units2
    profiles = {u["unit_id"]: u for u in units}
    # D4: derived BEFORE the header, because `attached_hero_rules` is a PROFILE
    # field the crate reads out of it (state.rs:71). "off" touches neither the
    # profiles nor the capture, so it stays byte-identical.
    attached = attached_to = None
    eff_hero_attach = resolve_hero_attach(hero_attach)
    if hero_join(hero_attach):
        selections = dict(load_selections(list_p1, 1))
        selections.update(load_selections(list_p2, 2))
        attached, attached_to = derive_attachment(units, selections)
        for u in units:
            u["attached_hero_rules"] = [
                profiles[h]["special_rules"] for h in attached[u["unit_id"]]
            ]

    board, terrain, pieces = load_board(seed, bank_dir)
    # NML-1163 — the banked drawing list rides the HEADER, so that
    # `Core.policy_tokens` exports the same terrain rows the shard exporter
    # packs (`tools/gen0_replay_shards.terrain_rows`). A banked board paints
    # its terrain into `cells` and carries an EMPTY `sandbox`, which is the
    # only list `tokens::build` could read before: every live state exported
    # 18 zero rows while the board carried 16 or 18 real pieces. The list is
    # the BANK's, never `_shift_pieces`'s — the shift knob's whole point is
    # that the board does not move with the drawing list.
    terrain = dict(terrain, pieces=pieces)
    if core is None:
        core = nml_core.load(str(repo_root))
    # NML-1142 — the trained eval. `None` leaves whatever the caller armed (a
    # reused core keeps its net across games, the way the table keeps its
    # process-global one); a path arms it and turns `fit_mode` on for every
    # activation of this game. The loader GATE is the GDScript's own selftest,
    # so a drifted net RAISES here instead of quietly playing.
    if net is not None:
        core.load_net(str(net), blend=fit_blend, mode=fit_mode)
    eff_top_k = resolve_top_k(top_k)
    eff_horizon = resolve_horizon(horizon)
    eff_charge_gate = resolve_charge_gate(charge_gate)
    eff_dice = resolve_dice(dice)
    eff_charge_landing = resolve_charge_landing(charge_landing)
    eff_movement = resolve_movement(movement)
    eff_ambush = resolve_ambush(ambush)
    eff_sighting = resolve_sighting(sighting)
    eff_los = resolve_los(los)
    eff_menu_los = resolve_menu_los(menu_los)
    eff_menu_wide = resolve_menu_wide(menu_wide)
    # W1: resolved here, not in the deep-seat block below, because the BASE core
    # is the one that RESOLVES every activation (`_play_round`) — including the
    # deep seat's ADVANCE+shoot. Without the permission the base core declines
    # it (`Unsupported::MovedShootLos`) and the game dies mid-round.
    eff_deep_menu_wide = (
        eff_menu_wide if deep_menu_wide is None else resolve_menu_wide(deep_menu_wide)
    )
    eff_deployment = resolve_deployment(deployment)
    knobs = dict(
        TRAINER_KNOBS,
        top_k=eff_top_k,
        horizon=eff_horizon,
        charge_gate=eff_charge_gate,
        # NML-1157: the MENU treats a joined Hero as part of its host (GF
        # v3.5.1 p.14) and offers the charge the unit can REACH beside the one
        # it scores best. False is the crate's default and what every earlier
        # corpus carries, so a caller that passes nothing writes the identical
        # header and the identical menu.
        menu_targets=bool(menu_targets),
        # NML-1157: see TRAINER_KNOBS. Needs `hero_attach` on to do anything.
        hero_last=bool(hero_last),
        # NML-1157: see TRAINER_KNOBS. Needs `hero_attach` on to do anything —
        # without the fold the rest of the resolver does not believe in the
        # chain either (`sim::caster_of`).
        cast_fold=bool(cast_fold),
        # NML-1073 M5 D1-B4b: the SEAM half of `hero_attach`. Deriving the
        # attachment is not enough — without this the hero would fire inside its
        # host's volley AND still be handed a full activation of its own
        # (`Seams::hero_attach` io.rs). "off" leaves it False, which is the
        # default and what every earlier corpus carries.
        hero_attach=eff_hero_attach,
        # NML-1073 M5 D5-1: the table's SECOND engage gate. "off" leaves it
        # False, which is the default and what every earlier corpus carries.
        charge_landing=eff_charge_landing,
        # NML-1073 M5 D5-2: the charge MOVE itself. "rigid" leaves it False,
        # which is the default and what every earlier corpus carries.
        movement=eff_movement,
        # NML-1073 M5 D6a-B4: how a VOLLEY counts its shooters. "unit" is the
        # crate's own default and what every earlier corpus carries, so a caller
        # that passes nothing writes the identical header.
        sighting=eff_sighting,
        # NML-1160: WHICH sight the menu and the resolve read. "unit" leaves it
        # False, which is the default and what every earlier corpus carries.
        los_model=eff_los,
        # NML-1161: whether the MENU's shoot leg asks the resolve's whole
        # question. "planner" leaves it False, which is the GDScript's own menu
        # and what every earlier corpus carries.
        menu_los=eff_menu_los,
        # W1: whether the MENU may offer ADVANCE+shoot at all. "off" leaves it
        # False, which is the menu every earlier corpus carries.
        menu_wide=eff_menu_wide,
        # W1: the RESOLVE half, granted to BOTH cores as soon as EITHER seat may
        # offer a moving shot. A permission, not a rule: with no such candidate
        # in the menu it changes nothing, which is why a knob-off game is still
        # byte-identical.
        moved_shoot=eff_menu_wide or eff_deep_menu_wide,
        # NML-1130: the header knob PR #446 defaults ON in the twin. True here
        # matches that default, so a caller that passes nothing sees no change.
        engage_fold=engage_fold,
        # DEFECT_LEDGER #12: a NEW rule (like `engage_fold`), True by default
        # so a fresh game stamps it and gets the p.10 test; a replay tool reads
        # the RECORD's own key instead and passes False when it predates this.
        dangerous_end_morale=dangerous_end_morale,
        # NML-1134: which RULE VOCABULARY this game's board rows are slotted
        # with. A fresh game uses THIS BUILD's version — the default here, and
        # the only setting a fresh corpus may use. A gate replaying a corpus
        # recorded under an older vocabulary passes that corpus's version
        # (`resolve_vocab_version`), so its `unknown_rules` and its row LENGTHS
        # are the ones the recording carries instead of today's.
        rule_vocab_version=(
            nml_core.RULE_VOCAB_VERSION if vocab_version is None else int(vocab_version)
        ),
    )
    # NML-1152 step 8: the arena stamp rides ONLY the arena branch — a "zone"
    # game records the identical header it always did (vintage-pin), an arena
    # game must say so (NML-1147a). The crate's knob struct ignores the key.
    if eff_deployment != "zone":
        knobs["deployment"] = eff_deployment
    core.set_header({"profiles": profiles, "terrain": terrain, "knobs": knobs})
    # NML-1130 (PR #448, NML-1103): conditional AP (Shatter/Tear/Disintegrate/
    # Melee Slayer/Piercing Assault/Piercing Hunter) counted the corrected way.
    # `cond_ap=None` (the default) leaves `LEGACY_NO_COND_AP` exactly as the
    # CALLER left it — see the docstring on why this one knob does not get a
    # concrete default the way `engage_fold` does.
    if cond_ap is not None:
        nml_core.set_legacy_no_cond_ap(not cond_ap)
    # Board columns 10/11 read the GameUnit's `source_data` (battle_sim.gd
    # :233-234), which `tools/core_selfplay.gd` fills from the unit since #392 —
    # so the DEFAULT is the profile's own quality/defense. The 4/4 of a blank
    # `OPRApiClient.OPRUnit` is what a pre-#392 corpus carries and nothing else.
    if legacy_source_qd:
        core.set_encoder_source_qd(SOURCE_DATA_QUALITY, SOURCE_DATA_DEFENSE)
    else:
        core.clear_encoder_source_qd()
    # SEARCH A/B: the DEEP seat's own core. Same header payload (same profiles,
    # terrain and every other knob) but `deep_top_k`/`deep_horizon` in place of
    # the base pair, so its `plan_with_rollout` searches deeper on the same
    # board; per-core state (`has_net`, the encoder source qd) is mirrored so
    # the two cores differ in the search pair alone. `act_cores` hands
    # `_play_round` the ACTING player's core — `None` leaves both seats on the
    # base core, which is every caller that passes nothing.
    act_cores: dict[int, Any] | None = None
    seat_knobs: dict[str, Any] | None = None
    if deep_player in (1, 2):
        d_top_k = resolve_top_k(deep_top_k)
        d_horizon = resolve_horizon(deep_horizon)
        deep_core = nml_core.load(str(repo_root))
        if net is not None:
            deep_core.load_net(str(net), blend=fit_blend, mode=fit_mode)
        # NML-1161b: the DEEP seat may also carry its own `menu_los`. It is the
        # first knob of this seam that is not a search depth, and it works for
        # one reason: `Tuning` is derived per CORE (`plan::tuning_of` off the
        # header), and `_play_round` plans the acting seat on ITS core while
        # both seats still RESOLVE on the base one. So the two seats differ in
        # the MENU and in nothing else — which is what makes a `menu_los` A/B a
        # STRENGTH measurement rather than the impact measurement a state-level
        # knob like `los` can give. `None` leaves the base value on both, which
        # is every caller written before this.
        d_menu_los = eff_menu_los if deep_menu_los is None else resolve_menu_los(deep_menu_los)
        # W1 rides the identical seam: `menu_wide` is a MENU knob, so the deep
        # seat may play the wide menu while the base seat plays today's, on one
        # board and one dice stream — a STRENGTH A/B, the way `menu_los` is.
        d_menu_wide = eff_deep_menu_wide
        deep_core.set_header(
            {"profiles": profiles, "terrain": terrain,
             "knobs": dict(knobs, top_k=d_top_k, horizon=d_horizon, menu_los=d_menu_los,
                           menu_wide=d_menu_wide)}
        )
        if legacy_source_qd:
            deep_core.set_encoder_source_qd(SOURCE_DATA_QUALITY, SOURCE_DATA_DEFENSE)
        else:
            deep_core.clear_encoder_source_qd()
        act_cores = {deep_player: deep_core}
        # NML-1147a pattern: the stamp rides ONLY a game whose deep pair parted
        # from the base pair — an equal-knobs deep game digests byte-identically
        # to a plain game, stamp included.
        if (d_top_k, d_horizon, d_menu_los, d_menu_wide) != (
            eff_top_k, eff_horizon, eff_menu_los, eff_menu_wide
        ):
            deep_stamp: dict[str, Any] = {"top_k": d_top_k, "horizon": d_horizon}
            base_stamp: dict[str, Any] = {"top_k": eff_top_k, "horizon": eff_horizon}
            # NML-1161b, NML-1147a pattern: the MENU half of the stamp rides
            # only a game whose two seats actually parted on it, so a
            # depth-only A/B records the exact object it always did.
            if d_menu_los != eff_menu_los:
                deep_stamp["menu_los"] = "resolve" if d_menu_los else "planner"
                base_stamp["menu_los"] = menu_los
            if d_menu_wide != eff_menu_wide:
                deep_stamp["menu_wide"] = "table" if d_menu_wide else "off"
                base_stamp["menu_wide"] = menu_wide
            seat_knobs = {"p1": deep_stamp, "p2": base_stamp}
            if deep_player == 2:
                seat_knobs["p1"], seat_knobs["p2"] = seat_knobs["p2"], seat_knobs["p1"]
    # EVAL-VARIANT seam (evolved-eval lane step 2): `deep_player`'s
    # counterpart for the HAND EVAL — a second core off the identical header,
    # `eval_variant` in place of 0. Built whenever a seat is named, even at
    # the default 0, so a caller can prove the second core changes nothing
    # (byte-identical digest) before any real variant exists; the stamp
    # rides only a game whose variant actually moved (NML-1147a pattern).
    if eval_variant_player in (1, 2):
        ev_core = nml_core.load(str(repo_root))
        if net is not None:
            ev_core.load_net(str(net), blend=fit_blend, mode=fit_mode)
        ev_core.set_header(
            {"profiles": profiles, "terrain": terrain,
             "knobs": dict(knobs, eval_variant=eval_variant)}
        )
        if legacy_source_qd:
            ev_core.set_encoder_source_qd(SOURCE_DATA_QUALITY, SOURCE_DATA_DEFENSE)
        else:
            ev_core.clear_encoder_source_qd()
        act_cores = {**(act_cores or {}), eval_variant_player: ev_core}
        if eval_variant != 0:
            seat_key, other_key = ("p1", "p2") if eval_variant_player == 1 else ("p2", "p1")
            seat_knobs = seat_knobs or {"p1": {}, "p2": {}}
            seat_knobs[seat_key] = dict(seat_knobs.get(seat_key, {}), eval_variant=eval_variant)
            seat_knobs.setdefault(other_key, {})
    # PLAYOUT-CAP (expert-iteration step 2): the per-ACTIVATION second core,
    # same header payload with `cap_top_k`/`cap_horizon` in place of the base
    # pair; per-core state mirrored exactly like the deep core above.
    cap_core = None
    if cap_share > 0.0:
        cap_core = nml_core.load(str(repo_root))
        if net is not None:
            cap_core.load_net(str(net), blend=fit_blend, mode=fit_mode)
        cap_core.set_header(
            {"profiles": profiles, "terrain": terrain,
             "knobs": dict(knobs, top_k=cap_top_k, horizon=cap_horizon)}
        )
        if legacy_source_qd:
            cap_core.set_encoder_source_qd(SOURCE_DATA_QUALITY, SOURCE_DATA_DEFENSE)
        else:
            cap_core.clear_encoder_source_qd()
    reads = core.capture_reads()
    # `SpellsRegistry.spells_for_unit(gu)` per unit — the book `_magic_init` asks
    # whether it resolved, and whose LONGEST range gates the eligibility tally.
    books = core.spell_ranges()
    spell_reach = {k: (max(v) if v else 0.0) for k, v in books.items()}
    magic = _magic_init(units, books)

    rng = nml_core.Rng(seed)
    # THE STREAM SPLIT (NML-1073 M5 D1-B3). `rng` above is the game's own
    # generator — deployment, the opener roll-off and every played activation
    # draw from it, exactly as `tools/core_selfplay.gd:_play_one` does. The
    # tray is a SECOND generator, seeded from the dice seed the way
    # `arena_match.gd:478` seeds the table's (`_dice_seed`, which defaults to
    # the game seed, :984-985) — because on the table those are two streams,
    # and one generator serving both could never reproduce it. D1-B4 gives it
    # its FIRST consumer — the shooting sub-phase — so under `dice="expected"`
    # the tray is not even built and every digest written before this knob
    # existed still reproduces byte for byte.
    # NML-1140 step 9b: the tray's seed is the DICE seed — `_dice_seed`,
    # which defaults to the game seed (`dice_seed=None` keeps every corpus
    # written so far byte-identical) and which the mixed A/B grid varies to
    # get its second dice rung per game seed.
    eff_dice_seed = seed if dice_seed is None else dice_seed
    tray = nml_core.Tray(eff_dice_seed) if eff_dice == "table" else None
    dice_tally: dict[str, int] = {}
    # core_selfplay.gd:176 — three markers on the centre line, 16" apart.
    eff_objectives = resolve_objectives(objectives)
    objective_layout: dict[str, Any] | None = None
    if eff_objectives in ("rulebook", "doctrine"):
        # D8a: the same layout the table places for this seed. The board is the very
        # `terrain` object the act header carries, so the legality test sees the same
        # impassable cells on both sides. NML-1140 step 9: "doctrine" keeps the draw
        # (count + roll-off, the stream contract — same count and first placer as the
        # rulebook of this seed) and replaces ONLY the candidate choice, which the
        # doctrine takes from the two armies' profiles with zero RNG of its own.
        draw = nml_core.objective_layout(terrain, seed, "d3+2", FRONT_LINE_ZONES)
        if eff_objectives == "rulebook":
            objective_layout = draw
        else:
            eff_doctrine = resolve_doctrine_mode(doctrine_mode)
            placed = nml_core.doctrine_place(
                terrain, eff_doctrine,
                (
                    {u["unit_id"]: u for u in units1},
                    {u["unit_id"]: u for u in units2},
                ),
                draw["count_roll"], FRONT_LINE_ZONES,
            )
            objective_layout = {
                "mode": "rulebook",
                "count_roll": draw["count_roll"],
                "first_placer": draw["first_placer"],
                "layout_seed": draw["layout_seed"],
                "edge_margin_in": draw["edge_margin_in"],
                "positions": placed["positions"],
                # objectives.rs:116-117 — the roll-off still books the placer
                # order even though it feeds no choice (design 4: the doctrine
                # places in canonical roster order).
                "placed_by": [
                    draw["first_placer"] if i % 2 == 0 else 3 - draw["first_placer"]
                    for i in range(len(placed["positions"]))
                ],
                "swept": placed["swept"],
                # The step-5 UNSURE, taken by the coordinator: the rung rides
                # under the table's own stamp key, beside "mode": "rulebook".
                "doctrine": eff_doctrine,
            }
        objectives = [
            [f32(float(x) * IN2M), 0.0, f32(float(z) * IN2M)]
            for x, z in objective_layout["positions"]
        ]
    elif eff_objectives == "mixed":
        # NML-1140 step 9b — per-side placer selection in the alternating
        # placement: the rolled placer order stands, and each ply's choice goes
        # to ITS seat's placer. The stream contract holds: the draws (count,
        # roll-off, then draw() per random ply) are the rulebook's pinned order
        # off a fresh generator on the layout seed; a doctrine ply draws
        # nothing. The sweep is the last resort for either side, x ascending.
        placement = resolve_mixed_placement(doctrine_mode)
        rng = nml_core.Rng(seed)
        count_roll = rng.randi_range(1, 3) + 2
        first_placer = 1
        for _ in range(100):
            d1, d2 = rng.randi_range(1, 6), rng.randi_range(1, 6)
            if d1 != d2:
                first_placer = 1 if d1 > d2 else 2
                break
        hx, hz = 33, 21
        placed, swept = [], 0
        while len(placed) < count_roll:
            seat = first_placer if len(placed) % 2 == 0 else 3 - first_placer
            cell = None
            if placement[str(seat)] == "random":
                for _ in range(1000):
                    x, z = rng.randi_range(-hx, hx), rng.randi_range(-hz, hz)
                    if nml_core.objective_is_legal(terrain, FRONT_LINE_ZONES, x, z, placed):
                        cell = [x, z]
                        break
            else:
                step = nml_core.doctrine_place_step(
                    ({u["unit_id"]: u for u in units1}, {u["unit_id"]: u for u in units2}),
                    count_roll, FRONT_LINE_ZONES, placed, terrain=terrain,
                )
                cell = list(step) if step else None
            if cell is None:
                cell = next(
                    ([x, z] for x in range(-hx, hx + 1) for z in range(-hz, hz + 1)
                     if nml_core.objective_is_legal(terrain, FRONT_LINE_ZONES, x, z, placed)),
                    None,
                )
                if cell is not None:
                    swept += 1
            if cell is None:  # no legal cell left at all: fewer markers, stamped honestly
                break
            placed.append(cell)
        objective_layout = {
            "mode": "mixed",
            "count_roll": count_roll,
            "first_placer": first_placer,
            "layout_seed": seed,
            "edge_margin_in": 3,
            "positions": placed,
            "placed_by": [first_placer if i % 2 == 0 else 3 - first_placer for i in range(len(placed))],
            "swept": swept,
            "doctrine": {"p1": placement["1"], "p2": placement["2"]},
        }
        objectives = [
            [f32(float(x) * IN2M), 0.0, f32(float(z) * IN2M)]
            for x, z in objective_layout["positions"]
        ]
    else:
        objectives = [[f32(-16.0 * IN2M), 0.0, 0.0], [0.0, 0.0, 0.0], [f32(16.0 * IN2M), 0.0, 0.0]]
    arena = eff_deployment in ("arena", "interleaved")
    deploy_seq: list[list[Any]] = []
    if arena:
        # NML-1152 step 8 — the table's pre-game. Roll-off FIRST from the game
        # stream (ties re-rolled; the winner of the last attempt opens, the
        # cap fallback 1 matching `roll_off_traced`), then the Rust pipeline
        # on per-side streams: the game stream advances by the roll-off and
        # NOTHING else before the first activation.
        roll_attempts = _arena_roll_off(rng)
        opener = 1 if roll_attempts[-1][0] >= roll_attempts[-1][1] else 2
        pos1, pos2, reserved, deploy_seq = _deploy_arena(
            seed, units1, units2, list_p1, list_p2, board, objectives, opener,
            eff_deployment == "interleaved",
        )
    elif deploy_rng_seed is None:
        pos1 = deploy_zone(units1, -TABLE_D_IN / 2.0, 12.0, rng)
        pos2 = deploy_zone(units2, TABLE_D_IN / 2.0 - 12.0, 12.0, rng)
    else:
        side = nml_core.Rng(deploy_rng_seed)
        pos1 = deploy_zone(units1, -TABLE_D_IN / 2.0, 12.0, side)
        pos2 = deploy_zone(units2, TABLE_D_IN / 2.0 - 12.0, 12.0, side)
        deploy_zone(units1, -TABLE_D_IN / 2.0, 12.0, rng)
        deploy_zone(units2, TABLE_D_IN / 2.0 - 12.0, 12.0, rng)
    # The arrival reads are the registry's, taken once off the header the way
    # `capture_reads` is — never re-derived in Python. Only `ambush="table"`
    # asks for them, so an "off" game builds byte-identically to every corpus
    # written before this knob.
    arrivals = core.arrival_reads() if (arena and eff_ambush) else None
    plain = capture(
        units, pos1 + pos2, reads, board, objectives, attached, attached_to,
        reserved if arrivals is not None else None,
        {k: v["earliest"] for k, v in arrivals.items()} if arrivals is not None else None,
    )
    mission_def = resolve_mission(mission, repo_root)  # SoloController.mission_reset mirrored
    eff_scoring = mission_def.get("scoring", "end")
    vp_flavour = mission_def.get("vp", {})
    mk_spec = mission_def.get("markers", {})
    markers_meta = [
        {"owned_by": (i % 2) + 1, "destructible": bool(mk_spec.get("destructible"))}
        for i in range(len(objectives))
    ] if mk_spec.get("owned") else []
    plain["scoring"] = eff_scoring
    if eff_scoring == "round_vp":
        plain["vp"], plain["vp_flavour"], plain["vp_memo"] = [0, 0], vp_flavour, {}
    if markers_meta:
        plain["markers_meta"], plain["destroy_seq"] = markers_meta, [0]
    state = core.state_of(plain)
    if eff_los:
        # NML-1160: the deployment sweep. `BattleSim.capture` fills `los` on the
        # state it hands the planner, and this is the same state.
        state = core.restamp_los(state)

    owners = [0] * len(objectives)
    vp = [0, 0]
    vp_memo: dict[str, Any] = {}
    destroy_seq = [0]
    if not arena:
        # The d6 roll-off, P1 winning ties — and BOTH dice are drawn, left first.
        left = rng.randi_range(1, 6)
        right = rng.randi_range(1, 6)
        opener = 1 if left >= right else 2
    log: list[dict[str, Any]] = []
    rounds_log: list[dict[str, Any]] = []
    rounds_played = 0
    for round_no in range(1, ROUNDS + 1):
        plain = state.plain()
        _round_start(plain, round_no, profiles, magic)
        if arrivals is not None:
            _arrive_reserves(plain, arrivals, board, objectives, opener, round_no)
        state = core.state_of(plain)
        state, opener = _play_round(
            core, state, opener, rng, log, round_no,
            seed=seed, owners=owners, sidecars=sidecars,
            fork_salt=fork_salt, sidecar_skip=sidecar_skip,
            magic=magic, spell_reach=spell_reach, tray=tray, dice_tally=dice_tally,
            net_player=net_player, eps=explore, act_cores=act_cores,
            cap_core=cap_core, cap_share=cap_share,
            record_cands=record_cands, los_model=eff_los,
            cand_logits_fn=cand_logits_fn, policy_mode=policy_mode,
        )
        state, owners = core.playout_seize(state, owners)
        if markers_meta:  # W3: an enemy-held owned marker falls before scoring
            markers_meta, owners, destroy_seq = core.apply_destroy_step(
                markers_meta, owners, destroy_seq
            )
        if eff_scoring == "round_vp":
            vp, vp_memo = core.vp_score_round(owners, vp, vp_flavour, vp_memo, markers_meta)
            if round_no == ROUNDS:
                vp = core.vp_score_end(owners, vp, vp_flavour)
        elif eff_scoring == "end":
            vp = core.vp_round_add(owners, vp)
        rounds_played = round_no
        entry = {"round": round_no, "owners": list(owners), "vp": list(vp)}
        if record_aux:
            entry.update(_aux_alive_wounds(state, profiles))
        rounds_log.append(entry)
    if eff_scoring == "end":
        vp = core.vp_end_bonus(owners, vp)

    p1 = sum(1 for o in owners if o == 1)
    p2 = sum(1 for o in owners if o == 2)
    # `_write_result` :700-706: Face-Off is END-scored, MARKERS decide; every
    # other mission asks `BattleSim.mission_winner`'s own referee.
    winner = ("draw" if p1 == p2 else ("p1" if p1 > p2 else "p2")) if eff_scoring == "end" \
        else core.mission_winner(eff_scoring, owners, vp, markers_meta, 0, 0)
    return {
        "schema": 1,
        "board_schema": 5,
        "rule_vocab": "v1d",
        "school_world": 2,
        # `_write_result` :725 — `SchoolTerrain.generate(seed)["pieces"]`, the
        # judge bench's drawing list, straight out of the bank.
        "terrain": _shift_pieces(pieces, terrain_shift_cells),
        "tool": "core_selfplay_py",
        # The CROSS-SIDE placement order (GF v3.5.1 p.6), `[[slot, unit key], ..]`
        # — the same fact tools/pregame_dump.gd writes as `placement_sequence`,
        # and the ONLY place a game record can show that the sides alternated.
        # Rides the "interleaved" branch only (NML-1147a pattern): a "zone" or
        # "arena" game stays the exact object it was, `result_digest` included.
        **({"placement_sequence": deploy_seq} if eff_deployment == "interleaved" else {}),
        # Gen-1 recorder fix: WHICH core build recorded the game — the short
        # sha of the checkout at import. Rides the expert-iteration corpus
        # path only (NML-1147a pattern): a default game stays the exact
        # object it always was, digest included.
        **({"core_commit": _core_commit} if record_cands else {}),
        # `tools/core_selfplay.gd` stamps no such field (it always runs the
        # planner's own defaults) — this documents the fast trainer's MODE,
        # e.g. the old training corpus's `NML_TOP_K=2 NML_HORIZON=1`. Excluded
        # from the Godot parity gates alongside the other Python-only extras
        # (sidecar_gate.py's `EXCLUDED_TOP`).
        "knobs": {
            "top_k": eff_top_k,
            "horizon": eff_horizon,
            "charge_gate": charge_gate,
            # Stamped only away from "duel" (the `deployment`/`ambush` idiom).
            **({"mission": mission} if mission != "duel" else {}),
            # NML-1157: stamped only when ON, the way `deployment` is — a
            # default game writes the identical object it wrote before the knob
            # existed, so no Godot parity gate sees a new key.
            **({"menu_targets": True} if menu_targets else {}),
            **({"hero_last": True} if hero_last else {}),
            **({"cast_fold": True} if cast_fold else {}),
            "hero_attach": hero_attach,
            "dice": eff_dice,
            "charge_landing": charge_landing,
            "movement": movement,
            # SPEC ambush arrival S3b: stamped only under "table", the
            # `deployment` idiom two keys below — an "off" game is the same
            # object it was before this knob existed, so every digest and
            # every recorded corpus stays byte-identical. The absence of the
            # key IS "off", which is what every corpus so far played.
            **({"ambush": ambush} if eff_ambush else {}),
            "sighting": eff_sighting,
            # NML-1160: WHICH sight the game played. Stamped only under
            # "model", for the same reason `deployment` is only stamped under
            # "arena": a default game is the object it was before the knob.
            **({"los": los} if los != "unit" else {}),
            # NML-1161: WHICH menu the game played. Stamped only under
            # "resolve", for the same reason `deployment` is only stamped under
            # "arena": a default game is the object it was before the knob.
            **({"menu_los": menu_los} if menu_los != "planner" else {}),
            # W1: WHICH menu the game played. Stamped only under "table", the
            # `menu_los` idiom above: a default game is the object it was
            # before this knob existed, so no digest and no corpus moves.
            **({"menu_wide": menu_wide} if menu_wide != "off" else {}),
            # NML-1147a: WHICH marker layout the game played (D8a). Gen-0's
            # rulebook corpus recorded exactly what a constants corpus records
            # until this key existed — the mode was honoured but never said.
            "objectives": eff_objectives,
            # NML-1152 step 8: WHICH pre-game deployment the game played —
            # stamped only under "arena" for the same reason objectives_layout
            # is only present when the rulebook generator ran: a default game
            # is the same object it was before this knob existed.
            **({"deployment": eff_deployment} if eff_deployment != "zone" else {}),
            "engage_fold": engage_fold,
            "dangerous_end_morale": dangerous_end_morale,
            "cond_ap": cond_ap,
            # NML-1142: WHICH brain played. `""` is the hand eval — every corpus
            # written before this knob existed, and the default still.
            "net": str(net) if net is not None else "",
            "net_player": net_player,
            # NML-1158a: the fitted share this game's leaf scores blended with
            # (NML-1147a pattern). 0.5 is `FIT_BLEND_DEFAULT` fitted.rs:35.
            "fit_blend": fit_blend,
            # NML-1158c: the exploration knob this game was played with
            # (NML-1147a pattern, same as `fit_blend` just above). 0.0 is the
            # default — every corpus written before this knob existed played
            # the pure argmax and would stamp the identical value here.
            "explore": explore,
            # NML-1147a pattern: absent at the default 0.0, so every earlier
            # corpus and every default game digests unchanged.
            **({"cap_share": cap_share} if cap_share > 0.0 else {}),
            # NML-1158a: HOW the armed net joined the hand eval — "blend" (the
            # E4.2 mix) or "residual" (hand + delta, the NML-1158a seam). The
            # default is ABSENT, the deployment knob's pattern: every game
            # before this knob existed, and every default game still, digests
            # byte-identically (`result_digest` does not strip `knobs`).
            **({"fit_mode": fit_mode} if fit_mode != "blend" else {}),
        },
        # SEARCH A/B: WHICH resolved depth each seat searched with — present
        # only when the deep seat's pair parted from the base pair, so every
        # other game records the identical object it always did.
        **({"knobs_by_seat": seat_knobs} if seat_knobs else {}),
        # D1-B4 telemetry, empty under `dice="expected"`: how many shooting
        # activations drew from the tray, how many rolls that was, and how many
        # of those activations hit a table branch this port does NOT reproduce
        # (`unported_acts`, then one counter per branch name). An unported
        # branch is a REPORTED divergence, never a silent skip.
        "dice_tally": dice_tally,
        "seed": seed,
        "dice_seed": eff_dice_seed,
        "grades": {"p1": "planner_core", "p2": "planner_core"},
        "mission": {
            "family": mission_def.get("family", "face_off"),
            "name": mission,
            "rounds": ROUNDS,
            "deployment": "zone12",
            "symmetric": True,
            "objective_count": len(owners),
            # D8a: the layout INPUTS, present only when the rulebook generator ran, so
            # a "constant" result is the same object it was before this knob existed.
            **({"objectives_layout": objective_layout} if objective_layout else {}),
            "packs": [],
        },
        "armies": {"p1": str(list_p1), "p2": str(list_p2)},
        "opener": 0,
        "objectives": {"p1": p1, "p2": p2, "neutral": len(owners) - p1 - p2},
        # Expert-iteration step 2: the AUX targets at game end, `record_aux`
        # only (rounds_log, and so the digest, must not move by default).
        **(_aux_alive_wounds(state, profiles) if record_aux else {}),
        "vp": {"p1": int(vp[0]), "p2": int(vp[1])},
        "scoring": eff_scoring,
        "winner": winner,
        "rounds_played": rounds_played,
        "rounds_log": rounds_log,
        "planner_positions": log,
        "planner_calib": [],
        "roster": [u["name"] for u in units],
        # `BattleSim.unknown_rules` — every rule name the committed encoder
        # vocabulary does not carry, collected by the row encoder above. Empty is
        # the only healthy answer, and it is MEASURED, not assumed.
        "unknown_rules": core.unknown_rules(),
        # `_write_result` :739 — the per-game cast counters, measured through the
        # same token deltas and cast log the GDScript reads.
        "magic": magic,
    }


# `main()` (below, :926-ish) stamps this onto a result AFTER `play_game`
# returns it — wall-clock, not game state — so it is the ONLY field on which
# `play_game`'s return value and a written `core_s<seed>.json` can ever
# disagree. Named explicitly so a second timing field never joins the
# exclusion silently; there is no other Python-only field in the result dict
# (see the module docstring's field-by-field accounting).
#
# `dice_tally` (D1-B4) joins it for a different reason: it is a REPORT ABOUT the
# resolution (how many activations drew, how many hit an unported branch), not
# the game. Hashing it would make `dice="table"` differ from `dice="expected"`
# on the counters alone, which is exactly the evidence the B4 test must not be
# allowed to fake — the digests have to part company because the GAME parted.
DIGEST_EXCLUDED_FIELDS = ("wall_seconds", "dice_tally")


def result_digest(result: dict) -> str:
    """GATE Q C4 (NML-1073) — a SHA-256 over the WHOLE game result, canonical
    (recursively sorted keys, floats through Python's own round-trip
    `repr()`, which is what `json.dumps` already calls) so two dicts meaning
    the same game hash the same regardless of key order or which process
    built them.

    This replaces the narrow digest `tools/throughput.py` used to compute
    inline (`winner`, `vp`, `objectives` and a 4-tuple per pick — ~161 numbers
    on a typical game). That digest is blind to the training data itself: it
    cannot see a `planner_positions` row's `board` / `ids` / `features` /
    `value` / `pair` / `fork` (the sidecars a training run actually
    consumes), `terrain`, or `magic` — so it produced the SAME hash for the
    pre-#392 quality/defense encoding, for a deliberately shifted terrain
    board, and for `sidecars=False`. `result_digest` does not: every field
    `play_game` returns is in scope except `DIGEST_EXCLUDED_FIELDS`."""
    body = {k: v for k, v in result.items() if k not in DIGEST_EXCLUDED_FIELDS}
    canonical = json.dumps(body, sort_keys=True, ensure_ascii=True, allow_nan=True)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def fit_blend_arg(text: str) -> float:
    """`--fit-blend`'s argparse type (NML-1158 arm a): parse and pin to 0..1 —
    a junk value must fail the ARGUMENT with a clean error, not silently
    reshape the E4.2 blend (`AiMissionEval.fit_blend` clamps; the trainer
    refuses instead, so a typo cannot impersonate a measurement)."""
    v = float(text)
    if not (0.0 <= v <= 1.0):
        raise argparse.ArgumentTypeError(
            "--fit-blend must be within 0..1, got %r" % (text,)
        )
    return v


def explore_arg(text: str) -> float:
    """`--explore`'s argparse type (NML-1158c): parse and pin to 0..1, the
    same clean-refusal shape as `fit_blend_arg` — a typo must not silently
    turn into an exploration rate nobody asked for."""
    v = float(text)
    if not (0.0 <= v <= 1.0):
        raise argparse.ArgumentTypeError(
            "--explore must be within 0..1, got %r" % (text,)
        )
    return v


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
    ap.add_argument("--no-sidecars", action="store_true", help="skip the pair/fork blocks")
    ap.add_argument("--fork-salt", type=int, default=0, help="NML_FORK_SALT — shifts ONLY the fork dice")
    ap.add_argument(
        "--sidecar-skip",
        type=int,
        default=0,
        help="RED PROOF: advance every sidecar generator by N draws",
    )
    ap.add_argument(
        "--top-k",
        type=int,
        default=None,
        help="planner ROLLOUT_TOP_K override; default is NML_TOP_K env or 6 (ai_planner.gd:49-56)",
    )
    ap.add_argument(
        "--horizon",
        type=int,
        default=None,
        help="planner ROLLOUT_HORIZON_ROUNDS override; default is NML_HORIZON env or 2 (ai_planner.gd:290-297)",
    )
    ap.add_argument(
        "--charge-gate",
        choices=list(CHARGE_GATE_MODES),
        default="table",
        help="'table' (default) wires SoloController.charge_candidate_illegal; "
        "'off' is tools/core_selfplay.gd, which stamps no gate at all",
    )
    ap.add_argument(
        "--menu-targets",
        action="store_true",
        help="NML-1157: the MENU treats a joined Hero as part of its host (GF "
        "v3.5.1 p.14) and offers the charge the unit can REACH beside the one it "
        "scores best; default off, which is the menu every recorded corpus carries",
    )
    ap.add_argument(
        "--menu-wide",
        choices=list(MENU_WIDE_MODES),
        default="off",
        help="W1: 'table' offers the ADVANCE+shoot candidates AiPlanner."
        "candidates_wide has carried since 16.08. (ai_planner.gd:1145-1157), so the "
        "search can fire without standing still; 'off' (default) is the menu every "
        "recorded corpus carries",
    )
    ap.add_argument(
        "--hero-last",
        action="store_true",
        help="NML-1157: a volley or charge aimed at a JOINED HERO resolves to its "
        "HOST while the host has living models (GF v3.5.1 p.14); needs "
        "--hero-attach table, and default off so every recorded bundle replays",
    )
    ap.add_argument(
        "--cast-fold",
        action="store_true",
        help="NML-1157: read the CASTER off the whole activating chain (host + its "
        "alive attached heroes) instead of the host alone; needs --hero-attach table, "
        "and without it a joined Caster hero never casts however seam_cast is set",
    )
    ap.add_argument(
        "--hero-attach",
        choices=list(HERO_ATTACH_MODES),
        default="off",
        help="'table' derives attached/attached_to from the list's "
        "selectionId/joinToUnit the way BattleSim.capture does; 'off' (default) "
        "is tools/core_selfplay.gd, which joins no hero at all",
    )
    ap.add_argument(
        "--dice",
        choices=list(DICE_MODES),
        default="expected",
        help="'table' is the real dice tray (D1); 'expected' (default) is the "
        "expected-value combat every corpus so far was written with",
    )
    ap.add_argument(
        "--charge-landing",
        choices=list(CHARGE_LANDING_MODES),
        default="off",
        help="'table' asks the table's SECOND engage question after a charge — "
        "the snap that closes the residual base gap must still fit the move "
        "budget the charge left over; 'off' (default) fights every charge that "
        "landed within 1\" of the target's base edge",
    )
    ap.add_argument(
        "--movement",
        choices=list(MOVEMENT_MODES),
        default="rigid",
        help="'table' moves a CHARGE the way the table moves it — per model, "
        "routed by the M4 movement port on the table's arc budget, aimed at the "
        "target's contact boundary; 'rigid' (default) translates the whole unit "
        "by one clamped delta",
    )
    ap.add_argument(
        "--ambush",
        choices=list(AMBUSH_MODES),
        default="off",
        help="'table' plays the Ambush arrival — a reserved unit waits off-table "
        "DORMANT and arrives at a round start from its earliest round on, "
        "alternating sides; 'off' (default) leaves it in reserve for the whole "
        "game, which is what every corpus written before this knob carries. "
        "Only 'arena' deployment sets units aside at all",
    )
    ap.add_argument(
        "--sighting",
        choices=list(SIGHTING_MODES),
        default="unit",
        help="'model' counts a volley the table's way — per model and per "
        "weapon, only the models with both range and line of sight; 'unit' "
        "(default) fires the whole unit, which is what every corpus written "
        "before D6a-B4 carries",
    )
    ap.add_argument(
        "--net",
        default="",
        help="NML-1142 — a netlab/fork_train.py ENCODER net JSON; arms the "
        "fitted eval (`AiMissionEval.fit_mode`, the planner_v1 `eval_fit` bit) "
        "for every activation. Empty (default) plays the hand eval",
    )
    ap.add_argument(
        "--fit-blend",
        type=fit_blend_arg,
        default=0.5,
        help="NML-1158 arm (a) — the fitted share in the E4.2 blend "
        "(1 - fb) * hand + fb * fit. 0.5 default = the table's blend; "
        "1.0 = pure net, 0.0 = pure hand. Stamped into knobs",
    )
    ap.add_argument(
        "--fit-mode",
        choices=("blend", "residual"),
        default="blend",
        help="NML-1158 arm (a) — how the armed net joins the hand eval: "
        "'blend' is the E4.2 mix; 'residual' plays hand + net_delta (the "
        "net's sigmoid read as a delta on the hand scale, neutral at 0.5). "
        "Stamped into knobs when not the default",
    )
    ap.add_argument(
        "--net-player",
        type=int,
        default=0,
        choices=(0, 1, 2),
        help="RESEARCH SEAM (no table twin): 0 = the armed eval plays both "
        "seats, 1 or 2 = only that seat plays the net, for a head-to-head A/B",
    )
    ap.add_argument(
        "--explore",
        type=explore_arg,
        default=0.0,
        help="NML-1158c — with this probability per activation, pick "
        "uniformly among the rolled top-K pool instead of the argmax. 0.0 "
        "default = today's argmax behaviour, byte-identical. Drawn from a "
        "dedicated stream, never the game's dice; stamped into knobs and "
        "into each row's `explored` key",
    )
    ap.add_argument(
        "--mission", default="duel",
        help="a catalog id from assets/solo/missions.json; 'duel' (default) is byte-identical",
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
            sidecars=not a.no_sidecars,
            fork_salt=a.fork_salt,
            sidecar_skip=a.sidecar_skip,
            top_k=a.top_k,
            horizon=a.horizon,
            charge_gate=a.charge_gate,
            menu_targets=a.menu_targets,
            menu_wide=a.menu_wide,
            hero_last=a.hero_last,
            cast_fold=a.cast_fold,
            hero_attach=a.hero_attach,
            dice=a.dice,
            charge_landing=a.charge_landing,
            movement=a.movement,
            ambush=a.ambush,
            sighting=a.sighting,
            net=a.net or None,
            net_player=a.net_player,
            fit_blend=a.fit_blend,
            explore=a.explore,
            fit_mode=a.fit_mode,
            mission=a.mission,
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
