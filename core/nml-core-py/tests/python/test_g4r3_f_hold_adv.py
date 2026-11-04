"""G4R3 F-HOLD-ADV (lead ruling D7) - the replay gate plays the verb the table EXECUTED.

THE BUG THIS PINS. The act line carries the planner's pick, flushed before the activation runs. The table may turn
that pick into another verb (aof_1000_net_001 act 33: a planned Hold became an Advance to walk into range, two models
moved 1.0 in), and the gate replayed the pick: at the act-start positions the core counted 6 where the table counted 7.
From EPOCH_73_V36 the recorder writes `{"kind":"verb","act":N,"verb":V,"planned":P}` when the executed verb is not the
picked one; the gate reads it and replays the executed verb.

The bundled game is `fixtures/pre_leg_cut/aof_1000_net_000` (two HOLD-and-shoot acts, 3 and 19). The tests add a verb
line to a COPY of it, so the gate's own run decides: the verb is applied only to the act the line names, and a game
without the line (every recording before this row) replays exactly as before.
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "pre_leg_cut"
HOLD, ADVANCE = 0, 1


def _game(tmp_path: Path, verbs: list[dict]) -> Path:
    """A copy of the bundled game with `verbs` appended to its acts.jsonl."""
    game = tmp_path / "aof_1000_net_000"
    shutil.copytree(FIXTURE / "aof_1000_net_000", game)
    if verbs:
        with (game / "acts.jsonl").open("a") as f:
            f.write("".join(json.dumps(v) + "\n" for v in verbs))
    return game


def _replayed(capsys, root: Path) -> int:
    """How many acts the gate replayed with an executed verb (its own report line)."""
    srg.run(root, str(REPO), "table", 0, 99, True, sighting="model")
    out = capsys.readouterr().out
    m = re.search(r"verbs : (\d+) acts replayed", out)
    assert m, out
    return int(m.group(1))


def test_read_verbs_maps_the_act_to_the_executed_verb(tmp_path):
    game = _game(tmp_path, [{"kind": "verb", "act": 3, "verb": ADVANCE, "planned": HOLD}])
    assert srg.read_verbs(game) == {3: ADVANCE}


def test_a_recording_without_verb_lines_has_none(tmp_path):
    assert srg.read_verbs(_game(tmp_path, [])) == {}


def test_the_gate_replays_the_executed_verb_of_the_act_the_line_names(capsys, tmp_path):
    _game(tmp_path, [{"kind": "verb", "act": 3, "verb": ADVANCE, "planned": HOLD}])
    assert _replayed(capsys, tmp_path) == 1


def test_the_key_deleted_mutant_replays_the_pick(capsys, tmp_path):
    _game(tmp_path, [])
    assert _replayed(capsys, tmp_path) == 0
