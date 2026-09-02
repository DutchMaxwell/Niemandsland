"""ARRIVAL section tests (S4, SPEC_rule_ambush_arrival_2026-09-02.md §4): the fixture parser,
the exact/within/mismatch/held classifier, the import guard (twin absent -> NO VERDICT, never a
fake pass), and the section's own --arrival-red-shift knob.

`deployment::arrive_one` has not landed in this tree (S1-S3 build in parallel per the spec's own
step ordering), so every test that needs a "twin" monkeypatches `nml_core.arrive_one` directly —
the same shape test_deployment_gate.py uses to synthesize its own truth.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import deployment_gate as gate  # noqa: E402


def _case(name, spot, own_ring_m=0.2286, base_r=0.016):
    return {"case": name, "zone": [-0.9144, -0.6096, 1.8288, 1.2192], "objectives": [[0.0, 0.0]],
            "occupied": [], "enemies": [], "own_ring_m": own_ring_m,
            "footprint": [[0.0, 0.0]], "base_r": base_r, "flying": False, "spot": spot}


def _write_fixture(tmp_path, cases):
    with open(os.path.join(tmp_path, "ambush_arrival.json"), "w") as f:
        json.dump({"schema": 1, "cases": cases}, f)


# === arrival_class — the vocabulary itself ======================================================

def test_arrival_class_exact_within_mismatch_held():
    assert gate.arrival_class([0.3, 0.2], [0.3, 0.2]) == "exact"
    assert gate.arrival_class([0.0, 0.0], [gate.SCAN_STEP, 0.0]) == "within"
    assert gate.arrival_class([0.0, 0.0], [1.0, 1.0]) == "mismatch"
    assert gate.arrival_class(None, None) == "held"
    assert gate.arrival_class(None, [0.0, 0.0]) == "mismatch"
    assert gate.arrival_class([0.0, 0.0], None) == "mismatch"


# === the fixture actually shipped by tools/ambush_arrival_dump.gd ==============================

def test_committed_fixture_loads_and_the_import_guard_refuses_a_verdict(capsys):
    fixtures = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..",
                             "nml-core", "tests", "fixtures")
    code = gate.main(["--arrival", "--fixtures", fixtures])
    out = capsys.readouterr().out
    assert code == 2
    assert "100 cases" in out
    assert "1 held" in out
    assert "NO VERDICT" in out
    assert "floor OK" not in out and "floor REGRESSION" not in out


# === the RED knob, on a synthetic twin (mirrors test_deployment_gate.py's own truth-from-twin) ==

def test_arrival_red_knob_collapses_exact(tmp_path, monkeypatch, capsys):
    truths = [[0.3, 0.2], None]
    _write_fixture(tmp_path, [_case("hit", truths[0]), _case("held", truths[1])])
    it = iter(truths)
    monkeypatch.setattr(gate.nml_core, "arrive_one", lambda *a, **k: next(it), raising=False)
    code = gate.main(["--arrival", "--fixtures", str(tmp_path)])
    assert code == 0
    out = capsys.readouterr().out
    assert "1 exact | 0 within | 0 mismatch | 1 held" in out
    assert "floor OK" in out

    it = iter(truths)
    monkeypatch.setattr(gate.nml_core, "arrive_one", lambda *a, **k: next(it), raising=False)
    code = gate.main(["--arrival", "--arrival-red-shift", "1", "--fixtures", str(tmp_path)])
    out = capsys.readouterr().out
    assert "0 exact" in out
    assert "collapsed, exit 1 as designed" in out
    assert code == 1


def test_arrival_mismatch_regresses_the_floor(tmp_path, monkeypatch, capsys):
    _write_fixture(tmp_path, [_case("hit", [0.3, 0.2])])
    monkeypatch.setattr(gate.nml_core, "arrive_one", lambda *a, **k: [9.0, 9.0], raising=False)
    code = gate.main(["--arrival", "--fixtures", str(tmp_path)])
    out = capsys.readouterr().out
    assert "0 exact | 0 within | 1 mismatch | 0 held" in out
    assert "floor REGRESSION" in out
    assert code == 1
