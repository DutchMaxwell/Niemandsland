#!/usr/bin/env python3
"""Fixture tests for tools/crossfit_gate.py.

The gate exists because a calibration-only offline proxy has passed and still lost the table A/B. b2 is the
cross-fit version: member A selects, member B scores, and a shuffled-B control must fail. These tests pin the
arithmetic on a known SIGNAL corpus (must PASS) and a pure NOISE corpus (must not), the RED collapse on the signal,
the event-rate floor, the legal mask, and the identity no-op when `--members` is omitted.

Run:  python3 -m pytest tools/crossfit_gate_test.py
"""
import importlib.util
import json
import os
import random

import pytest

np = pytest.importorskip("numpy")
_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("crossfit_gate", os.path.join(_HERE, "crossfit_gate.py"))
cf = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(cf)


def signal_corpus(games=60, per_game=4, seed=1):
    """Member A and member B agree: the row A selects (row 0) is worth ~1.0 more to B than the incumbent (row 1)."""
    rng = random.Random(seed)
    decs = []
    for g in range(games):
        for _ in range(per_game):
            va = [1.0 + rng.uniform(0.0, 0.2)] + [rng.uniform(-0.1, 0.1) for _ in range(3)]
            decs.append({"game": "g%d" % g, "values_a": va, "values_b": list(va), "pick": 1, "margin": 0.1})
    return decs


def noise_corpus(games=400, per_game=4, seed=2):
    """A and B are independent noise: A's selection carries no information for B (event at chance)."""
    rng = random.Random(seed)
    decs = []
    for g in range(games):
        for _ in range(per_game):
            va = [rng.gauss(0, 1) for _ in range(4)]
            pick = min(range(4), key=lambda i: va[i])  # the incumbent is a distinct row -> the pair is unbiased
            decs.append({"game": "g%d" % g, "values_a": va, "values_b": [rng.gauss(0, 1) for _ in range(4)],
                         "pick": pick, "margin": 0.0})
    return decs


def sparse_event_corpus(games=80, per_game=8, seed=3):
    """A large gain on rare events, tiny losses otherwise: gain_lo95 > 0 but event_rate below the 0.20 floor."""
    decs = []
    for g in range(games):
        for j in range(per_game):
            vb = [2.0, 0.0, 0.0, 0.0] if j == 0 else [0.9, 1.0, 0.0, 0.0]
            decs.append({"game": "g%d" % g, "values_a": [2.0, 0.0, 0.0, 0.0], "values_b": vb, "pick": 1, "margin": 0.0})
    return decs


def test_best_a_respects_the_legal_mask():
    d = {"values_a": [5.0, 1.0, 0.0], "values_b": [9.0, 1.0, 0.0], "pick": 2, "margin": 0.0, "legal": [False, True, True]}
    assert cf.best_a(d) == 1  # the illegal row 0 has the highest values_a and must be skipped
    d2 = dict(d, legal=[False, False, False])
    assert cf.best_a(d2) == 2  # nothing legal -> the incumbent pick
    assert cf.best_a(dict(d, legal=[])) == 2  # an EMPTY legal list is not "all legal"


def test_signal_corpus_passes_and_the_shuffle_collapses():
    v = cf.gate(signal_corpus(), perms=8, resamples=400)
    assert v["pass"] is True, v
    assert v["event_rate"] > 0.9
    assert v["red_event_rate"] < v["event_rate"]
    assert v["red_gain_lo95"] <= 0


def test_noise_corpus_is_chance_and_does_not_pass():
    v = cf.gate(noise_corpus(), perms=6, resamples=300)
    assert not v["pass"], v
    assert 0.40 < v["event_rate"] < 0.60  # symmetric noise with margin 0 -> event at chance
    assert v["gain_lo95"] <= 0
    assert v["red_gain_lo95"] <= 0


def test_sparse_events_fail_the_event_rate_floor_despite_a_positive_gain():
    v = cf.gate(sparse_event_corpus(), perms=2, resamples=200)
    assert v["event_rate"] < cf.MIN_EVENT_RATE
    assert v["gain_lo95"] > 0  # the rare big wins do lift the mean
    assert not v["pass"]  # ... but too rare to be a signal


def test_gain_interval_is_ordered():
    decs = signal_corpus()
    gains = [cf.decision_gain(d, d["values_b"]) for d in decs]
    iv = cf.interval(decs, gains, resamples=300, seed=0)
    assert iv["lo95"] <= iv["point"] <= iv["hi95"]


def test_load_corpus_accepts_a_dir_and_a_list(tmp_path):
    decs = signal_corpus(games=2, per_game=1)
    (tmp_path / "a.json").write_text(json.dumps(decs[0]))
    (tmp_path / "b.json").write_text(json.dumps(decs[1]))
    assert len(cf.load_corpus(str(tmp_path))) == 2
    one = tmp_path / "list.json"
    one.write_text(json.dumps(decs))
    assert len(cf.load_corpus(str(one))) == 2
    with pytest.raises(SystemExit):
        bad = tmp_path / "bad.json"
        bad.write_text(json.dumps([{"values_a": [1.0], "values_b": []}]))
        cf.load_corpus(str(bad))
    with pytest.raises(SystemExit):
        badlegal = tmp_path / "badlegal.json"
        badlegal.write_text(json.dumps([{"values_a": [1.0, 2.0], "values_b": [1.0, 2.0], "legal": [True]}]))
        cf.load_corpus(str(badlegal))


def test_no_members_is_a_noop(tmp_path, capsys):
    (tmp_path / "d.json").write_text(json.dumps([{"game": 0, "values_a": [1.0], "values_b": [1.0], "pick": 0}]))
    rc = cf.main(["--corpus", str(tmp_path), "--members", "1"])
    assert rc == 0
    assert "no-op" in capsys.readouterr().out
    assert not list(tmp_path.glob("GATE_CROSSFIT_*.json"))


def test_cli_writes_the_gate_and_passes_on_signal(tmp_path):
    d = tmp_path / "corpus"
    d.mkdir()
    for i, dec in enumerate(signal_corpus(games=20, per_game=2)):
        (d / ("d%02d.json" % i)).write_text(json.dumps(dec))
    out = tmp_path / "GATE.json"
    rc = cf.main(["--corpus", str(d), "--members", "2", "--perms", "4", "--resamples", "300", "--out", str(out)])
    assert rc == 0
    v = json.loads(out.read_text())
    assert v["pass"] is True and v["red_gain_lo95"] <= 0 and v["n_decisions"] == 40
