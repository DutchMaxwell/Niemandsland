"""G4-C7b (rules epoch 73) - when the core executes the gather pick, the stragglers are pulled back into coherency.

The G4-C7 menu row gives a unit that starts its activation out of coherency one pick, the gather: an ADVANCE that stays
where the unit stands. The table runs it through the placement gate (`_act_regroup` hands `_finalize_placement` the
UNMOVED positions), so the stragglers are pulled in although the centre goes nowhere. The core's move port returned
before the gate when nothing moved, so an imagined unit stayed torn and was held to the gather pick again and again.

SOURCES (3.6 parity recordings, cut down to the header, the act-start state and the table's own after-state of the
unit by a one-off script; the corpus itself is not committed):
  * g4_c7b/aof_026_act24.json - aof_1000_net_026 act 24, Royal Guard (4 models, the 9 inch chain of Age of Fantasy);
  * g4_c7b/gf_001_act30.json  - gf_1000_net_001 act 30, Battle Brothers (10 models, the 6 inch skirmish chain);
  * g4_c7/act26.json          - aof_1000_net_022 act 26, Havoc Ogres: the table's gather could NOT close the gap there
    (the straggler would rest on ground it may not rest on), so the unit stays where it stands at the table.

The coherency check is written from the rule in plain Python (a 1 inch link between base edges, every model in one
chain, no two models farther apart than the chain), not asked of the core.

Legs (the unit is the recorded one, the pick is the menu's own row, the board is the recorded board):
  * at epoch 73 the executed gather ends where the TABLE'S unit ended (every model within 0.05 inches) and coherent;
  * the battle log names the Regroup rule;
  * below 73 the old early return stands: nothing moves, the unit stays torn;
  * act 26: the core, like the table, leaves the unit where it stands;
  * the SAME unit packed into a tight row is coherent: the same pick moves nothing (no free re-arrangement).
"""

from __future__ import annotations

import copy
import itertools
import json
import math
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[4]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
IN2M = 0.0254
GATHERED = ["g4_c7b/aof_026_act24.json", "g4_c7b/gf_001_act30.json"]


def _fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text())


def _gap_in(a, ra, b, rb) -> float:
    return math.hypot(a[0] - b[0], a[2] - b[2]) / IN2M - (ra + rb) / IN2M


def coherent(positions, radii, chain_in) -> bool:
    """One chain of 1 inch base-edge links holding every model, no two models farther apart than `chain_in`."""
    n = len(positions)
    if n <= 1:
        return True
    seen, todo = {0}, [0]
    while todo:
        i = todo.pop()
        for j in range(n):
            if j not in seen and _gap_in(positions[i], radii[i], positions[j], radii[j]) <= 1.0 + 1e-6:
                seen.add(j)
                todo.append(j)
    spread = max(_gap_in(positions[i], radii[i], positions[j], radii[j]) for i, j in itertools.combinations(range(n), 2))
    return len(seen) == n and spread <= chain_in


def _chain_in(fix: dict) -> float:
    return 6.0 if fix["header"]["profiles"][fix["charger"]]["game_system"] in ("gff", "aofs") else 9.0


def _core(fix: dict, rules_epoch: int | None = None):
    import nml_core

    head = fix["header"]
    knobs = dict(head["knobs"], hero_attach=True, engage_fold=True, movement=True)
    if rules_epoch is not None:
        knobs["rules_epoch"] = rules_epoch
    core = nml_core.load(str(REPO))
    core.set_header({"profiles": head["profiles"], "terrain": head["terrain"], "knobs": knobs})
    return core


def _gather(fix: dict, rules_epoch: int | None = None):
    """The unit's one pick, an ADVANCE on its own centre, executed: (positions before, positions after, the log)."""
    import nml_core

    unit = fix["state"]["units"][fix["charger"]]
    n = len(unit["positions"])
    centre = [sum(p[i] for p in unit["positions"]) / n for i in (0, 1, 2)]
    core = _core(fix, rules_epoch)
    nxt, report = core.resolve_with_tray(
        core.state_of(fix["state"]), {"kind": 1, "unit": fix["charger"], "dest": centre}, nml_core.Rng(0), nml_core.Tray(1)
    )
    return unit["positions"], nxt.plain()["units"][fix["charger"]]["positions"], report["log"]


def _worst_in(a, b) -> float:
    return max(math.hypot(p[0] - q[0], p[2] - q[2]) for p, q in zip(a, b)) / IN2M


@pytest.mark.parametrize("name", GATHERED)
def test_the_recorded_unit_starts_torn_at_rules_73(name):
    fix = _fixture(name)
    unit = fix["state"]["units"][fix["charger"]]
    assert fix["header"]["knobs"]["rules_epoch"] == 73
    assert not coherent(unit["positions"], unit["radii"], _chain_in(fix)), "the fixture must start out of coherency"
    assert coherent(fix["table_after"], unit["radii"], _chain_in(fix)), "the table gathered it"


@pytest.mark.parametrize("name", GATHERED)
def test_the_executed_gather_ends_where_the_table_ended(name):
    fix = _fixture(name)
    radii = fix["state"]["units"][fix["charger"]]["radii"]
    _, after, _ = _gather(fix)
    assert coherent(after, radii, _chain_in(fix)), "the gather left the unit torn"
    assert _worst_in(after, fix["table_after"]) < 0.05, "the core's gather parts from the table's"


@pytest.mark.parametrize("name", GATHERED)
def test_the_battle_log_names_the_regroup_rule(name):
    _, _, log = _gather(_fixture(name))
    assert any(line.startswith("Regroup:") for line in log), log


@pytest.mark.parametrize("name", GATHERED)
def test_below_epoch_73_nothing_moves(name):
    fix = _fixture(name)
    radii = fix["state"]["units"][fix["charger"]]["radii"]
    before, after, log = _gather(fix, rules_epoch=72)
    assert _worst_in(before, after) < 1e-4, "epoch 72: nothing moves"
    assert not coherent(after, radii, _chain_in(fix)), "epoch 72 keeps the unit torn"
    assert not any(line.startswith("Regroup:") for line in log), log


def test_a_gather_the_table_could_not_carry_out_leaves_the_unit_where_it_stands():
    fix = _fixture("g4_c7/act26.json")
    fix["table_after"] = fix["state"]["units"][fix["charger"]]["positions"]
    _, after, _ = _gather(fix)
    assert _worst_in(after, fix["table_after"]) < 1e-4, "the straggler cannot rest there: the table left the unit alone"


def test_a_coherent_unit_is_not_rearranged_for_free():
    fix = _fixture("g4_c7b/aof_026_act24.json")
    unit = fix["state"]["units"][fix["charger"]]
    n = len(unit["positions"])
    cx = sum(p[0] for p in unit["positions"]) / n
    cz = sum(p[2] for p in unit["positions"]) / n
    step = 2 * max(unit["radii"]) + 0.005
    packed = copy.deepcopy(fix)
    for i, p in enumerate(packed["state"]["units"][fix["charger"]]["positions"]):
        p[0], p[2] = cx + (i - (n - 1) / 2) * step, cz
    assert coherent(packed["state"]["units"][fix["charger"]]["positions"], unit["radii"], 9.0)
    before, after, _ = _gather(packed)
    assert _worst_in(before, after) < 0.05
