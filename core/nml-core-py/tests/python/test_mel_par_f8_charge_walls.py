"""MEL-PAR-F8 — the AI's charge menu must see ruin walls.

SOURCE: one act of a 3.6 parity recording (gf_1000_net_000, act 19, recorded at
origin/main 4f7aaa0c), cut down to its header (profiles, terrain, knobs) and the
act's state by a one-off script; the corpus itself is not committed.

The Pathfinders stand inside a ruin; the straight line to Hive Swarms (about 9"
edge to edge) runs through a ruin wall, and the only way out is a detour longer
than the 12" charge band. The table refuses that charge at execution and the
unit rushes instead; the core's menu offered it because the reach index behind
`charge_needs_path` was built without the board's walls.

Two legs: with the recorded walls the menu must NOT offer CHARGE -> Hive Swarms;
with the walls removed from the header it MUST still offer it (so the first leg
is the walls' doing, not a lost charge for any other reason).
"""

from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "mel_par_f8" / "act19.json"


def _menu_offers_the_charge(walls: bool) -> bool:
    import nml_core

    fix = json.loads(FIXTURE.read_text())
    head = fix["header"]
    terrain = head["terrain"] if walls else dict(head["terrain"], walls=[])
    core = nml_core.load(str(REPO))
    core.set_header({
        "profiles": head["profiles"],
        "terrain": terrain,
        "knobs": dict(head["knobs"], hero_attach=True, engage_fold=True),
    })
    menu = core.candidates(core.state_of(fix["state"]), fix["charger"])
    return any(isinstance(c, dict) and c.get("charge") == fix["victim"] for c in menu)


def test_no_charge_through_a_ruin_wall_the_unit_cannot_walk_around():
    fix = json.loads(FIXTURE.read_text())
    assert len(fix["header"]["terrain"]["walls"]) == 48, "the fixture must carry the board's walls"
    assert fix["header"]["knobs"]["charge_needs_path"] is True
    assert not _menu_offers_the_charge(walls=True), (
        "the menu offers CHARGE -> Hive Swarms through the ruin wall")


def test_without_the_walls_the_same_charge_is_offered():
    assert _menu_offers_the_charge(walls=False), (
        "with the walls removed the charge must stay on the menu")
