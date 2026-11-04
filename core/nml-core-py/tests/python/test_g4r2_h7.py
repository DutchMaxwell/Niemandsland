"""AI-G4 round 2, row G4-H7 (rules epoch 73) - a cast leg that destroys the charge target leaves nothing to charge.

The table's activation is [movement] -> spell cast -> charge. When the spell destroys the charge target, the table
logs "<charger>'s charge falls short" and draws no charge dice; the recorded rolls of the act are the cast die and the
spell's own saves, which the gate cuts. The state the gate patches from the `pre` line then holds the target with no
living model (host AND joined heroes), and the core - which was handed a charge on it - strikes a destroyed unit and
rolls six dice the table never did: the act landed in `table_silent`, which fails the gate.

The gate now treats such an act as what it is: the table is silent after the cut and the charge is void, so the core
is not asked and the act counts as both-silent (equal), like the table's "falls short".

THE BUNDLED GAMES (`fixtures/g4r2_h7/`, the 1104 recording, trimmed like the other fixtures):

  * aof_1000_net_026 act 30 - the spell destroys all three `Lust Bliss Beast Riders`; before the fix the
    core rolled 6 dice at the dead unit (table_silent).
  * aof_1000_net_010 act 26 - the spell destroys the five `Automa Drones`; both sides were already silent.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "g4r2_h7"


def charge(capsys, report_only: bool) -> tuple[int, str]:
    rc = mrg.run(FIXTURES, str(REPO), "table", 0, report_only, movement=True)
    return rc, capsys.readouterr().out


def test_a_charge_on_a_target_the_spell_destroyed_is_both_silent(capsys):
    rc, out = charge(capsys, False)
    assert "(2 both silent + 0 table silent)" in out, out
    assert "BOTH-SILENT: 2/2 acts" in out, out
    assert rc == 0, out


def test_the_core_is_not_asked_to_strike_a_destroyed_unit(capsys, monkeypatch):
    """The live core must not even be called for the act: a call is where the six stray dice came from."""
    import nml_core

    calls = []
    real = nml_core.load

    def spy(repo):
        core = real(repo)
        resolve = core.resolve_with_tray

        class Spy:
            def __getattr__(self, name):
                return getattr(core, name)

            def resolve_with_tray(self, *a, **kw):
                calls.append(a[1].get("charge"))
                return resolve(*a, **kw)

        return Spy()

    monkeypatch.setattr(nml_core, "load", spy)
    charge(capsys, True)
    assert calls == [], "the gate resolved a charge on a destroyed target: %s" % calls
