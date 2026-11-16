"""G4-C6 (rules epoch 73) - the AI's charge menu must not offer a charge whose longest model route outruns the band.

SOURCE: act 30 of a 3.6 parity recording (aof_1000_net_000, AoF 1000 pt, NET arm), cut down to its header (profiles,
terrain with the board walls, knobs) and the act-start state by a one-off script; the corpus itself is not committed.

* arc_act30.json - aof_1000_net_000 act 30: the unit declares a charge, the table refuses it at execution ("corridor
  cannot reach contact within 6.0 inches") and the unit does something else. The formation does reach the engage ring, but
  one trailing model walks 7.55 inches under a 6.0 inch band (the 6 inch cap on difficult ground). The move port computes
  the same 7.55; its "ends short" verdict only looked at the gap that is left, never at the route against the band.
* g4_c2/port_executed_act11.json - aof_1000_net_000 act 11: a charge the table EXECUTED. Its longest route stays inside the
  band, so the menu must keep it (the new clause is not a blanket removal).

Legs: the refused charge is NOT offered; below rules epoch 73 it still is (the clause is a 3.6 rule, which is also the
mutant: with the clause off the charge comes back); the executed charge is offered.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def _core(fixture: str, rules_epoch: int | None = None):
    import nml_core

    fix = json.loads((FIXTURES / fixture).read_text())
    head = fix["header"]
    knobs = dict(head["knobs"], hero_attach=True, engage_fold=True)
    if rules_epoch is not None:
        knobs["rules_epoch"] = rules_epoch
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": head["profiles"], "terrain": head["terrain"], "knobs": knobs})
    return core, fix


def _menu_offers_the_charge(fixture: str, rules_epoch: int | None = None) -> bool:
    core, fix = _core(fixture, rules_epoch)
    menu = core.candidates(core.state_of(fix["state"]), fix["charger"])
    return any(isinstance(c, dict) and c.get("charge") == fix["victim"] for c in menu)


def test_the_fixture_is_a_rules_73_game():
    fix = json.loads((FIXTURES / "g4_c6" / "arc_act30.json").read_text())
    assert fix["header"]["knobs"]["rules_epoch"] == 73


def test_no_charge_whose_longest_route_outruns_the_band():
    assert not _menu_offers_the_charge("g4_c6/arc_act30.json"), "the menu offers a charge the table refuses on the route"


def test_below_epoch_73_the_charge_is_still_offered():
    assert _menu_offers_the_charge("g4_c6/arc_act30.json", rules_epoch=72), "epoch 72 must stay byte-identical"


def test_a_charge_the_table_executed_stays_on_the_menu():
    assert _menu_offers_the_charge("g4_c2/port_executed_act11.json"), "the route fits the band: the charge must stay"


def test_from_epoch_77_the_capped_charge_is_offered_and_stays_inside_the_band():
    """#183 (EPOCH_77_CHARGE_CAP): the arc cap stops the trailing model at its 6" band (7.55" at 73-76), so the charge the
    table could not execute becomes executable and is offered; at 76 it stays off the menu (byte-identical leg)."""
    assert not _menu_offers_the_charge("g4_c6/arc_act30.json", rules_epoch=76)
    assert _menu_offers_the_charge("g4_c6/arc_act30.json", rules_epoch=77)
    core, fix = _core("g4_c6/arc_act30.json", 77)
    land = core.charge_move(core.state_of(fix["state"]), fix["charger"], fix["victim"])
    assert land["budget_in"] == 6.0 and land["arc_in"] <= 6.0 + 0.05, land["arc_in"]
    assert land["snap_in"] is not None and land["snap_in"] >= 0.0, land["snap_in"]
