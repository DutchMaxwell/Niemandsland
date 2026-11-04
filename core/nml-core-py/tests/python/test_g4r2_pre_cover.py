"""AI-G4 round 2, row F-PRE-COVER (rules epoch 73) - the target's cover is read again after the cast leg's casualties.

The table decides a unit's cover per save moment from the models STANDING (`_solo_majority_in_cover`: more than half
of the alive models fully inside cover terrain, a unit built with one model by its centre alone). The act line records
the flag at the START of the activation; when the cast leg kills models before the volley the gate patches the state
from the `pre` line (`patch_pre`), and the flag stayed what it was - the core then saved the volley with a Cover +1
the table never gave (the last roll of the act parted at the target: 4+ against the table's 5+).

`patch_pre` now takes the board and recomputes `in_cover` for every unit it cut down, with the same rule on the
survivors (the table's cast leg kills from the end of the model list in this gate, as `patch_pre` always did).

THE BUNDLED GAME (`fixtures/g4r2_pre_cover/aof_1000_net_021`, the 1104 recording, trimmed like the other fixtures):
act 4 - the host `Gargoyles` (5 models, the last three standing in forest) loses three models to the spell before the
volley; the two left stand in the open.
"""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import nml_core  # noqa: E402
import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
GAME = Path(__file__).resolve().parent / "fixtures" / "g4r2_pre_cover" / "aof_1000_net_021"


def test_act_4_is_full_equal_once_the_cover_is_read_from_the_survivors(capsys):
    srg.run(GAME.parent, str(REPO), "table", 0, 99, True, sighting="model", movement=True)
    out = capsys.readouterr().out
    assert "EQUAL : 1/1 acts FULL-equal" in out, out
    assert "OWNER : 1/1 acts FULL-equal" in out, out


def _fixture() -> tuple[dict, dict, str, dict]:
    head, lines, _, _ = srg.read_game(GAME)
    plain = lines[0]["state"]
    host = next(k for k, u in plain["units"].items() if u.get("attached") and u["alive"] == 5)
    return head, plain, host, srg.read_pre(GAME)[4]


def test_patch_pre_reads_the_cover_of_the_survivors():
    head, plain, host, pre = _fixture()
    assert plain["units"][host]["in_cover"] is True, "the flag the table recorded at the start"
    out = srg.patch_pre(plain, pre, nml_core.board(head["terrain"]))
    assert out["units"][host]["alive"] == 2
    assert out["units"][host]["in_cover"] is False, "the two survivors stand in the open"


def test_patch_pre_without_a_board_leaves_the_flag_as_recorded():
    """No terrain (a recording without a board) or a caller that passes none: byte-identical to before."""
    _, plain, host, pre = _fixture()
    out = srg.patch_pre(copy.deepcopy(plain), pre)
    assert out["units"][host]["in_cover"] is True


def test_a_unit_the_spell_did_not_touch_keeps_its_flag():
    head, plain, host, pre = _fixture()
    untouched = {k: v for k, v in pre.items() if k != host}
    out = srg.patch_pre(plain, untouched, nml_core.board(head["terrain"]))
    assert out["units"][host]["in_cover"] is True
    assert json.dumps(out["units"][host]) == json.dumps(plain["units"][host])
