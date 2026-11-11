"""G4-H-LIM RED-GREEN: the act state carries the table's spent-Limited ledger, and the core obeys it.

THE BUG THIS PINS. The table keeps a once-per-game ledger of spent Limited weapons
(`unit_properties["limited_used"]`) and a spent weapon does not fire. The act state it hands to the core
carried no such field and the core started every state with an empty ledger, so the AI's search priced a
second shot of a spent Limited weapon and the replay fired it where the table logged "no volley - no ready
ranged weapon".

The fixture is act 24 of a rules 3.6 laptop recording (gf_1000_net_034, 04.11.): the Gators advance and
shoot, their only ranged weapon is the Disposable Assault Rocket-Pod (Limited), and they already fired it
in act 12. The table rolled no dice. The exporter now writes the spent weapon names under
`ledger.limited_used`; the leg below that carries them is what a recorder at EPOCH_73_V36 writes.

Legs: with the ledger the core is silent like the table; the key-deleted mutant (an old recording) rolls
the pod again; below EPOCH_73_V36 the key is not read, so the two never differ.
"""

from __future__ import annotations

import json
from pathlib import Path

import nml_core

REPO = str(Path(__file__).resolve().parents[4])
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "g4_h_lim" / "act24.json"
EPOCH_72_PLAYTEST_RULES = 72
EPOCH_73_V36 = 73
POD = "Disposable Assault Rocket-Pod"


def _attack_dice(epoch: int, spent: list[str] | None) -> int:
    """The attack dice act 24 draws when replayed at `epoch`, the unit's ledger naming `spent` (None = no key)."""
    fx = json.loads(FIXTURE.read_text())
    head = fx["header"]
    core = nml_core.load(REPO)
    knobs = dict(head["knobs"], hero_attach=True, engage_fold=True, sighting="model", rules_epoch=epoch)
    core.set_header({"profiles": head["profiles"], "terrain": head["terrain"], "knobs": knobs})
    if spent is not None:
        fx["state"]["units"][fx["action"]["unit"]]["ledger"]["limited_used"] = spent
    _, rep = core.resolve_with_tray(core.state_of(fx["state"]), fx["action"], nml_core.Rng(0), nml_core.Tray(fx["seed"]))
    return sum(r["count"] for r in rep["rolls"] if r["kind"] == "attack")


def test_with_the_ledger_the_core_is_silent_like_the_table():
    assert _attack_dice(EPOCH_73_V36, [POD]) == 0, "the table logged no volley: the spent pod draws no dice"


def test_the_key_deleted_mutant_rolls_the_spent_pod_again():
    assert _attack_dice(EPOCH_73_V36, None) == 3, "an old recording carries no key: three models roll the pod"


def test_below_epoch_73_the_key_is_not_read():
    assert _attack_dice(EPOCH_72_PLAYTEST_RULES, [POD]) == _attack_dice(EPOCH_72_PLAYTEST_RULES, None)
