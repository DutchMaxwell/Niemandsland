"""AI-G4 row F-H2 (rules epoch 73) - the shoot replay gate moves the shooter through the per-model port.

For an ADVANCE the gate used to let the core translate the shooter RIGIDLY (header knob `movement` off) while the
table plans per model: aof_1000_net_009 act 22 (Claysoul Levy, 24 models) lands 0.7" from its start in the core
and 5.5" away at the table, so the volley is 14+5 dice there and 20+6 dice at the table. The core has the
per-model port (`movement=table`, the melee gate's `--movement`); this gate now takes the same switch: the header
knob, and the board's wall list handed to the port the way `melee_replay_gate.header_walls_m` reads it.

THE BUNDLED GAME. `fixtures/shoot_movement/aof_1000_net_009` is the recorded Claysoul Levy game (AoF 1000 pt,
NET arm, seed 36110), trimmed to the header (its terrain carries the walls), act 22 (state + pick only), `auto`
placeholders for the ordinals before it, every roll of acts 1-22 verbatim and the shots of act 22.

  * `movement=False` is today's gate: the rigid landing parts at the COUNT (the baseline pinned here, so the
    port's gain is read against it).
  * `movement=True` is the port: act 22 is FULL-equal.
  * `red_move_rigid=True` (`--red-move-rigid`) hands over the same walls but leaves the knob OFF: the rigid
    landing is back and the act parts again - the proof that the port, and not the wall list, closes the act.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import shoot_replay_gate as srg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "shoot_movement"


def gate(capsys, **kw) -> tuple[int, int, str]:
    """The gate's own run over the bundled game: (FULL-equal acts, shooting acts, the whole report)."""
    srg.run(FIXTURE, str(REPO), "table", 0, 99, True, sighting="model", **kw)
    out = capsys.readouterr().out
    m = re.search(r"EQUAL : (\d+)/(\d+) acts FULL-equal", out)
    assert m, out
    return int(m.group(1)), int(m.group(2)), out


def test_the_rigid_advance_parts_at_the_count(capsys):
    equal, acts, out = gate(capsys)
    assert (equal, acts) == (0, 1), out
    assert "first field to part: count=1" in out, out


def test_the_movement_port_makes_act_22_full_equal(capsys):
    equal, acts, out = gate(capsys, movement=True)
    assert (equal, acts) == (1, 1), out


def test_red_move_rigid_falls_back_to_the_rigid_landing(capsys):
    equal, acts, out = gate(capsys, movement=True, red_move_rigid=True)
    assert (equal, acts) == (0, 1), out
    assert "first field to part: count=1" in out, out
