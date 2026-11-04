"""AI-G4 round 2, row G4-H7 (rules epoch 73) - a charge on a target the cast leg destroyed resolves nothing.

The table's activation is [movement] -> spell cast -> charge. When the spell destroys the charge target, the table
logs "<charger>'s charge falls short" and draws no charge dice and no dangerous test: the recorded rolls of the act
are the cast die and the spell's own saves, which the gate cuts. The state the gate patches from the `pre` line then
holds the target with no living model (host AND joined heroes) - and the core, handed the recorded landing of the
charge, still carried the move out. On aof_1000_net_026 act 30 that move crosses dangerous terrain and the core draws
the charger's own six-dice test, which the table never drew: the act landed in `table_silent`, which fails the gate.

(The charge diagnosis read these six dice as a strike on the destroyed unit. They are not: switching the core's own
dangerous test off leaves the act silent, and the core never reaches the melee - there is no model to be near.)

THE FIX IS IN THE CORE (sim.rs): from `EPOCH_73_V36` a charge on a unit with no living model, host and joined heroes,
resolves nothing - no move, so no test and no fight. The GATE does not skip anything: it replays the patched state and
the core proves itself silent; the act then counts as both-silent by the existing formula.

THE BUNDLED GAMES (`fixtures/g4r2_h7/`, the 1104 recording, trimmed like the other fixtures):

  * aof_1000_net_026 act 30 - the spell destroys all three `Lust Bliss Beast Riders`; before the guard the core drew
    6 dice (table_silent).
  * aof_1000_net_010 act 26 - the spell destroys the five `Automa Drones`; both sides were already silent.

THE GUARD-OFF MUTANT is the same recording stamped rules epoch 72: the old leg is back and the six dice with it.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "g4r2_h7"


def charge(capsys, report_only: bool, ref: Path = FIXTURES) -> tuple[int, str]:
    rc = mrg.run(ref, str(REPO), "table", 0, report_only, movement=True)
    return rc, capsys.readouterr().out


def test_a_charge_on_a_target_the_spell_destroyed_is_both_silent(capsys):
    rc, out = charge(capsys, False)
    assert "(2 both silent + 0 table silent)" in out, out
    assert "BOTH-SILENT: 2/2 acts" in out, out
    assert rc == 0, out


def test_the_core_is_asked_and_proves_itself_silent(capsys, monkeypatch):
    """No skip in the gate: the live core resolves both acts and draws not one die."""
    import nml_core

    drawn = []
    real = nml_core.load

    def spy(repo):
        core = real(repo)
        resolve = core.resolve_with_tray

        class Spy:
            def __getattr__(self, name):
                return getattr(core, name)

            def resolve_with_tray(self, *a, **kw):
                nxt, report = resolve(*a, **kw)
                drawn.append(len(report["rolls"]))
                return nxt, report

        return Spy()

    monkeypatch.setattr(nml_core, "load", spy)
    charge(capsys, True)
    assert drawn == [0, 0], "the core drew dice against a destroyed target (per act): %s" % drawn


def test_guard_off_the_core_draws_the_six_dice_again(capsys, tmp_path):
    """The mutant: the recording stamped epoch 72 replays on the old leg - the charger walks to its landing through the
    dangerous terrain and rolls the test the table never drew."""
    old = tmp_path / "ref"
    shutil.copytree(FIXTURES, old)
    for game in old.iterdir():
        lines = (game / "acts.jsonl").read_text().splitlines()
        head = json.loads(lines[0])
        head["knobs"]["rules_epoch"] = 72
        (game / "acts.jsonl").write_text("\n".join([json.dumps(head)] + lines[1:]) + "\n")
    rc, out = charge(capsys, False, old)
    assert "(1 both silent + 1 table silent)" in out, out
    assert rc == 1, out
