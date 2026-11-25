"""A rule-only upgrade (Banner, Musician, Sergeant, Great Banner) reaches its unit from the selected option's `gains`,
the way the table reads a real Army Forge export - from `EPOCH_98_COMMAND_GAINS` on; one epoch below the list
builds its units without it. A rule that already reaches the unit another way (a loadout item's Caster(2)) stays one
entry on both legs."""
from __future__ import annotations

import sys
from pathlib import Path

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
import list_to_profile as l2p  # noqa: E402

E = nml_core.EPOCH_98_COMMAND_GAINS


def _list() -> dict:
    banner = {"upgrade": {"label": "Upgrade one model with one"},
              "option": {"label": "Banner", "gains": [{"type": "ArmyBookRule", "name": "Banner", "label": "Banner"}]}}
    synapses = {"upgrade": {"label": "Upgrade with one"},
                "option": {"label": "Psychic Synapses (Caster(2))", "gains": [
                    {"type": "ArmyBookItem", "name": "Psychic Synapses", "label": "Psychic Synapses",
                     "content": [{"type": "ArmyBookRule", "name": "Caster", "rating": 2}]},
                    {"type": "ArmyBookRule", "name": "Caster", "rating": 2}]}}
    return {"gameSystem": "gf", "units": [
        {"id": "a", "selectionId": "sa", "name": "Squad", "quality": 4, "defense": 4, "size": 5, "rules": [],
         "selectedUpgrades": [banner], "loadout": [],
         "weapons": [{"name": "Rifle", "range": 24, "attacks": 1, "count": 5}]},
        {"id": "b", "selectionId": "sb", "name": "Lord", "quality": 3, "defense": 3, "size": 1,
         "rules": [{"label": "Hero", "name": "Hero"}], "selectedUpgrades": [synapses],
         "loadout": [{"type": "ArmyBookItem", "name": "Psychic Synapses", "label": "Psychic Synapses", "count": 1,
                      "content": [{"type": "ArmyBookRule", "name": "Caster", "rating": 2}]}],
         "weapons": [{"name": "Blade", "range": 0, "attacks": 3, "count": 1}]},
    ]}


def _rules(epoch: int) -> tuple[list[str], list[str]]:
    squad, lord = l2p._units_from_list(_list(), 1, epoch)
    return squad["special_rules"], lord["special_rules"]


def test_the_epoch_is_live_from_98():
    assert E == 98 <= nml_core.CURRENT_RULES_EPOCH


def test_a_record_at_epoch_97_builds_no_banner():
    """A game recorded at 97 (the live epoch before the bump) replays unchanged: no Banner from the list."""
    assert "Banner" not in _rules(97)[0]
    assert _rules(98)[0].count("Banner") == 1


def test_a_banner_reaches_its_unit_from_the_epoch_on():
    assert "Banner" not in _rules(E - 1)[0]
    assert _rules(E)[0].count("Banner") == 1


def test_a_caster_upgrade_gives_caster_2_once_on_both_legs():
    for epoch in (E - 1, E):
        lord = _rules(epoch)[1]
        assert lord.count("Caster(2)") == 1, (epoch, lord)
        assert not any(r.startswith("Caster(") and r != "Caster(2)" for r in lord), (epoch, lord)
