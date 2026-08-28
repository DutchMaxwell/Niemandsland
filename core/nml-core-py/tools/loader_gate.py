#!/usr/bin/env python
"""GATE M3-9 (NML-1097 / NML-1098) — the Godot-free trainer's LIST LOADER
against the arena's own act-header profiles.

Every training game the fast core plays builds its units with
`list_to_profile.py` out of an Army-Forge list JSON. The ARENA plays the very
same lists through the table's full import path (`OPRApiClient` ->
`OPRArmyManager` -> `GameUnit`) and `AiActRecorder` stamps the resulting
`BattleSim._unit_profile` (battle_sim.gd:1610-1643) into every game's act-corpus
HEADER, under `profiles`. So the header IS the table's answer to "what is this
unit", recorded from the same list the trainer reads — an oracle for the loader
that costs nothing to consult.

WHAT IS HELD, per game, per side, per unit:

  (1) ALIGNMENT — the arena spawns a joined hero right after its host while the
      trainer keeps roster order, and `unit_id` is a runtime token on one side
      and a roster index on the other. So units are paired by IDENTITY
      (`hero_attach_gate.ident`: name / quality / defense / model count /
      wounds), duplicates in order of appearance. A side whose identity
      multisets differ is counted as MISALIGNED and contributes no field rows —
      nothing below means anything if the two are not looking at the same
      roster.

  (2) THE STATIC PROFILE — every field of the header profile except `unit_id`:
      base radius, effective rule set, weapons, tough / quality / defense,
      wounds, model count, caster value, move bands (advance + rush), item
      grants, attached-hero rules, game system, faction folder.

  (3) THE TWO DYNAMIC FIELDS — `shooting_range_bonus` and
      `max_activation_advance_bonus_in` live in `unit_profile_dyn`
      (battle_sim.gd:1665-1676), not in the header, so they are read off the
      FIRST act's per-unit `prof`. The first act is round 1's first activation,
      recorded BEFORE it resolves, so that reading is deployment-time — the same
      instant the header was written.

Counts are reported twice, because 168 games replay 18 rosters: `units` is the
number of DISTINCT roster units (list file + identity) that ever mismatch —
that is the number a fix has to move — and `rows` is the raw per-game count.

RED PROOF: two knobs that corrupt the TRAINER's side only, so the gate must go
red on exactly one column and stay green on the rest.

  --red-base-mm N     overwrite every trainer base radius with (N/2) mm
  --red-drop-rule R   drop rule R from every trainer unit's `special_rules`

    ~/venvs/nmlloader/bin/python core/nml-core-py/tools/loader_gate.py \\
        --ref ~/selfplay_out/qbf_ref --lists ~/ai_lists_gf
    ~/venvs/nmlloader/bin/python core/nml-core-py/tools/loader_gate.py \\
        --ref ~/selfplay_out/qbf_ref --lists ~/ai_lists_gf --red-base-mm 99
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import selfplay as sp  # noqa: E402
from hero_attach_gate import arena_reading, games, ident  # noqa: E402

#: Header profile fields, in report order. `unit_id` is deliberately absent —
#: it is a runtime token on one side and a roster index on the other.
STATIC_FIELDS = (
    "base_radius",
    "special_rules",
    "item_grants",
    "attached_hero_rules",
    "move_bands",
    "weapons",
    "tough",
    "quality",
    "defense",
    "model_count",
    "wounds_max",
    "caster_value",
    "name",
    "game_system",
    "faction_folder",
)

#: `unit_profile_dyn` fields, read off the first act's `prof` (see the docstring).
DYN_FIELDS = ("shooting_range_bonus", "max_activation_advance_bonus_in")

FIELDS = STATIC_FIELDS + DYN_FIELDS


def _eq(a, b) -> bool:
    """Field equality. Floats compare with an absolute tolerance (the arena
    writes `0.0125 * 1.6` and JSON round-trips it), everything else exactly."""
    if isinstance(a, bool) or isinstance(b, bool):
        return a is b or a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return math.isclose(float(a), float(b), rel_tol=0.0, abs_tol=1e-9)
    if isinstance(a, dict) and isinstance(b, dict):
        return set(a) == set(b) and all(_eq(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_eq(x, y) for x, y in zip(a, b))
    return a == b


def _short(v) -> str:
    s = json.dumps(v, sort_keys=True, default=str)
    return s if len(s) <= 90 else s[:87] + "..."


def trainer_army(list_path: Path, player: int, hero_attach: bool) -> list[dict]:
    """One side's trainer profiles, built exactly as `selfplay.play_game` builds
    them — including the D4 `attached_hero_rules` pass, which lives in
    `play_game` and not in the loader."""
    units = sp.load_army(list_path, player)
    if hero_attach:
        attached, _ = sp.derive_attachment(units, sp.load_selections(list_path, player))
        by_id = {u["unit_id"]: u for u in units}
        for u in units:
            u["attached_hero_rules"] = [
                by_id[h]["special_rules"] for h in attached[u["unit_id"]]
            ]
    return units


def redden(units: list[dict], base_mm: float | None, drop_rule: str | None) -> None:
    """The RED knobs — corrupt the trainer side so a named column must fail."""
    for u in units:
        if base_mm is not None:
            u["base_radius"] = (base_mm / 2.0) * 0.001
        if drop_rule:
            u["special_rules"] = [r for r in u["special_rules"] if r != drop_rule]
            u["attached_hero_rules"] = [
                [r for r in hero if r != drop_rule] for hero in u["attached_hero_rules"]
            ]


def arena_side_units(profiles: dict, aunits: dict) -> dict[int, list[dict]]:
    """The arena's per-side profiles in recorded order, each merged with the two
    dynamic fields off the same unit's first-act `prof`."""
    out: dict[int, list[dict]] = {1: [], 2: []}
    for key, su in aunits.items():
        prof = dict(profiles[key])
        for f in DYN_FIELDS:
            if f in su.get("prof", {}):
                prof[f] = su["prof"][f]
        out[int(su["player"])].append(prof)
    return out


def pair_by_ident(arena: list[dict], trainer: list[dict]) -> list[tuple[dict, dict]] | None:
    """1:1 pairing by identity, duplicates in order of appearance. `None` when
    the two identity multisets differ — see (1) in the module docstring."""
    if Counter(ident(p) for p in arena) != Counter(ident(u) for u in trainer):
        return None
    buckets: dict[tuple, list[dict]] = defaultdict(list)
    for u in trainer:
        buckets[ident(u)].append(u)
    seen: Counter = Counter()
    pairs = []
    for p in arena:
        k = ident(p)
        pairs.append((p, buckets[k][seen[k]]))
        seen[k] += 1
    return pairs


def compare_game(
    profiles: dict, aunits: dict, sides: dict[int, list[dict]]
) -> tuple[list[tuple], list[int]]:
    """`(rows, misaligned_sides)`. A row is
    `(side, unit name, field, arena value, trainer value)`."""
    arena = arena_side_units(profiles, aunits)
    rows: list[tuple] = []
    misaligned: list[int] = []
    for side in (1, 2):
        pairs = pair_by_ident(arena[side], sides[side])
        if pairs is None:
            misaligned.append(side)
            continue
        for want, got in pairs:
            for f in FIELDS:
                if f not in want:
                    continue
                if not _eq(want[f], got.get(f)):
                    rows.append((side, str(want.get("name", "?")), f, want[f], got.get(f)))
    return rows, misaligned


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", required=True, help="directory of <p1>_vs_<p2>_s<seed> dirs")
    ap.add_argument(
        "--lists",
        default=str(Path("~/ai_lists_gf").expanduser()),
        help="directory the army list JSONs live in",
    )
    ap.add_argument("--pairing", default="", help="substring filter on <p1>_vs_<p2>")
    ap.add_argument(
        "--hero-attach",
        choices=("table", "off"),
        default="table",
        help="'table' derives attachment as play_game does (the arena's own setting)",
    )
    ap.add_argument("--max-detail", type=int, default=25, help="per-field example rows to print")
    ap.add_argument("--report-only", action="store_true", help="never exit 1")
    ap.add_argument("--red-base-mm", type=float, default=None, help="RED: force every base to N mm")
    ap.add_argument("--red-drop-rule", default=None, help="RED: drop this rule from every unit")
    args = ap.parse_args(argv)

    ref, lists = Path(args.ref).expanduser(), Path(args.lists).expanduser()
    todo = games(ref, None, args.pairing)
    if not todo:
        print("no games under %s" % ref)
        return 0 if args.report_only else 1

    cache: dict[tuple[str, int], list[dict]] = {}
    #: field -> distinct (list stem, identity) that mismatch; and raw row count.
    units_hit: dict[str, set] = {f: set() for f in FIELDS}
    rows_hit: Counter = Counter()
    games_hit: dict[str, set] = {f: set() for f in FIELDS}
    examples: dict[str, dict[tuple, tuple]] = {f: {} for f in FIELDS}
    misaligned = 0
    clean_games = 0
    total_units = 0
    seen_units: set = set()

    for pair, p1, p2, _seed, d in todo:
        try:
            profiles, aunits = arena_reading(d)
        except (OSError, json.JSONDecodeError):
            continue
        sides = {}
        for side, stem in ((1, p1), (2, p2)):
            key = (stem, side)
            if key not in cache:
                cache[key] = trainer_army(
                    lists / ("%s.json" % stem), side, args.hero_attach == "table"
                )
            sides[side] = [dict(u) for u in cache[key]]
            redden(sides[side], args.red_base_mm, args.red_drop_rule)
        stems = {1: p1, 2: p2}
        rows, mis = compare_game(profiles, aunits, sides)
        misaligned += len(mis)
        for side, stem in stems.items():
            if side not in mis:
                for u in sides[side]:
                    seen_units.add((stem, ident(u)))
        total_units += sum(len(sides[s]) for s in (1, 2) if s not in mis)
        if not rows:
            clean_games += 1
        for side, name, field, want, got in rows:
            units_hit[field].add((stems[side], name))
            rows_hit[field] += 1
            games_hit[field].add(d.name)
            ex_key = (stems[side], name)
            if ex_key not in examples[field] and len(examples[field]) < args.max_detail:
                examples[field][ex_key] = (stems[side], name, want, got)

    print("ref            %s" % ref)
    print("lists          %s" % lists)
    print("hero_attach    %s" % args.hero_attach)
    if args.red_base_mm is not None or args.red_drop_rule:
        print("RED            base_mm=%s drop_rule=%s" % (args.red_base_mm, args.red_drop_rule))
    print(
        "games          %d compared, %d field-clean, %d misaligned sides"
        % (len(todo), clean_games, misaligned)
    )
    print("units          %d distinct roster units, %d unit-readings" % (len(seen_units), total_units))
    print()
    print("%-32s %8s %8s %8s" % ("field", "units", "rows", "games"))
    bad = 0
    for f in FIELDS:
        if not rows_hit[f]:
            continue
        bad += 1
        print("%-32s %8d %8d %8d" % (f, len(units_hit[f]), rows_hit[f], len(games_hit[f])))
    if not bad:
        print("%-32s %8d %8d %8d" % ("(none)", 0, 0, 0))
    print()
    for f in FIELDS:
        if not examples[f]:
            continue
        print("--- %s (%d distinct units)" % (f, len(units_hit[f])))
        for stem, name, want, got in examples[f].values():
            print("  %-26s %-24s arena=%s" % (stem, name, _short(want)))
            print("  %-26s %-24s train=%s" % ("", "", _short(got)))
        if len(units_hit[f]) > len(examples[f]):
            print("  ... %d more" % (len(units_hit[f]) - len(examples[f])))
        print()

    failed = bool(rows_hit) or misaligned > 0
    print("VERDICT        %s" % ("RED" if failed else "GREEN"))
    return 1 if (failed and not args.report_only) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
