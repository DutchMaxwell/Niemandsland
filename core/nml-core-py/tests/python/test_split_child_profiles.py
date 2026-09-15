"""SPLIT step 2 (D-SPLIT, decided 15.09.) — the army-list loader ships the
Split child templates into the header map.

Option (b) of analysis/SPLIT_STEP2_2026-09-14.md: a FRESH core sim refuses a
fielded `Split(<name> [<n>])` carrier at load (io.rs:1111 `spawn_templates_of`)
until the header carries the child's template under
`spawn:<carrier_key>:<rule string>` — the same seam #949 gave RECORDED games
(`act_recorder.gd:_spawn_profiles`, indexed on the fresh path too by
`acts.rs:header_of` -> `io.rs:index_spawn_profiles`). The child's profile is
resolved by the table's NAMED BOOK lookup (main.gd:18135-18138 ->
opr_api_client.gd:1792-1800): scan the book's `units` for the string's name,
build a FULL fresh unit, stamp `size = count` — never off the parent (the
#823 silent-fallback ruling). The book comes off the table's own snapshot
instrument (`NML_ARMY_BOOKS_DIR`, `<dir>/<system>/<armyId>.json`).

RED while `list_to_profile` has no spawn-profiles builder: the call raises
AttributeError and this file fails the suite (the tools/python suite runs in
CI, workflow rust.yml).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))

import list_to_profile  # noqa: E402

SYSTEM = "gf"
ARMY_ID = "testbook123"
FACTION = "testfaction"

#: The book the named lookup scans — the child's OWN values, deliberately
#: different from the carriers' (the e2e fixture's shape: carrier Q4/D4, child
#: Q5/D5, e2e_split_test.gd:41-45 vs :62).
BOOK = {
    "name": "Test Book",
    "units": [
        {
            "id": "goblin_mob",
            "name": "Goblin Mob",
            "quality": 5,
            "defense": 3,
            "size": 6,
            "specialRules": [{"name": "Tough", "rating": 1}],
            "equipment": [{"name": "Claws", "range": 0, "attacks": 1, "count": 4}],
            "bases": {"round": "25"},
        },
        {
            "id": "rat_swarm",
            "name": "Rat Swarm",
            "quality": 3,
            "defense": 5,
            "size": 4,
            "specialRules": [{"name": "Tough", "rating": 2}],
            "equipment": [{"name": "Bite", "range": 0, "attacks": 2}],
            "bases": {"round": "25"},
        },
    ],
}

#: One Split carrier per seat — the fresh sim's two child units, the pair the
#: header map must carry when the core loads the game.
LIST_P1 = {
    "gameSystem": SYSTEM,
    "units": [
        {
            "id": "brood",
            "selectionId": "s1",
            "name": "Hatchling Brood",
            "quality": 4,
            "defense": 4,
            "size": 3,
            "rules": [{"name": "Split(Goblin Mob [4])"}],
            "weapons": [],
            "armyId": ARMY_ID,
        }
    ],
}
LIST_P2 = {
    "gameSystem": SYSTEM,
    "units": [
        {
            "id": "mother",
            "selectionId": "s2",
            "name": "Rat Mother",
            "quality": 4,
            "defense": 4,
            "size": 2,
            "rules": [{"name": "Split(Rat Swarm [2])"}],
            "weapons": [],
            "armyId": ARMY_ID,
        }
    ],
}


def test_the_loader_ships_both_split_child_templates_with_their_book_size(
    tmp_path, monkeypatch, capsys
):
    """A list with a fielded `Split(<name> [<n>])` carrier loads through the
    loader with BOTH child templates in the header map — keyed
    `spawn:<carrier_key>:<rule string>` the way #949's replay reader expects,
    each child the BOOK's own profile at `size = count`, and one printed line
    per template shipped (the rules-must-log)."""
    book_dir = tmp_path / "books" / SYSTEM
    book_dir.mkdir(parents=True)
    (book_dir / (ARMY_ID + ".json")).write_text(json.dumps(BOOK), encoding="utf-8")
    monkeypatch.setenv("NML_ARMY_BOOKS_DIR", str(tmp_path / "books"))
    list_p1 = tmp_path / (SYSTEM + "_" + FACTION + "_1000.json")
    list_p2 = tmp_path / (SYSTEM + "_" + FACTION + "_1000_b.json")
    list_p1.write_text(json.dumps(LIST_P1), encoding="utf-8")
    list_p2.write_text(json.dumps(LIST_P2), encoding="utf-8")

    spawn_profiles = list_to_profile.spawn_profiles_from_list(list_p1, 1)
    spawn_profiles.update(list_to_profile.spawn_profiles_from_list(list_p2, 2))

    gob_key = "spawn:p1_0_brood:Split(Goblin Mob [4])"
    rat_key = "spawn:p2_0_mother:Split(Rat Swarm [2])"
    assert set(spawn_profiles) == {gob_key, rat_key}
    gob = spawn_profiles[gob_key]
    assert gob["unit_id"] == gob_key
    assert gob["name"] == "Goblin Mob"
    assert gob["model_count"] == 4
    assert gob["wounds_max"] == [1, 1, 1, 1]
    # The NAMED BOOK's own values, not the carrier's 4/4 — parent-side
    # derivation would be the #823 silent-fallback break.
    assert gob["quality"] == 5
    assert gob["defense"] == 3
    rat = spawn_profiles[rat_key]
    assert rat["unit_id"] == rat_key
    assert rat["name"] == "Rat Swarm"
    assert rat["model_count"] == 2
    assert rat["wounds_max"] == [2, 2]
    assert rat["quality"] == 3
    assert rat["defense"] == 5
    # The profiles map stays field-for-field (M3-3): the templates ride the
    # separate header map, like the recorder's write.
    profiles = list_to_profile.profiles_from_list(list_p1, 1)
    assert gob_key not in profiles and rat_key not in profiles
    # Rules-must-log: one line per child template shipped.
    out = capsys.readouterr().out
    assert gob_key in out and rat_key in out