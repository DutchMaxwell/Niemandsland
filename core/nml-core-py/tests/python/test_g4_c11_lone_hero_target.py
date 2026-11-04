"""G4-C11 (rules epoch 73) - a charge named at a host whose models are all dead fights the joined hero that is still alive.

SOURCE: act 19 of a 3.6 parity recording (gf_1000_net_015, GF 1000 pt, NET arm, seed 36276), cut down to its header
(profiles, terrain with the board walls, knobs), the act-start state, the recorded pick and the table's rolls by a
one-off script; the corpus itself is not committed. The state is the act as the replay gate hands it to the core: the
spell leg of the same activation has already wiped the host.

Jokers (4 models + a hero) charge Berserkers (0 models left, the joined Berserker Veteran alive). The table
fights: Jokers strike twice and the Champion once, the hero saves and strikes back (five roll groups). The core
guarded the fight on the HOST's model count alone, so it resolved nothing at all (a charge landed in base contact
and then no dice). The chain's models are the hero's now: the same unit, p.14 "fights on alone".

Legs: from epoch 73 the five rolls equal the table's roll for roll (counts, targets and faces); below 73 the old
silence stands (byte-identical replay of the old games).
"""

from __future__ import annotations

import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "g4_c11" / "act19.json"


def _rolls(rules_epoch: int | None = None) -> tuple[list, list]:
    """(the core's rolls, the table's rolls) as (kind, count, target, faces); the roller label is not compared."""
    import nml_core

    fix = json.loads(FIXTURE.read_text())
    head = fix["header"]
    knobs = dict(head["knobs"])
    if rules_epoch is not None:
        knobs["rules_epoch"] = rules_epoch
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": head["profiles"], "terrain": head["terrain"], "knobs": knobs})
    tray = nml_core.Tray(fix["tray"]["seed"])
    if fix["tray"]["burn"]:
        tray.roll(fix["tray"]["burn"])
    _, report = core.resolve_with_tray(core.state_of(fix["state"]), fix["action"], nml_core.Rng(0), tray)
    got = [(r["kind"], r["count"], r["target"], r["faces"]) for r in report["rolls"]]
    want = [(w[0], w[1], w[2], w[3]) for w in fix["want"]]
    return got, want


def test_the_fixture_is_a_lone_hero_charge_at_rules_73():
    fix = json.loads(FIXTURE.read_text())
    assert fix["header"]["knobs"]["rules_epoch"] == 73
    host = fix["state"]["units"][fix["action"]["charge"]]
    assert host["alive"] == 0 and host["attached"], "the host is wiped and carries a joined hero"
    assert fix["state"]["units"][host["attached"][0]]["alive"] > 0, "the joined hero lives"


def test_the_charge_fights_the_hero_roll_for_roll():
    got, want = _rolls()
    assert len(got) == 5, got
    assert got == want, (got, want)


def test_below_epoch_73_the_old_silence_stands():
    got, _ = _rolls(rules_epoch=72)
    assert got == [], "epoch 72 must stay byte-identical"
