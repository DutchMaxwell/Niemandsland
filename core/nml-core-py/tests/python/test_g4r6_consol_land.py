"""AI-G4 round 6, row R21 F-CONSOL-LAND (rules epoch 73, GATE ONLY) - the melee gate replays a consolidation where the
table's consolidation LANDED.

A winner who wiped its enemy "may" move up to 3" (Consolidation Moves) - the book names no destination, so the core's
pick (the nearest marker its side does not own) and the table's planner pick are both legal. The table's own Dangerous
terrain test on ITS destination then has no core twin, and the gate filed that die under `morale_table_only` (a
`dangerous`-leg die read as a morale die). The gate now hands the core the table's recorded final charger centroid as a
NEUTRAL marker, for a charge whose next act shows the charger alive and the defender wiped, and tells a recorded
`dangerous`-leg die from a morale die. Neither the core nor the table changes.

THE BUNDLED ACT (the 1105 round-5a recording, GF 1000 pt NET arm, trimmed like `g4r5_dang_tail_melee`: the header, an
`auto` placeholder for every earlier activation, the act line, the NEXT act line and every roll up to the act):

  * `fixtures/g4r6_consol_land/gf_1000_net_005` act 26 - the Destroyer wipes the Change Sentinel Walker, consolidates 2.9"
    east and takes one Dangerous terrain test there (1 die, 6+); the core, aiming at the neutral marker to the
    south-west, crossed no dangerous ground and rolled none.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import melee_replay_gate as mrg  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def melee(capsys, **kw) -> str:
    mrg.run(FIXTURES / "g4r6_consol_land", str(REPO), "table", 0, True, movement=True, **kw)
    return capsys.readouterr().out


def test_the_wiping_charge_is_full_equal_with_the_tables_consolidation_marker(capsys):
    """Before: 0/1 - the table's trailing 1-die 6+ roll was a die the core never rolled, `morale_table_only`.
    After: every roll equal, the die is the same face, and it is no morale die on either side."""
    out = melee(capsys)
    assert "EQUAL : 1/1 acts FULL-equal" in out, out
    assert "0 table only" in out, out


def test_the_mutant_without_the_marker_parts_the_act_again(capsys):
    """`--red-consol-land` hands the core no marker: the old numbers - 0/1, the table's test is the one die the core lacks."""
    out = melee(capsys, red_consol_land=True)
    assert "EQUAL : 0/1 acts FULL-equal" in out and "1 table_longer" in out, out


def test_below_epoch_73_the_gate_asks_for_no_marker(capsys, tmp_path, monkeypatch):
    """The same act recorded at rules epoch 72 never reaches `consol_marker` (the epoch-73 act does: the control)."""
    calls = []
    orig = mrg.consol_marker
    monkeypatch.setattr(mrg, "consol_marker", lambda *a: calls.append(a) or orig(*a))
    melee(capsys)
    assert len(calls) == 1
    game = tmp_path / "gf_1000_net_005"
    game.mkdir()
    for f in (FIXTURES / "g4r6_consol_land" / "gf_1000_net_005").iterdir():
        game.joinpath(f.name).write_text(f.read_text())
    rows = (game / "acts.jsonl").read_text().splitlines()
    head = json.loads(rows[0])
    head["knobs"]["rules_epoch"] = 72
    (game / "acts.jsonl").write_text("\n".join([json.dumps(head)] + rows[1:]) + "\n")
    mrg.run(tmp_path, str(REPO), "table", 0, True, movement=True)
    assert len(calls) == 1, "the epoch-72 act asked for a marker"


def test_the_marker_is_the_chargers_final_centroid_and_only_for_a_wipe():
    plain = {"objectives": [{"owner": 2, "pos": [1.0, 0.0, 1.0]}]}
    action = {"unit": "a", "charge": "b"}
    nxt = {"units": {"a": {"alive": 2, "positions": [[0.0, 0.0, 0.0], [2.0, 0.0, 4.0]]}, "b": {"alive": 0, "positions": []}}}
    assert mrg.consol_marker(plain, action, nxt)["objectives"] == plain["objectives"] + [{"owner": 0, "pos": [1.0, 0.0, 2.0]}]
    assert plain["objectives"] == [{"owner": 2, "pos": [1.0, 0.0, 1.0]}]  # the recorded state is not edited
    for edit in ({"b": {"alive": 1, "positions": [[0.0, 0.0, 0.0]]}}, {"a": {"alive": 0, "positions": []}}):
        assert mrg.consol_marker(plain, action, {"units": dict(nxt["units"], **edit)}) is plain
    assert mrg.consol_marker(plain, action, None) is plain


def test_a_dangerous_leg_die_is_not_a_morale_die():
    """`trailing_morale` stops at a recorded `dangerous`-leg roll (a sixth tuple field); a `main`-leg die still counts."""
    defence = ("defense", 2, 5, [1, 6], "AI (Walker)")
    assert mrg.trailing_morale([defence, ("attack", 1, 6, [2], "AI (Destroyer)", "dangerous")]) == []
    morale = ("attack", 1, 4, [2], "AI (Destroyer)", "main")
    assert mrg.trailing_morale([defence, morale]) == [morale]
