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

import hashlib
import json
import os
import re
import struct
from pathlib import Path
from typing import Any

import nml_core

from list_to_profile import (
    _faction_from_path,
    profiles_from_army_forge_json,
    selections_from_army_forge_json,
)

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


#: `charge_gate` modes. "off" is the default and is what the OLD planner-lane
#: trainer does: `tools/core_selfplay.gd` never stamps `state["charge_illegal"]`,
#: so both planner menu sites read `illegal_cb.is_valid()` as false
#: (ai_planner.gd:1024/1308) and offer charges the table would refuse. "table"
#: wires the gate the ARENA wires — `SoloController.charge_candidate_illegal`
#: (solo_controller.gd:1450, stamped at :3002/:3358/:3475/:3704) — through its
#: pure twin `gate::charge_illegal` (NML-1073 M2-0c), whose five inputs the
#: capture already carries per unit: `aircraft`, the rush `bands`, the melee
#: `shroud` pair, `charge_no_difficult` (the p.13 Strider/Flying exemption) and
#: `charge_probe_r` (the unit footprint), against the header board's difficult
#: ground. Nothing else changes, so "off" stays byte-identical to every corpus
#: written before this knob existed.
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


def resolve_dice(dice: str) -> str:
    """The validated `dice` mode. An unknown mode RAISES rather than falling
    back to "expected": a corpus that silently recorded expected-value combat
    while its file claimed table dice is worse than no corpus."""
    if dice not in DICE_MODES:
        raise ValueError("dice must be one of %s, not %r" % (list(DICE_MODES), dice))
    return dice


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
    still has a living, un-activated unit; `{}` when the side is dry.

    The pool is the PLANNER's own filter (:431-436, player / activated / alive)
    unless the header's `hero_attach` FOLD seam is on. NML-1127: reading that
    seam here rather than folding unconditionally is what lets the harness play
    the oracle's "joined but not folded" game — see `HERO_ATTACH_MODES`."""
    if not state.pool(player, bool(core.knobs().get("hero_attach", True))):
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
) -> tuple[Any, int]:
    """`_play_round` core_selfplay.gd:247-307 — strict one-for-one alternation, a
    dry side hands the tail to the other, and the NEXT round opens with whoever
    did NOT take the last activation.

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
    those activations hit (see `Core.resolve_with_tray`). Nothing else draws
    from the tray in B4 — melee, impact and morale are B5's, which is why the
    stream is left standing exactly before the morale roll."""
    turn = opener
    last_side = 0
    forked = False
    rp_count = 0
    # `state["units"]` is keyed by unit key and the crate's per-unit lists by
    # capture index; the roster never changes shape inside a game.
    at = {k: i for i, k in enumerate(state.keys())}
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
        seq = len(log)
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
            casts_before = state.casts()[actor]
            events_before = len(state.cast_event_kinds())
            _magic_eligibility_tally(
                magic, side_key, state, actor,
                (spell_reach or {}).get(pick["unit_key"], 0.0),
            )
        if tray is None:
            state = core.resolve_stochastic_rng(state, action, rng)
        else:
            state, report = core.resolve_with_tray(state, action, rng, tray)
            if dice_tally is not None:
                dice_tally["activations"] = dice_tally.get("activations", 0) + 1
                dice_tally["rolls"] = dice_tally.get("rolls", 0) + len(report["rolls"])
                if report["unported"]:
                    dice_tally["unported_acts"] = dice_tally.get("unported_acts", 0) + 1
                for name in report["unported"]:
                    dice_tally[name] = dice_tally.get(name, 0) + 1
        if magic is not None:
            _magic_tally(magic, side_key, casts_before, state.casts()[actor])
            _spells_by_kind_tally(magic, side_key, state.cast_event_kinds(), events_before)
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
    sidecars: bool = True,
    fork_salt: int = 0,
    sidecar_skip: int = 0,
    legacy_source_qd: bool = False,
    terrain_shift_cells: int = 0,
    top_k: int | None = None,
    horizon: int | None = None,
    charge_gate: str = "off",
    hero_attach: str = "off",
    dice: str = "expected",
    charge_landing: str = "off",
    movement: str = "rigid",
) -> dict[str, Any]:
    """One full match for `seed` — `_play_one` core_selfplay.gd:164-244.

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
    changes a RULE: "off" (the default) reproduces `tools/core_selfplay.gd`,
    which stamps no `state["charge_illegal"]` and therefore lets the planner
    offer charges against aircraft, past the rush band and through difficult
    ground; "table" wires the arena's own gate. It is stamped into the result's
    `knobs` alongside the search pair — see `CHARGE_GATE_MODES`.

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
    measuring the seed, not the deployment."""
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
    if core is None:
        core = nml_core.load(str(repo_root))
    eff_top_k = resolve_top_k(top_k)
    eff_horizon = resolve_horizon(horizon)
    eff_charge_gate = resolve_charge_gate(charge_gate)
    eff_dice = resolve_dice(dice)
    eff_charge_landing = resolve_charge_landing(charge_landing)
    eff_movement = resolve_movement(movement)
    knobs = dict(
        TRAINER_KNOBS,
        top_k=eff_top_k,
        horizon=eff_horizon,
        charge_gate=eff_charge_gate,
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
    )
    core.set_header({"profiles": profiles, "terrain": terrain, "knobs": knobs})
    # Board columns 10/11 read the GameUnit's `source_data` (battle_sim.gd
    # :233-234), which `tools/core_selfplay.gd` fills from the unit since #392 —
    # so the DEFAULT is the profile's own quality/defense. The 4/4 of a blank
    # `OPRApiClient.OPRUnit` is what a pre-#392 corpus carries and nothing else.
    if legacy_source_qd:
        core.set_encoder_source_qd(SOURCE_DATA_QUALITY, SOURCE_DATA_DEFENSE)
    else:
        core.clear_encoder_source_qd()
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
    tray = nml_core.Tray(seed) if eff_dice == "table" else None
    dice_tally: dict[str, int] = {}
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
    plain = capture(units, pos1 + pos2, reads, board, objectives, attached, attached_to)
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
        _round_start(plain, round_no, profiles, magic)
        state = core.state_of(plain)
        state, opener = _play_round(
            core, state, opener, rng, log, round_no,
            seed=seed, owners=owners, sidecars=sidecars,
            fork_salt=fork_salt, sidecar_skip=sidecar_skip,
            magic=magic, spell_reach=spell_reach, tray=tray, dice_tally=dice_tally,
        )
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
        # `_write_result` :725 — `SchoolTerrain.generate(seed)["pieces"]`, the
        # judge bench's drawing list, straight out of the bank.
        "terrain": _shift_pieces(pieces, terrain_shift_cells),
        "tool": "core_selfplay_py",
        # `tools/core_selfplay.gd` stamps no such field (it always runs the
        # planner's own defaults) — this documents the fast trainer's MODE,
        # e.g. the old training corpus's `NML_TOP_K=2 NML_HORIZON=1`. Excluded
        # from the Godot parity gates alongside the other Python-only extras
        # (sidecar_gate.py's `EXCLUDED_TOP`).
        "knobs": {
            "top_k": eff_top_k,
            "horizon": eff_horizon,
            "charge_gate": charge_gate,
            "hero_attach": hero_attach,
            "dice": eff_dice,
            "charge_landing": charge_landing,
            "movement": movement,
        },
        # D1-B4 telemetry, empty under `dice="expected"`: how many shooting
        # activations drew from the tray, how many rolls that was, and how many
        # of those activations hit a table branch this port does NOT reproduce
        # (`unported_acts`, then one counter per branch name). An unported
        # branch is a REPORTED divergence, never a silent skip.
        "dice_tally": dice_tally,
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
        default="off",
        help="'table' wires SoloController.charge_candidate_illegal; 'off' (default) "
        "is tools/core_selfplay.gd, which stamps no gate at all",
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
            hero_attach=a.hero_attach,
            dice=a.dice,
            charge_landing=a.charge_landing,
            movement=a.movement,
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
