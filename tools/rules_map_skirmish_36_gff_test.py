"""The shared 3.6 rows of the skirmish mechanics maps (data lane, 0.3.16).

The 3.6 wave finished the full-scale games: the gf/aof maps carry the new
shared core rows (Assault, Shred, Surge, Spell Amplifier, Brace/Parry), the
3.6 Artillery and Indirect knobs, the Sergeant attack bonus and the two-pick
Banner/Musician scope. The gff/aofs/aofr maps are still the 3.5 export, so a
3.6 skirmish game plays 3.6 engine rules on 3.5 data. These pins hold the
ported rows per system so the set cannot drift again.

Reads the committed maps only (no private books), like the modelled-name
hygiene test.
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

ARTILLERY_36 = {
    "shooter_hit_bonus": 1,
    "target_hit_penalty": 2,
    "target_hit_penalty_v36": 1,
    "target_over_in": 12.0,
    "over_in": 9.0,
    "shooter_over_in": 12.0,
    "shooter_requires_hold": True,
    "hold_only": True,
}

INDIRECT_36 = {
    "moved_hit_penalty": 1,
    "ignores_cover": True,
    "ignores_los": True,
    "hold_and_shoot": True,
    "los_needs_hold": True,
    "cover_needs_hold": True,
}

SHARED_ADD_ROWS = {
    "Assault": {"primitive": "Assault", "rated": False, "book_version": "3.6.0",
                "params": {"melee_copy": True}},
    "Shred": {"primitive": "Shred", "rated": False, "book_version": "3.6.0",
              "params": {"extra_wound_per_save_one": 1}},
    "Surge": {"primitive": "Surge", "rated": False, "book_version": "3.6.0",
              "params": {"bonus_hits_per_six": 1}},
    "Spell Amplifier": {"primitive": "Spell Amplifier", "rated": False, "book_version": "3.6.0",
                        "params": {"casting_mod": 1}},
    "Unique Hero": {"primitive": "Hero", "rated": False, "book_version": "3.6.0"},
}

SPECS = {
    "gff": {
        "add": dict(SHARED_ADD_ROWS, **{
            "Brace": {"primitive": "Brace", "rated": True, "book_version": "3.6.0",
                      "params": {"rating": "X"}},
            "Parry": {"primitive": "Parry", "rated": True, "book_version": "3.6.0",
                      "params": {"rating": "X"}},
        }),
        "params": {
            "Sergeant": {"ap_bonus": 1, "model_level": True},
            "Artillery": ARTILLERY_36,
            "Indirect": INDIRECT_36,
            "Banner": {"morale_bonus": 1, "picked_units": 2, "scope": "picked"},
            "Musician": {"move_bonus_in": 1, "picked_units": 2, "scope": "picked"},
        },
        "remove": ["Entrenched"],
    },
}


def _load(system: str) -> dict:
    return json.loads((REPO / "assets" / "solo" / f"rules_mechanics_{system}.json").read_text())


def check(system_map: dict, spec: dict) -> list[str]:
    problems: list[str] = []
    common = system_map.get("common", {})
    modeled = set(system_map.get("modeled", []))
    for name, entry in spec.get("add", {}).items():
        if common.get(name) != entry:
            problems.append(f"common/{name} is not the 3.6 row: {common.get(name)!r}")
        if name not in modeled:
            problems.append(f"modeled list does not carry {name}, so the row would sit unused")
    for name, params in spec.get("params", {}).items():
        entry = common.get(name, {})
        if entry.get("params") != params:
            problems.append(f"common/{name} params are not the 3.6 knobs: {entry.get('params')!r}")
    for name in spec.get("remove", []):
        if name in common:
            problems.append(f"common/{name} is a 3.5 row the 3.6 books dropped")
    return problems


def test_the_skirmish_maps_carry_the_shared_36_rows() -> None:
    offenders = [
        f"{system}: {problem}"
        for system, spec in SPECS.items()
        for problem in check(_load(system), spec)
    ]
    assert not offenders, "the skirmish maps are not on the shared 3.6 rows:\n" + "\n".join(offenders)


def _clean_map(spec: dict) -> dict:
    common = copy.deepcopy(spec.get("add", {}))
    for name, params in spec.get("params", {}).items():
        common[name] = {"primitive": name, "rated": False, "book_version": "3.5.1", "params": copy.deepcopy(params)}
    return {"common": common, "modeled": list(spec.get("add", {}))}


def test_the_check_reports_each_planted_fault() -> None:
    spec = SPECS["gff"]
    assert not check(_clean_map(spec), spec), "the clean map must pass, else this control proves nothing"
    broken = _clean_map(spec)
    del broken["common"]["Shred"]
    broken["common"]["Artillery"]["params"]["over_in"] = 12.0
    broken["common"]["Entrenched"] = {"primitive": "Stealth"}
    broken["modeled"] = [n for n in broken["modeled"] if n != "Unique Hero"]
    found = check(broken, spec)
    assert any("common/Shred" in f for f in found), found
    assert any("common/Artillery" in f for f in found), found
    assert any("common/Entrenched" in f for f in found), found
    assert any("Unique Hero" in f for f in found), found
