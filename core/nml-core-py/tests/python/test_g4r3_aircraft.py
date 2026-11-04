"""AI-G4 round 3, row F-AIRCRAFT (rules epoch 73) - an Aircraft flies the table's straight 30" run, in the table's heading.

SOURCE: three Aircraft acts of the 3.6 parity recording (origin/main fb56aec1, games gf_1000_net_019 / _020), cut down
to their header (profiles, terrain, knobs), the act's state and pick, and the unit's landing in the NEXT act's state
(`table_landing`). The corpus itself is not committed.

The table's Aircraft activation (`_act_aircraft`) ignores the planner's dest and the 6"/12" bands: every model shifts by
the same 30" in a heading it picks itself (toward an enemy centre or one of 16 compass points, the best expected volley
from the endpoint). All 6 recorded Aircraft activations moved exactly 30.0" ; the core moved them 4-6" toward the dest.

* gf019_act16 - kind ADVANCE, the table flew 22.5 deg (a compass heading, the planner's dest lay at -12 deg).
* gf020_act7  - kind RUSH, the table flew at an enemy centre (126.9 deg, the planner's dest lay at 59.5 deg).
* gf020_act11 - kind ADVANCE, the table flew at an enemy centre (1.9 deg, the dest lay at 19.4 deg).

Legs: the landing is the table's; below rules epoch 73 the unit still moves by its band (byte-identical); the menu of an
Aircraft is the ONE row the table executes (whatever the pick, the plane flies), aimed at the same landing.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "g4r3_aircraft"
IN = 0.0254
ACTS = ["gf019_act16.json", "gf020_act7.json", "gf020_act11.json"]


def _fix(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text())


def _core(fix: dict, rules_epoch: int | None = None):
    import nml_core

    head = fix["header"]
    knobs = dict(head["knobs"], movement=True, hero_attach=True, engage_fold=True)  # the shoot replay gate's own set
    if rules_epoch is not None:
        knobs["rules_epoch"] = rules_epoch
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": head["profiles"], "terrain": head["terrain"], "knobs": knobs})
    return core


def _landing(fix: dict, rules_epoch: int | None = None) -> list:
    core = _core(fix, rules_epoch)
    nxt = core.resolve(core.state_of(fix["state"]), fix["action"])
    return nxt.plain()["units"][fix["unit"]]["positions"]


def _centre(ps: list) -> tuple[float, float]:
    return sum(p[0] for p in ps) / len(ps), sum(p[2] for p in ps) / len(ps)


def _flown_in(fix: dict, landing: list) -> float:
    (x0, z0), (x1, z1) = _centre(fix["state"]["units"][fix["unit"]]["positions"]), _centre(landing)
    return math.hypot(x1 - x0, z1 - z0) / IN


def test_the_plane_lands_where_the_table_lands_it():
    for name in ACTS:
        fix = _fix(name)
        got, want = _landing(fix), fix["table_landing"]
        assert len(got) == len(want), name
        for g, w in zip(got, want):
            assert math.hypot(g[0] - w[0], g[2] - w[2]) < 1e-4, (name, got, want)


def test_the_plane_flies_the_full_30_inches():
    for name in ACTS:
        fix = _fix(name)
        assert abs(_flown_in(fix, _landing(fix)) - 30.0) < 0.01, name


def test_below_epoch_73_the_plane_still_moves_by_its_band():
    for name in ACTS:
        fix = _fix(name)
        band = fix["state"]["units"][fix["unit"]]["bands"]["advance" if fix["action"]["kind"] == 1 else "rush"]
        assert _flown_in(fix, _landing(fix, rules_epoch=72)) <= band + 0.01, name


def test_the_menu_of_a_plane_is_the_one_row_the_table_executes():
    fix = _fix("gf019_act16.json")
    core = _core(fix)
    menu = core.candidates(core.state_of(fix["state"]), fix["unit"])
    assert [c["kind"] for c in menu] == [1], menu
    dest, want = menu[0]["dest"], _centre(fix["table_landing"])
    assert math.hypot(dest[0] - want[0], dest[2] - want[1]) < 1e-4, (dest, want)
    old = _core(fix, 72)
    assert len(old.candidates(old.state_of(fix["state"]), fix["unit"])) > 1, "below epoch 73 the menu is unchanged"
