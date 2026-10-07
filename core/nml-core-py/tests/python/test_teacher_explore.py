"""Root exploration for the teacher recorder (NachtmahrZero E2, 07.10.2026) — `teacher_record.Explorer`, default OFF.

  * OFF = no Explorer is built and `pack` writes no `explored` column: the records are the ones main wrote;
  * ON = the first 8 decisions of an exploring seat sample from `0.75 * root prior + 0.25 * Dirichlet(0.3)`
    (the pool softmax where no tree prior exists), then the pick is left alone; seeded, so two runs agree and
    two seeds differ; the stamp `explored` lands on exactly the sampled rows.
Pure Python: no core, no net, no private fixtures.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "tools"))
import teacher_record as tr  # noqa: E402

N = 6


def fake_pick(tree=True):
    trace = {"cands": [{"unit": "u%d" % i} for i in range(N)], "best_idx": 0,
             "scored": [{"idx": i, "score": 1.0 - 0.1 * i} for i in range(N)]}
    if tree:
        trace["tree"] = {"root": [[i, 100 if i == 0 else 20, 0.5] for i in range(N)]}
    return {"trace": trace, "action": trace["cands"][0], "unit_key": "u0"}


def run(seed, seat=1, picks=12, tree=True, seats=(1, 2)):
    ex = tr.make_explorer(seed, "row-1", seats)
    out = []
    for _ in range(picks):
        p = fake_pick(tree)
        flag = ex.apply(p, seat)
        out.append((flag, p["played_idx"] if "played_idx" in p else 0, p["unit_key"]))
    return out


def test_off_builds_no_explorer_and_pack_has_no_column():
    assert tr.make_explorer(-1, "row-1", (1, 2)) is None
    rows = [{k: np.zeros(1) for k in tr.FLAT} | {"glob": np.zeros(3), **{k: np.zeros((1, 2)) for k in tr.RAGGED}}]
    assert "explored" not in tr.pack(rows, "p1")
    rows[0]["explored"] = np.int8(1)
    assert tr.pack(rows, "p1")["explored"].tolist() == [1]


def test_same_seed_same_picks_other_seed_other_picks():
    a, b = run(7), run(7)
    assert a == b
    assert any(a != run(s) for s in range(8, 14))


def test_only_the_first_eight_decisions_of_an_exploring_seat_are_sampled():
    got = run(3, picks=12)
    assert [f for f, _, _ in got] == [True] * 8 + [False] * 4
    assert all(i == 0 and u == "u0" for f, i, u in got[8:])  # past the window the pick is left alone
    assert all(not f for f, _, _ in run(3, seat=2, seats=(1,)))  # a seat outside --explore-seats never explores


def test_noise_moves_some_picks_and_the_prior_keeps_most():
    moved = [i for f, i, _ in (x for s in range(60) for x in run(s, picks=8)) if i != 0]
    total = 60 * 8
    assert 0.02 * total < len(moved) < 0.6 * total  # exploration happens, the prior still carries the argmax


def test_no_tree_falls_back_to_the_pool_softmax_and_swaps_the_action():
    ex = tr.make_explorer(5, "row-2", (1, 2))
    seen = set()
    for _ in range(8):
        p = fake_pick(tree=False)
        ex.apply(p, 1)
        assert p["unit_key"] == p["action"]["unit"] == "u%d" % p.get("played_idx", 0)
        seen.add(p.get("played_idx", 0))
    assert seen <= set(range(N))
