"""G4-C2 (a) — the AI's charge menu must apply the table's difficult-ground cap.

SOURCE: one act of a 3.6 parity recording (aof_1000_net_001, act 13, recorded at origin/main 1fdc6418), cut down to its
header (profiles, terrain, knobs) and the act's state by a one-off script; the corpus itself is not committed.

Chosen Warriors (10 models, charge band 13") stand about 8.9" from Foot Knights. Forest lies in the way. The table caps a
charge at 6" when a model's route crosses difficult ground and refuses the charge at execution ("corridor cannot reach
contact within 6.0"", the unit rushes instead); the core's menu asked its reach query with no cap and offered it.

Three legs: with the recorded board the menu must NOT offer CHARGE -> Foot Knights; with the forest cells removed it MUST
(so the first leg is the forest's doing); below rules epoch 73 it must still offer it (the cap is a 3.6 rule).
"""

from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "g4_c2" / "act13.json"
FOREST = 2


def _menu_offers_the_charge(forest: bool = True, rules_epoch: int | None = None) -> bool:
    import nml_core

    fix = json.loads(FIXTURE.read_text())
    head = fix["header"]
    terrain = head["terrain"]
    if not forest:
        terrain = dict(terrain, cells=[c for c in terrain["cells"] if c[2] != FOREST])
    knobs = dict(head["knobs"], hero_attach=True, engage_fold=True)
    if rules_epoch is not None:
        knobs["rules_epoch"] = rules_epoch
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": head["profiles"], "terrain": terrain, "knobs": knobs})
    menu = core.candidates(core.state_of(fix["state"]), fix["charger"])
    return any(isinstance(c, dict) and c.get("charge") == fix["victim"] for c in menu)


def test_no_charge_the_table_would_cap_at_six_inches_and_refuse():
    fix = json.loads(FIXTURE.read_text())
    assert fix["header"]["knobs"]["charge_needs_path"] is True
    assert fix["header"]["knobs"]["rules_epoch"] == 73
    assert any(c[2] == FOREST for c in fix["header"]["terrain"]["cells"]), "the fixture must carry the forest"
    assert not _menu_offers_the_charge(), "the menu offers CHARGE -> Foot Knights through the forest"


def test_without_the_forest_the_same_charge_is_offered():
    assert _menu_offers_the_charge(forest=False), "with the forest removed the charge must stay on the menu"


def test_below_epoch_73_the_charge_is_still_offered():
    assert _menu_offers_the_charge(rules_epoch=72), "the cap is a rules-3.6 rule: epoch 72 must stay byte-identical"
