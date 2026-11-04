"""AI-G4 round 2, row F-AIM (rules epoch 73) - a shot aimed at a dead host reaches the living joined hero.

The table fires "at" the HOST object of a joined unit even after the host is gone and only the hero lives: the
sidecar's `target_id` is then the dead host's key. G4-H4 made `split_aim` trust that key, so the core was handed a
split-fire aim whose group sits on a unit with no model - no distance, no sight, no dice: the act came back
PORT-SILENT (38 of the 44 port-silent acts of the 1104 round-2 shooting replay). `split_aim` now maps a key whose
unit has no living model and exactly one living attached hero to that hero (the lone hero is the unit).

THE BUNDLED GAMES (`fixtures/g4r2_aim/`, AoF 1000 pt NET arm, the 1104 recording, trimmed like the other shoot
fixtures: the header, the one act line, `auto` placeholders before it, every roll up to it verbatim, its shots):

  * aof_1000_net_007 act 22 - a HOLD: the pick is the hero `Champion`, its host `Dark Shooters` has no model left.
    After the fix the port rolls the table's attack and both save batches with the same faces. It stays one roll
    short (the table's morale test of the lone hero) - a different cause, not this row's; the test pins that.
  * aof_1000_net_001 act 22 - an ADVANCE: the port rolls the table's dice and the act is FULL-equal on the dice
    (the signer of the defender's roll differs: the lone-hero label, G4-H6).

THE MUTANTS are the pre-fix gate (no mapping: both acts port-silent) and a recording below rules epoch 73, where
the mapping must stay off.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "g4r2_aim"


def gate(capsys, ref: Path = FIXTURE) -> str:
    """The gate's own run as the round-2 diagnosis ran it (--sighting model --movement); the whole report."""
    srg.run(ref, str(REPO), "table", 0, 99, True, sighting="model", movement=True)
    return capsys.readouterr().out


def test_a_dead_host_aim_reaches_the_living_hero(capsys):
    out = gate(capsys)
    assert "0 table silent, 0 port silent, 0 shape, 0 faces" in out, out
    assert "2/2 acts PREFIX-equal" in out, out
    assert "1/2 acts FULL-equal" in out, out


def test_the_lone_hero_is_the_unit_the_aim_names():
    units = {"host": {"alive": 0, "attached": ["hero"]}, "hero": {"alive": 1, "attached": []},
             "dead_hero": {"alive": 0, "attached": []}, "two": {"alive": 0, "attached": ["hero", "hero2"]},
             "hero2": {"alive": 1, "attached": []}, "live_host": {"alive": 3, "attached": ["hero"]}}
    assert srg.lone_hero_of(units, "host") == "hero"
    assert srg.lone_hero_of(units, "dead_hero") == "dead_hero", "nothing to map to"
    assert srg.lone_hero_of(units, "two") == "two", "two living heroes: not a lone hero, stay put"
    assert srg.lone_hero_of(units, "live_host") == "live_host", "a living host keeps its own shot"


def test_below_epoch_73_the_aim_is_left_as_recorded(capsys, tmp_path):
    old = tmp_path / "ref"
    shutil.copytree(FIXTURE, old)
    for game in old.iterdir():
        lines = (game / "acts.jsonl").read_text().splitlines()
        head = json.loads(lines[0])
        head["knobs"]["rules_epoch"] = 72
        (game / "acts.jsonl").write_text("\n".join([json.dumps(head)] + lines[1:]) + "\n")
    out = gate(capsys, old)
    assert "2 port silent" in out, out
