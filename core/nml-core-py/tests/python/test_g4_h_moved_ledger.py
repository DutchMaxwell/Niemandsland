"""G4-H-MOVED RED-GREEN: the act state carries the table's `moved_round` stamp, and the core reads it.

THE BUG THIS PINS. The table stamps `unit_properties["moved_round"]` on every unit that executes a move; the
Artillery rule (-1 to hit a target) is withheld from a target that moved THIS round ("Artillery target: no -1
(moved this round)"). The act state it hands to the core carried no such field and `io.rs` started every unit
at -1 ("never moved"), so a target that moved earlier in the round kept the -1 the table withholds.

The fixture is act 4 of a rules 3.6 laptop recording (gf_1000_net_026, 04.11.): a unit advances and shoots at
a Knight Support Turret (Artillery) that already moved in round 1. The table rolled 4 dice on 3+; without the
stamp the core rolls them on 4+. The exporter now writes the stamp under `ledger.moved_round`; the leg below
that carries it is what a recorder at EPOCH_73_V36 writes. The fixture is the gate's own replay input
(vintage flags, movement=table, hero_attach, model sighting) plus the table's recorded rolls.

Legs: with the stamp the core is FULL-equal to the table; the key-deleted mutant (an old recording) parts at
the first roll; below EPOCH_73_V36 the key is not read, so the two never differ.
"""

from __future__ import annotations

import json
from pathlib import Path

import nml_core

REPO = str(Path(__file__).resolve().parents[4])
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "g4_h_moved" / "act4.json"
EPOCH_72_PLAYTEST_RULES = 72
EPOCH_73_V36 = 73


def _rolls(epoch: int, stamped: bool) -> list:
    """The `[kind, count, target, faces]` rolls act 4 draws at `epoch`, the target's ledger carrying the stamp or not."""
    fx = json.loads(FIXTURE.read_text())
    head = fx["header"]
    core = nml_core.load(REPO)
    core.set_header({"profiles": head["profiles"], "terrain": head["terrain"], "knobs": dict(head["knobs"], rules_epoch=epoch)})
    if stamped:
        fx["state"]["units"][fx["action"]["shoot"]]["ledger"]["moved_round"] = fx["state"]["round"]
    tray = nml_core.Tray(fx["seed"])
    if fx["burn"]:
        tray.roll(fx["burn"])
    _, rep = core.resolve_with_tray(core.state_of(fx["state"]), fx["action"], nml_core.Rng(0), tray)
    return [[r["kind"], r["count"], r["target"], r["faces"]] for r in rep["rolls"]]


def test_with_the_stamp_the_core_is_full_equal_to_the_table():
    fx = json.loads(FIXTURE.read_text())
    assert _rolls(EPOCH_73_V36, True) == fx["want"], "the target moved this round: Artillery's -1 is withheld"


def test_the_key_deleted_mutant_still_applies_the_artillery_penalty():
    fx = json.loads(FIXTURE.read_text())
    assert _rolls(EPOCH_73_V36, False) != fx["want"], "an old recording carries no key: the -1 to hit stays"


def test_below_epoch_73_the_key_is_not_read():
    assert _rolls(EPOCH_72_PLAYTEST_RULES, True) == _rolls(EPOCH_72_PLAYTEST_RULES, False)
