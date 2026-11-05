"""G4R5 F-LAND, reposition half - an Ethereal / Teleport reposition is a separate beat AFTER the Advance.

THE BUG THIS PINS. `moves.json` carries the Advance only: for aof_1000_net_034 acts 10 and 16 (Spectres, Ethereal) its last point is
6.3" / 6.4" short of where the unit really stood for the volley. The table's log reads "Ethereal repositions within 6" - landing
centroid ..." and then "no volley - no target in range or sight"; the only die the table rolled is the dangerous-terrain test BEFORE
the reposition. The end of the reposition is written twice: in the unit ledger of the NEXT act (`teleport.to`, "(x, z)" in metres, equal
to the next state's centre to 0.00") and in the next state's positions. With `--land` the gate now moves the landed chain rigidly to
`teleport.to`, and cuts the table's dangerous test (its dice burned, the core's own test off): nothing follows it, so its losses cannot
change a volley. Both sides are silent and the acts are FULL-equal.

The ledger keeps the LAST teleport, so a `to` equal to the start ledger's is a stale one (a unit that teleported in an earlier act):
it is not read. Not closed here: gf_1000_net_024 act 7 (a volley follows its reposition; it needs core row R13).

The bundled game `fixtures/g4r5_land_teleport/aof_1000_net_034` is the recorded AoF 1000 pt NET game, trimmed to acts 10 and 16, the
act after each, `auto` placeholders and every roll up to act 16.
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "g4r5_land_teleport"
GAME = "aof_1000_net_034"


def gate(capsys, tmp_path: Path, land: bool) -> tuple[int, int, str]:
    """The gate's own run the way parity.sh calls it: (both-silent acts, shooting acts, the whole report)."""
    shutil.copytree(FIXTURE / GAME, tmp_path / GAME)
    srg.run(tmp_path, str(REPO), "table", 0, 99, True, sighting="model", movement=True, **({"land": True} if land else {}))
    out = capsys.readouterr().out
    m = re.search(r"BOTH-SILENT: (\d+)/(\d+) acts", out)
    assert m, out
    return int(m.group(1)), int(m.group(2)), out


def _act(k: int):
    _head, lines, _dice, _seed = srg.read_game(FIXTURE / GAME)
    pos = next(i for i, a in enumerate(lines) if a["act"] == k)
    return lines[pos]["state"]["units"], lines[pos + 1]["state"]["units"], lines[pos]["pick"]["action"]["unit"]


def test_flag_off_mutant_both_acts_fire_a_volley_the_table_never_did(capsys, tmp_path):
    silent, acts, out = gate(capsys, tmp_path, land=False)
    assert (silent, acts) == (0, 2), out
    assert "0 table_longer, 2 port_longer" in out, out


def test_land_makes_both_acts_silent_on_both_sides(capsys, tmp_path):
    silent, acts, out = gate(capsys, tmp_path, land=True)
    assert (silent, acts) == (2, 2), out
    assert "LAND applied 2 acts" in out, out


def test_the_reposition_end_is_the_next_acts_ledger_teleport_to():
    start, later, key = _act(10)
    assert srg.teleport_to(start[key], later[key]) == (-0.063969, -0.413988)
    start, later, key = _act(16)
    assert srg.teleport_to(start[key], later[key]) == (-0.202495, -0.439503)


def test_a_teleport_that_is_already_in_the_start_ledger_is_stale():
    start, _later, key = _act(16)   # act 10's teleport sits in act 16's start ledger
    assert start[key]["ledger"]["teleport"]["used"]
    assert srg.teleport_to(start[key], start[key]) is None
    assert srg.teleport_to({}, {}) is None


def test_shifting_the_chain_moves_x_and_z_and_keeps_the_height():
    start, _later, key = _act(10)
    moved = srg.shift({"units": dict(start)}, [key], 0.25, -0.5)["units"][key]["positions"]
    assert all(abs(a[0] + 0.25 - b[0]) < 1e-12 and abs(a[2] - 0.5 - b[2]) < 1e-12 and a[1] == b[1]
               for a, b in zip(start[key]["positions"], moved))
