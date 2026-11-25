"""Heroes never join units in the skirmish systems (gff / aofs): from the skirmish hero epoch on, the
list loader clears a Hero's `joinToUnit`, so the Hero deploys and plays as its own unit. One epoch
below, and in gf at any epoch, the same list still joins."""
from __future__ import annotations

import copy
import sys
import warnings
from pathlib import Path

import nml_core

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
import selfplay as sp  # noqa: E402
from list_to_profile import deploy_unit_specs, selections_from_army_forge_json  # noqa: E402

E = nml_core.EPOCH_98_SKIRMISH_HERO

JOIN_LIST = {
    "gameSystem": "gf",
    "units": [
        {
            "id": "h", "selectionId": "sh", "joinToUnit": "sa", "name": "Lord",
            "quality": 3, "defense": 4, "size": 1,
            "rules": [{"label": "Hero", "name": "Hero"}],
            "weapons": [{"name": "Blade", "range": 0, "attacks": 3, "count": 1}],
        },
        {
            "id": "a", "selectionId": "sa", "name": "Squad", "quality": 4, "defense": 4, "size": 3,
            "rules": [],
            "weapons": [{"name": "Rifle", "range": 24, "attacks": 1, "count": 1}],
        },
    ],
}
HERO, HOST = "p1_0_h", "p1_1_a"


def _list(system: str) -> dict:
    data = copy.deepcopy(JOIN_LIST)
    data["gameSystem"] = system
    return data


def _joins(system: str, epoch: int) -> tuple[str, dict]:
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        sels = selections_from_army_forge_json(_list(system), 1, epoch)
        _, fold = deploy_unit_specs(_list(system), "robot_legions", 1, epoch)
    return sels[HERO][1], fold


def test_the_epoch_is_the_frozen_skirmish_hero_epoch():
    assert E == 98 <= nml_core.CURRENT_RULES_EPOCH
    assert nml_core.hero_join_refusal("gff", E - 1) is None


def test_a_skirmish_hero_is_refused_the_join_and_deploys_alone_from_the_epoch():
    for system in ("gff", "aofs"):
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            sels = selections_from_army_forge_json(_list(system), 1, E)
        assert sels[HERO] == ("sh", ""), system
        assert any("Lord plays alone - Heroes may not join units in this game system." in str(w.message)
                   for w in caught), system
        join, fold = _joins(system, E)
        assert join == "" and fold == {}, system
        attached, attached_to = sp.derive_attachment(
            [{"unit_id": HERO}, {"unit_id": HOST}], selections_from_army_forge_json(_list(system), 1, E))
        assert attached[HOST] == [] and attached_to[HERO] == "", system


def test_one_epoch_below_and_in_gf_the_hero_still_joins():
    for system, epoch in (("gff", E - 1), ("aofs", E - 1), ("gf", E), ("gf", E - 1)):
        join, fold = _joins(system, epoch)
        assert join == "sa", (system, epoch)
        assert fold == {HERO: (HOST, 3, 1)}, (system, epoch)
