"""G4R5 F-LAND (maintainer decision A1, 05.11.) - the shoot replay gate can replay a volley from the landing the TABLE executed.

THE BUG THIS PINS. The core lands an Advancing unit with its own per-model solver (`mv::step`), which is not the table's
`MovementPlanner`; the landing faithfulness belongs to the S4 move gate. In the round-4 recording 11 shooting acts part from the
table's dice only because the models stand somewhere else at the volley (one model on the far side of a sight or cover boundary).
`--land` takes the landing OUT of the dice comparison: the shooter chain (host and joined hero) is put where the table's executed
move ended and the Advance is played in place, so the verb stays an Advance (a Hold would fire an Indirect weapon without sight).

  * x/z: the recorder's `moves.json` entry of the activation, each model by the start point it left. The NEXT act's state is not used
    for them: it can already hold a later Harassing step (aof_006 act 33).
  * y (the climb): the next act's state, when that unit still has as many models.
  * Not applied, and counted in a second summary line: an Advance whose own dangerous test the table rolled (the core's route rolls
    it; cutting it would lose the shooter's casualties), an aircraft (it flies its fixed distance from where it stands), a recording
    without a matching executed move.

THE BUNDLED GAMES (`fixtures/g4r5_land`, AoF / GF 1000 pt, NET arm; each trimmed to the named acts, the act after each for y, `auto`
placeholders for the other ordinals, every roll up to the last act, the acts' moves):

  * aof_1000_net_006 act 33   the TRAP: the next act's state holds a later step; only `moves.json` closes it
  * gf_1000_net_006 acts 21, 26   a landing across a sight boundary; act 26 also climbs (y 2.5")
  * aof_1000_net_008 act 34   a landing across a sight boundary; act 2 rolls the table's own dangerous test (not applied)
  * aof_1000_net_001 act 3    an INDIRECT weapon: equal both ways, and only while the Advance stays an Advance
  * gf_1000_net_019 act 1     an aircraft (not applied)

Flag off the four landing acts part again (the mutant); with `land=True` all seven acts are FULL-equal.
"""

from __future__ import annotations

import math
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "g4r5_land"
ALL = ("aof_1000_net_001", "aof_1000_net_006", "aof_1000_net_008", "gf_1000_net_006", "gf_1000_net_019")
IN2M = 0.0254


def _ref(tmp_path: Path, *games: str) -> Path:
    """A reference dir holding copies of the named bundled games (every game when none is named)."""
    for g in games or ALL:
        shutil.copytree(FIXTURE / g, tmp_path / g)
    return tmp_path


def gate(capsys, ref: Path, land: bool) -> tuple[int, int, str]:
    """The gate's own run the way parity.sh calls it (`--land` only when asked): (FULL-equal acts, shooting acts, the report)."""
    srg.run(ref, str(REPO), "table", 0, 99, True, sighting="model", movement=True, **({"land": True} if land else {}))
    out = capsys.readouterr().out
    m = re.search(r"EQUAL : (\d+)/(\d+) acts FULL-equal", out)
    assert m, out
    return int(m.group(1)), int(m.group(2)), out


def _act(game: str, k: int):
    """(header, the act's state, its action, its moves.json entry, the next act's units) of a bundled game."""
    head, lines, _dice, _seed = srg.read_game(FIXTURE / game)
    pos = next(i for i, a in enumerate(lines) if a["act"] == k)
    return (head, lines[pos]["state"], lines[pos]["pick"]["action"], srg.read_moves(FIXTURE / game)[k],
            lines[pos + 1]["state"]["units"])


def test_flag_off_mutant_the_four_landing_acts_part(capsys, tmp_path):
    equal, acts, out = gate(capsys, _ref(tmp_path), land=False)
    assert (equal, acts) == (3, 7), out
    assert "LAND" not in out, out


def test_land_replays_every_act_from_the_table_landing(capsys, tmp_path):
    equal, acts, out = gate(capsys, _ref(tmp_path), land=True)
    assert (equal, acts) == (7, 7), out


def test_the_summary_line_names_the_acts_applied_and_the_gap(capsys, tmp_path):
    _, _, out = gate(capsys, _ref(tmp_path), land=True)
    assert "LAND applied 5 acts, 2 landed > 0.5in from the core" in out, out


def test_the_acts_it_did_not_touch_are_named_too(capsys, tmp_path):
    _, _, out = gate(capsys, _ref(tmp_path), land=True)
    assert "LAND not applied to 2 Advance acts: 1 with the table's own dangerous test, 1 aircraft or without a matching move" in out, out


def test_the_trap_act_closes_from_moves_json_alone(capsys, tmp_path):
    ref = _ref(tmp_path, "aof_1000_net_006")
    assert gate(capsys, ref, land=False)[:2] == (0, 1)
    assert gate(capsys, ref, land=True)[:2] == (1, 1)


def test_x_z_come_from_the_executed_move_not_from_the_next_acts_state():
    _head, plain, action, move, later = _act("aof_1000_net_006", 33)
    landed = srg.land_at_table(plain, action, _head["profiles"][action["unit"]]["name"], move, later)
    ends = sorted(tuple(round(c, 6) for c in m["pts"][-1]) for m in move["models"])
    got = sorted((round(p[0], 6), round(p[2], 6)) for p in landed["units"][action["unit"]]["positions"])
    assert got == ends
    after = later[action["unit"]]["positions"]   # a later Harassing step: at least one model is not where the table's volley stood
    assert any(math.dist((p[0], p[2]), (q[0], q[2])) > 0.01 for p, q in zip(landed["units"][action["unit"]]["positions"], after))


def test_the_climb_height_comes_from_the_next_acts_state():
    head, plain, action, move, later = _act("gf_1000_net_006", 26)
    name = head["profiles"][action["unit"]]["name"]
    with_y = srg.land_at_table(plain, action, name, move, later)["units"][action["unit"]]["positions"]
    without = srg.land_at_table(plain, action, name, move, None)["units"][action["unit"]]["positions"]
    assert max(p[1] for p in with_y) == max(p[1] for p in later[action["unit"]]["positions"]) > 0.05
    assert max(p[1] for p in without) == max(p[1] for p in plain["units"][action["unit"]]["positions"]) == 0.0


def test_an_aircraft_a_foreign_unit_and_another_verb_are_not_landed():
    head, plain, action, move, later = _act("gf_1000_net_019", 1)
    name = head["profiles"][action["unit"]]["name"]
    assert plain["units"][action["unit"]].get("aircraft")
    assert srg.land_at_table(plain, action, name, move, later) is None
    head, plain, action, move, later = _act("aof_1000_net_006", 33)
    assert srg.land_at_table(plain, action, "Some Other Unit", move, later) is None
    assert srg.land_at_table(plain, action, head["profiles"][action["unit"]]["name"], dict(move, action=0), later) is None


def test_a_recording_without_moves_json_applies_nothing_and_says_so(capsys, tmp_path):
    ref = _ref(tmp_path, "aof_1000_net_006")
    (ref / "aof_1000_net_006" / "moves.json").unlink()
    equal, acts, out = gate(capsys, ref, land=True)
    assert (equal, acts) == (0, 1), out
    assert "LAND applied 0 acts, 0 landed > 0.5in from the core" in out, out


def test_the_indirect_advance_stays_equal_because_the_verb_stays_an_advance(capsys, tmp_path):
    ref = _ref(tmp_path, "aof_1000_net_001")
    assert gate(capsys, ref, land=False)[:2] == (1, 1)
    assert gate(capsys, ref, land=True)[:2] == (1, 1)
