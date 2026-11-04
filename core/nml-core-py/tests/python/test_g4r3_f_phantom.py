"""G4R3 F-PHANTOM - the replay gate skips a pick the table never played.

THE BUG THIS PINS. The act line is written when the planner PICKS, before the table decides to play the unit.
gf_1000_net_004 act 20, gf_1000_net_009 act 25 and gf_1000_net_022 act 27 are picks the table never played (no log
line of the unit, no gate call, no dice, the game ended first), and the gate scored each as a core-longer silence.
From EPOCH_73_V36 the recorder writes `{"kind":"played","act":N}` when the activation ran; the gate then skips an act
with no marker. A recording from before the row has no markers at all and is replayed whole.

The bundled game is `fixtures/pre_leg_cut/aof_1000_net_000` (two HOLD-and-shoot acts, 3 and 19). The tests add played
lines to a COPY of it, so the gate's own run decides what is skipped.
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


def _game(tmp_path: Path, played: list[int]) -> Path:
    """A copy of the bundled game with a `played` line appended for every act in `played`."""
    game = tmp_path / "aof_1000_net_000"
    shutil.copytree(FIXTURE / "aof_1000_net_000", game)
    if played:
        with (game / "acts.jsonl").open("a") as f:
            f.write("".join(json.dumps({"kind": "played", "act": k}) + "\n" for k in played))
    return game


def _replayed_acts(capsys, root: Path) -> tuple[int, str]:
    """(how many shooting acts the gate replayed, its whole report)."""
    srg.run(root, str(REPO), "table", 0, 99, True, sighting="model")
    out = capsys.readouterr().out
    m = re.search(r"EQUAL : (\d+)/(\d+) acts FULL-equal", out)
    assert m, out
    return int(m.group(2)), out


def test_read_played_lists_the_acts_the_table_ran(tmp_path):
    assert srg.read_played(_game(tmp_path, [3, 7])) == {3, 7}


def test_a_recording_without_markers_has_none(tmp_path):
    assert srg.read_played(_game(tmp_path, [])) == set()


def test_an_act_with_no_marker_is_skipped_when_the_recording_has_markers(capsys, tmp_path):
    _game(tmp_path, [3])
    acts, out = _replayed_acts(capsys, tmp_path)
    assert acts == 1, out
    assert "unplayed: 1" in out, out


def test_every_act_marked_replays_whole(capsys, tmp_path):
    _game(tmp_path, [3, 19])
    acts, out = _replayed_acts(capsys, tmp_path)
    assert acts == 2, out
    assert "unplayed: 0" in out, out


def test_the_key_deleted_mutant_replays_every_act(capsys, tmp_path):
    """An old recording has no markers: nothing is skipped, the numbers are the ones it always had."""
    _game(tmp_path, [])
    acts, out = _replayed_acts(capsys, tmp_path)
    assert acts == 2, out
    assert "unplayed: 0" in out, out
