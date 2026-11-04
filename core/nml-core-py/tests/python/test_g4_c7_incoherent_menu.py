"""G4-C7 (rules epoch 73) - a unit that starts its activation out of coherency gets only the gather pick on its menu.

SOURCE: act 26 of a 3.6 parity recording (aof_1000_net_022, AoF 1000 pt, NET arm), cut down to its header (profiles,
terrain with the board walls, knobs) and the act-start state by a one-off script; the corpus itself is not committed.

Havoc Ogres (5 models) have lost a model to casualties and stand split: the nearest base edges of one straggler are
1.2 to 1.3 inches from the rest, past the 1 inch link. The core picked a CHARGE; the table executed an ADVANCE with no
target, because the Regroup rule makes the unit's whole activation the action that restores coherency (decision
"regroup", no charge, no objective).

Legs (the unit is real: the recorded state, run through the same menu the AI plays):
  * at epoch 73 the menu is ONE row, an ADVANCE that stays where the unit stands (the gather), and no CHARGE;
  * below 73 the menu is unchanged and still offers the charge (byte-identical replay of the old games);
  * the SAME unit packed into a tight line is coherent: its menu is the full one again, hold row and charge included
    (so the first leg is the coherency's doing, not a blanket removal);
  * a coherent charger of another recorded game (aof_1000_net_000 act 11) keeps its charge.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
HOLD, ADVANCE, RUSH, CHARGE = 0, 1, 2, 3


def _menu(fix: dict, rules_epoch: int | None = None) -> list[dict]:
    import nml_core

    head = fix["header"]
    knobs = dict(head["knobs"], hero_attach=True, engage_fold=True)
    if rules_epoch is not None:
        knobs["rules_epoch"] = rules_epoch
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": head["profiles"], "terrain": head["terrain"], "knobs": knobs})
    return core.candidates(core.state_of(fix["state"]), fix["charger"])


def _fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text())


def _packed(fix: dict) -> dict:
    """The same recorded unit, its models moved into a tight row around their own centre: coherent."""
    out = copy.deepcopy(fix)
    unit = out["state"]["units"][out["charger"]]
    n = len(unit["positions"])
    cx = sum(p[0] for p in unit["positions"]) / n
    cz = sum(p[2] for p in unit["positions"]) / n
    step = 2 * max(unit["radii"]) + 0.005
    for i, p in enumerate(unit["positions"]):
        p[0], p[2] = cx + (i - (n - 1) / 2) * step, cz
    return out


def test_the_fixture_is_a_rules_73_game():
    assert _fixture("g4_c7/act26.json")["header"]["knobs"]["rules_epoch"] == 73


def test_an_incoherent_unit_gets_only_the_gather_pick():
    fix = _fixture("g4_c7/act26.json")
    menu = _menu(fix)
    assert not any(c.get("charge") for c in menu), "a split unit may not charge"
    assert [c["kind"] for c in menu] == [ADVANCE], menu
    unit = fix["state"]["units"][fix["charger"]]
    n = len(unit["positions"])
    centre = [sum(p[i] for p in unit["positions"]) / n for i in (0, 2)]
    dest = menu[0]["dest"]
    assert abs(dest[0] - centre[0]) < 0.02 and abs(dest[2] - centre[1]) < 0.02, "the gather stays where the unit stands"


def test_below_epoch_73_the_menu_is_unchanged():
    menu = _menu(_fixture("g4_c7/act26.json"), rules_epoch=72)
    assert any(c.get("charge") for c in menu), "epoch 72 must stay byte-identical"
    assert any(c["kind"] == HOLD for c in menu)


def test_the_same_unit_packed_into_a_row_has_its_full_menu_back():
    menu = _menu(_packed(_fixture("g4_c7/act26.json")))
    kinds = {c["kind"] for c in menu}
    assert HOLD in kinds and len(menu) > 1, menu


def test_a_coherent_charger_keeps_its_charge():
    fix = _fixture("g4_c2/port_executed_act11.json")
    assert any(c.get("charge") == fix["victim"] for c in _menu(fix))
