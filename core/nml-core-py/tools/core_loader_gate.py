#!/usr/bin/env python
"""GATE M3-10 (NML-1105) — `tools/core_selfplay.gd`'s LIST LOADER against the
arena's own act-header profiles.

The sibling of `loader_gate.py`. That one holds the Godot-free trainer's
`list_to_profile.py` against the table; this one holds the GODOT ORACLE that
records the M3 reference sidecars — `tools/core_selfplay.gd` — against the same
oracle. Both tools stamp `BattleSim._unit_profile` (battle_sim.gd) into their
act-corpus HEADER (`act_recorder.gd:_header_line`, env `NML_ACT_DUMP`), so the
two headers are directly comparable for the SAME two lists.

WHY IT EXISTS: core_selfplay built its units in its own `_units_from_list`,
which the table's import path had long outgrown — 32 mm bases for everyone (no
`bases`, no Tough fallback), no item grants, no aura expansion, no hero
attachment, and rule names parsed out of upgrade LABEL text. Every reference
corpus the M3 ladder is gated against carries that reading. NML-1105 routes the
harness through `OPRApiClient.build_army_offline` +
`EquipmentDistributor.create_from_opr_unit` + `OPRArmyManager`'s two post-spawn
passes, i.e. exactly what `tools/arena_match.gd` runs.

RECIPE (one seed is enough — the header profile is deployment-time static):

    NML_ACT_DUMP=<dir> NML_ACT_DUMP_MAX=2 godot --headless --path . \\
        -s res://tools/core_selfplay.gd -- \\
        army1=~/ai_lists_gf/robot_legions_1000.json \\
        army2=~/ai_lists_gf/blessed_sisters_1000.json seed=27 games=1 out=<dir>

    python core/nml-core-py/tools/core_loader_gate.py \\
        --core <dir>/acts.jsonl \\
        --arena ~/selfplay_out/qbf_ref/robot_legions_1000_vs_blessed_sisters_1000_s27/acts.jsonl

ALIGNMENT: units are paired by NAME in order of appearance (both headers come
from the same two list files, so the name multiset is the alignment claim
itself). A name only one side knows is reported and contributes no field rows.

RESIDUE: `move_bands` may legitimately differ — the arena resolves an army-book
rule DESCRIPTION into a movement modifier, and the description arrives over the
network (`_fetch_army_book`), which a headless harness never calls. Fields the
two recordings do not share (one side recorded before a profile field existed)
are listed under SKIPPED, never counted as mismatches.

Exit code 0 when every compared field matches, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

#: Header profile fields worth holding, in report order. `unit_id` is absent by
#: design: a runtime token on the arena side, a deterministic harness id on the
#: core side (core_selfplay.gd keeps its own so a corpus can be replayed).
FIELDS = (
    "base_radius",
    "base_shape",
    "base_w_mm",
    "base_d_mm",
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
    "game_system",
    "faction_folder",
)


def header_profiles(path: Path) -> dict:
    """The `profiles` dict of an act corpus's header line, keyed by unit_id."""
    with path.open() as fh:
        head = json.loads(fh.readline())
    if head.get("kind") != "header":
        raise SystemExit("%s: first line is not an act header" % path)
    return head.get("profiles", {})


def by_name(profiles: dict) -> dict:
    """name -> [profile, ...] in the header's own key order."""
    out = defaultdict(list)
    for prof in profiles.values():
        out[str(prof.get("name", ""))].append(prof)
    return out


def norm(value):
    """Compare-ready form: floats rounded (0.020000000000000004 == 0.02)."""
    if isinstance(value, float):
        return round(value, 6)
    if isinstance(value, list):
        return [norm(v) for v in value]
    if isinstance(value, dict):
        return {k: norm(v) for k, v in sorted(value.items())}
    return value


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--core", required=True, type=Path, help="core_selfplay acts.jsonl")
    ap.add_argument("--arena", required=True, type=Path, help="arena_match acts.jsonl")
    ap.add_argument("--quiet", action="store_true", help="counts only, no per-unit lines")
    args = ap.parse_args()

    core, arena = by_name(header_profiles(args.core)), by_name(header_profiles(args.arena))

    only_core = sorted(set(core) - set(arena))
    only_arena = sorted(set(arena) - set(core))
    paired = [(n, c, a) for n in sorted(set(core) & set(arena))
              for c, a in zip(core[n], arena[n])]

    fields = [f for f in FIELDS
              if all(f in c and f in a for _, c, a in paired)] if paired else []
    skipped = [f for f in FIELDS if f not in fields]

    mismatches = defaultdict(list)
    for name, c, a in paired:
        for f in fields:
            if norm(c[f]) != norm(a[f]):
                mismatches[f].append((name, c[f], a[f]))

    print("units paired: %d | only in core: %s | only in arena: %s"
          % (len(paired), only_core or "-", only_arena or "-"))
    print("fields compared: %d (%s)" % (len(fields), ", ".join(fields)))
    if skipped:
        print("fields SKIPPED (absent from one recording): %s" % ", ".join(skipped))
    total = sum(len(v) for v in mismatches.values())
    for f in fields:
        rows = mismatches.get(f, [])
        print("  %-22s %d mismatch(es)" % (f, len(rows)))
        if rows and not args.quiet:
            for name, cv, av in rows:
                print("      %-20s core=%s" % (name, json.dumps(cv, sort_keys=True)))
                print("      %-20s arena=%s" % ("", json.dumps(av, sort_keys=True)))
    print("TOTAL mismatching rows: %d over %d units x %d fields"
          % (total, len(paired), len(fields)))
    return 0 if total == 0 and not only_core and not only_arena else 1


if __name__ == "__main__":
    sys.exit(main())
