"""G4-C2 (c) — the AI's charge menu must confirm its charge picks with the core's own move port.

SOURCE: two acts of a 3.6 parity recording (origin/main 1fdc6418), cut down to their header (profiles, terrain, knobs)
and the act's state by a one-off script; the corpus itself is not committed.

* port_act22.json — aof_1000_net_001 act 22: Foot Knights stand 1.0" from Change Barbarian Champion and declare a
  charge. The table refuses it at execution ("corridor cannot reach contact", the unit rushes instead). No forest is
  involved, the edge gap is a single inch: the cheap path check cannot see why, the move port can (the formation ends
  short of the engage ring once it is planned the way the table plans it).
* port_executed_act11.json — aof_1000_net_000 act 11: a charge the table EXECUTED. The port reaches contact, so the menu
  must keep it (the confirmation is not a blanket removal).

Legs: the refused charge is NOT offered; below rules epoch 73 it still is (the confirmation is a 3.6 rule); the
executed charge is offered.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "g4_c2"


def _menu_offers_the_charge(fixture: str, rules_epoch: int | None = None) -> bool:
    import nml_core

    fix = json.loads((FIXTURES / fixture).read_text())
    head = fix["header"]
    knobs = dict(head["knobs"], hero_attach=True, engage_fold=True)
    if rules_epoch is not None:
        knobs["rules_epoch"] = rules_epoch
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": head["profiles"], "terrain": head["terrain"], "knobs": knobs})
    menu = core.candidates(core.state_of(fix["state"]), fix["charger"])
    return any(isinstance(c, dict) and c.get("charge") == fix["victim"] for c in menu)


def test_no_charge_the_move_port_cannot_execute():
    fix = json.loads((FIXTURES / "port_act22.json").read_text())
    assert fix["header"]["knobs"]["rules_epoch"] == 73
    assert not _menu_offers_the_charge("port_act22.json"), "the menu offers a charge the port ends short on"


def test_below_epoch_73_the_charge_is_still_offered():
    assert _menu_offers_the_charge("port_act22.json", rules_epoch=72), "epoch 72 must stay byte-identical"


def test_a_charge_the_table_executed_stays_on_the_menu():
    assert _menu_offers_the_charge("port_executed_act11.json"), "the port reaches contact: the charge must stay"
