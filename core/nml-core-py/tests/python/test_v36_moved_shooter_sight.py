"""SHO-PAR-F3 RED-GREEN: a shooter that moved asks the per-model 3D sight, not the coarse grid line.

THE BUG THIS PINS. For a MOVED shooter the core's target gate asked the coarse school grid along the line
from the shooter's centre to the target's centre, and any forest, ruins or container cell on that line refused
the whole shot. The table decides per model with 3D volumes, so a unit that stepped out beside a wood still
fires on the table and fired nothing in the core. The same gate prices every advance-and-shoot in the search.

The fixture is act 15 of a rules 3.6 laptop recording (gf_1000_net_000, 30.10.): a five-model unit advances
and shoots across a forest. `table_post_positions` is where the table's own move put the five models; the
table rolled 5 attack dice from there. The grid centre line from that spot crosses forest cells, the
per-model sight lines do not.

Both legs: from EPOCH_73_V36 the moved shot fires (5 attack dice); EPOCH_72_PLAYTEST_RULES keeps the grid
line and rolls nothing.
"""

from __future__ import annotations

import json
from pathlib import Path

import nml_core

REPO = str(Path(__file__).resolve().parents[4])
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "sho_par_f3" / "act15.json"
EPOCH_72_PLAYTEST_RULES = 72
EPOCH_73_V36 = 73


def _attack_dice(epoch: int) -> list[int]:
    """The attack batches of act 15 replayed as an ADVANCE to the table's own post-move centroid."""
    fx = json.loads(FIXTURE.read_text())
    head = fx["header"]
    core = nml_core.load(REPO)
    knobs = dict(head["knobs"], hero_attach=True, engage_fold=True, sighting="unit", rules_epoch=epoch)
    core.set_header({"profiles": head["profiles"], "terrain": head["terrain"], "knobs": knobs})
    post = fx["table_post_positions"]
    dest = [sum(p[0] for p in post) / len(post), 0.0, sum(p[2] for p in post) / len(post)]
    action = dict(fx["action"], dest=dest)
    _, rep = core.resolve_with_tray(core.state_of(fx["state"]), action, nml_core.Rng(0), nml_core.Tray(fx["seed"]))
    return [r["count"] for r in rep["rolls"] if r["kind"] == "attack"]


def test_a_moved_shooter_fires_past_a_forest_it_sees_beside_at_epoch_73():
    assert sum(_attack_dice(EPOCH_73_V36)) == 5, "the table rolled 5 attack dice after this advance"


def test_a_moved_shooter_keeps_the_grid_line_at_epoch_72():
    assert _attack_dice(EPOCH_72_PLAYTEST_RULES) == [], "epoch 72 replays the coarse grid gate: no shot"
