#!/usr/bin/env python3
"""Fixture tests for tools/judge_b2.py.

The judge harness asks whether a NEW candidate selector (the judge, member A) adds ordering signal that the
hand leaf (the scorer, member B) can see. `crossfit_gate` already gates a member-A selection with a shuffled-LEAF
control; here the control shuffles the JUDGE, because a real judge's *selection* must vanish when its own values
are permuted. These tests pin the arithmetic on a known SIGNAL corpus (must PASS), a pure NOISE corpus (must not),
the degenerate TIED-JUDGE corpus that makes the control non-null (the RED exit-1 case), and the identity no-op.

Run:  python3 -m pytest tools/judge_b2_test.py
"""
import importlib.util
import json
import os
import random

import pytest

np = pytest.importorskip("numpy")
_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("judge_b2", os.path.join(_HERE, "judge_b2.py"))
jb = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(jb)


def signal_corpus(games=60, per_game=4, seed=1):
    """The judge ranks row 0 above the incumbent row 1, and the leaf agrees: a genuine, shuffle-collapsible signal."""
    rng = random.Random(seed)
    decs = []
    for g in range(games):
        for _ in range(per_game):
            gap = 0.1 + rng.uniform(0.0, 0.1)
            vb = [0.9 + gap, 0.9, rng.uniform(0.0, 0.05), rng.uniform(0.0, 0.05)]
            decs.append({"game": "g%d" % g, "values_a": [2.0, 1.0, 0.0, 0.0], "values_b": vb,
                         "pick": 1, "margin": 0.0})
    return decs


def tied_judge_corpus(games=60, per_game=4, seed=4):
    """Every judge value is tied, so shuffling the judge changes nothing: the control CANNOT collapse (RED)."""
    decs = []
    for g in range(games):
        for _ in range(per_game):
            decs.append({"game": "g%d" % g, "values_a": [1.0, 1.0, 1.0, 1.0],
                         "values_b": [1.0, 0.0, 0.0, 0.0], "pick": 1, "margin": 0.0})
    return decs


def noise_corpus(games=400, per_game=4, seed=2):
    """A and B are independent noise: the judge's selection carries no information for the leaf."""
    rng = random.Random(seed)
    decs = []
    for g in range(games):
        for _ in range(per_game):
            va = [rng.gauss(0, 1) for _ in range(4)]
            pick = min(range(4), key=lambda i: va[i])  # the incumbent is a distinct row -> an unbiased pair
            decs.append({"game": "g%d" % g, "values_a": va, "values_b": [rng.gauss(0, 1) for _ in range(4)],
                         "pick": pick, "margin": 0.0})
    return decs


def test_signal_corpus_passes_and_the_judge_shuffle_collapses():
    v = jb.gate(signal_corpus(), perms=8, resamples=400)
    assert v["pass"] is True, v
    assert v["event_rate"] > 0.9
    assert v["judge_shuffle_event_rate"] < v["event_rate"]
    assert v["judge_shuffle_lo95"] <= 0


def test_noise_corpus_is_chance_and_does_not_pass():
    v = jb.gate(noise_corpus(), perms=6, resamples=300)
    assert not v["pass"], v
    assert 0.40 < v["event_rate"] < 0.60
    assert v["gain_lo95"] <= 0
    assert v["judge_shuffle_lo95"] <= 0


def test_tied_judge_makes_the_shuffle_non_null_and_fails():
    v = jb.gate(tied_judge_corpus(), perms=4, resamples=200)
    assert v["judge_shuffle_lo95"] > 0  # a tied judge cannot be shuffled away
    assert not v["pass"]


def test_cli_exits_1_when_the_judge_shuffle_is_not_null(tmp_path):
    d = tmp_path / "corpus"
    d.mkdir()
    for i, dec in enumerate(tied_judge_corpus(games=20, per_game=2)):
        (d / ("d%02d.json" % i)).write_text(json.dumps(dec))
    out = tmp_path / "GATE.json"
    rc = jb.main(["--corpus", str(d), "--members", "2", "--perms", "3", "--resamples", "200", "--out", str(out)])
    v = json.loads(out.read_text())
    assert v["judge_shuffle_lo95"] > 0
    assert rc == 1


def test_cli_passes_on_signal(tmp_path):
    d = tmp_path / "corpus"
    d.mkdir()
    for i, dec in enumerate(signal_corpus(games=20, per_game=2)):
        (d / ("d%02d.json" % i)).write_text(json.dumps(dec))
    out = tmp_path / "GATE.json"
    rc = jb.main(["--corpus", str(d), "--members", "2", "--perms", "4", "--resamples", "300", "--out", str(out)])
    v = json.loads(out.read_text())
    assert rc == 0
    assert v["pass"] is True and v["judge_shuffle_lo95"] <= 0 and v["n_decisions"] == 40


def test_judge_shuffle_permutes_the_selection():
    decs = signal_corpus(games=1, per_game=6)
    gains = jb.judge_shuffle_gains(decs, random.Random(0))
    assert len(gains) == len(decs)
    assert any(abs(g) < 1e-9 for g in gains)  # some permutation lands the judge on the incumbent row


def test_no_members_is_a_noop(tmp_path, capsys):
    (tmp_path / "d.json").write_text(json.dumps([{"game": 0, "values_a": [1.0], "values_b": [1.0], "pick": 0}]))
    rc = jb.main(["--corpus", str(tmp_path), "--members", "1"])
    assert rc == 0
    assert "no-op" in capsys.readouterr().out
    assert not list(tmp_path.glob("GATE_JUDGE_B2_*.json"))
