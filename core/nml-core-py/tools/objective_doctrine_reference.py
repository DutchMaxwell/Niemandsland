#!/usr/bin/env python3
"""NML-1140 step 10a — the pyo3 half of the identity smoke.

Writes ONE JSON line — `nml_core.doctrine_place` for the pinned fixture the
GDScript smoke (tools/objective_doctrine_smoke.gd) drives through the
GDExtension in the same run — to the file named in argv[1] (or stdout, when
run by hand to debug). This file and that script are the ONE fixture in two
languages — change both or neither. Identity across the two seams is the
design's whole point (design 0, gate 2(ii)): one implementation in the Rust
core, two consumers, no second copy of the choice logic.

The smoke points NML_DOCTRINE_PYO3_PYTHON at a python that imports the
nml_core built from THIS commit (maturin develop -m core/nml-core-py/Cargo.toml).
A file handoff, not a captured pipe: OS.execute's stdout capture is unreliable
here, and a stale file must never pass for a fresh answer, so the smoke
removes the path before the call.
"""

from __future__ import annotations

import json
import sys

import nml_core

ZONES = {
    "zones": {
        "1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
        "2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]],
    }
}


def _infantry(uid: str) -> dict:
    return {
        "unit_id": uid, "name": "Line Infantry", "quality": 4, "defense": 4, "tough": 1,
        "wounds_max": [1, 1, 1, 1, 1], "model_count": 5,
        "weapons": [
            {"name": "Rifle", "range": 30, "attacks": 2, "count": 1, "ap": 1, "rules": []},
            {"name": "Carbine", "range": 18, "attacks": 1, "count": 2, "ap": 0, "rules": []}],
        "special_rules": [], "caster_value": 0,
        "move_bands": {"advance": 6.0, "rush": 12.0},
        "base_radius": 0.016, "game_system": "gf", "faction_folder": "gf_test",
        "item_grants": [], "attached_hero_rules": [],
        "shooting_range_bonus": 0, "max_activation_advance_bonus_in": 0.0,
    }


def _walker(uid: str, cannon_range: int = 24) -> dict:
    return {
        "unit_id": uid, "name": "Heavy Walker", "quality": 4, "defense": 4, "tough": 6,
        "wounds_max": [6], "model_count": 1,
        "weapons": [{"name": "Cannon", "range": cannon_range, "attacks": 6, "count": 1, "ap": 2, "rules": []}],
        "special_rules": [], "caster_value": 0,
        "move_bands": {"advance": 6.0, "rush": 12.0},
        "base_radius": 0.025, "game_system": "gf", "faction_folder": "gf_test",
        "item_grants": [], "attached_hero_rules": [],
        "shooting_range_bonus": 0, "max_activation_advance_bonus_in": 0.0,
    }


def _army(prefix: str) -> dict:
    return {
        "%s_0_inf" % prefix: _infantry("%s_0_inf" % prefix),
        "%s_1_walker" % prefix: _walker("%s_1_walker" % prefix),
    }


def main() -> None:
    line = json.dumps(
        nml_core.doctrine_place(None, "search", (_army("p1"), _army("p2")), 3, ZONES))
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w", encoding="utf-8") as f:
            f.write(line)
    else:
        print(line)


if __name__ == "__main__":
    main()
