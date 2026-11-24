"""AoF: Skirmish fields one Sergeant, one Musician and one Banner per army: the list loader refuses a second pick of
any one, naming the unit. AoF (one per unit) loads the same list."""
from __future__ import annotations

import copy
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
from list_to_profile import profiles_from_army_forge_json  # noqa: E402


def _warrior(uid: str, name: str, upgrade: str) -> dict:
    return {
        "id": uid, "selectionId": "s" + uid, "name": name, "quality": 4, "defense": 4, "size": 1,
        "rules": [{"label": "Tough(3)", "name": "Tough", "rating": 3}],
        "selectedUpgrades": [{"upgrade": {"label": "Upgrade one model with one"}, "option": {"label": upgrade}}],
        "weapons": [{"name": "Hand Weapon", "range": 0, "attacks": 2, "count": 1}],
    }


ONE_EACH = {"gameSystem": "aofs", "units": [
    _warrior("a", "Guard", "Banner"), _warrior("b", "Spears", "Musician"), _warrior("c", "Archers", "Sergeant")]}
TWO_BANNERS = {"gameSystem": "aofs", "units": [_warrior("a", "Guard", "Banner"), _warrior("b", "Spears", "Banner")]}


def test_one_of_each_command_upgrade_loads_in_skirmish():
    assert len(profiles_from_army_forge_json(copy.deepcopy(ONE_EACH), "havoc_dwarves", 1)) == 3


def test_a_second_banner_is_refused_by_name_in_skirmish():
    with pytest.raises(ValueError, match="Spears: only one Banner per army in this game system"):
        profiles_from_army_forge_json(copy.deepcopy(TWO_BANNERS), "havoc_dwarves", 1)


def test_the_same_two_banners_load_in_aof():
    data = copy.deepcopy(TWO_BANNERS)
    data["gameSystem"] = "aof"
    assert len(profiles_from_army_forge_json(data, "havoc_dwarves", 1)) == 2
