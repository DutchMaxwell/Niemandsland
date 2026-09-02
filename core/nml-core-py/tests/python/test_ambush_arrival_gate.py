"""ARRIVAL section tests (S4, SPEC_rule_ambush_arrival_2026-09-02.md §4): the fixture parser,
the exact/within/mismatch/held classifier, the import guard (twin absent -> NO VERDICT, never a
fake pass), and the section's own --arrival-red-shift knob.

S3b UPDATE: `nml_core.arrive_one` now EXISTS (the py binding over
`deployment::arrive_one`), so the import guard no longer fires on the committed fixture and the
section gives a real verdict instead. The guard itself is still tested — with the symbol removed,
which is the state it was written for. Tests that need a controlled twin keep monkeypatching
`nml_core.arrive_one`, the shape test_deployment_gate.py uses to synthesize its own truth.
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

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..",
                        "nml-core", "tests", "fixtures")


def test_the_import_guard_still_refuses_a_verdict_without_a_twin(capsys, monkeypatch):
    """The guard the section was built around, tested in the state it guards: no
    `nml_core.arrive_one` at all. It must REFUSE (code 2), never fake a pass."""
    monkeypatch.delattr(gate.nml_core, "arrive_one", raising=False)
    code = gate.main(["--arrival", "--fixtures", FIXTURES])
    out = capsys.readouterr().out
    assert code == 2
    assert "100 cases" in out and "NO VERDICT" in out
    assert "floor OK" not in out and "floor REGRESSION" not in out


def test_committed_fixture_gives_a_real_verdict_now_that_the_twin_exists(capsys):
    """S3b: with the binding landed the section reports classes for all 100 cases
    and reaches a verdict. The NUMBERS are deliberately NOT pinned here — the
    recorded-case oracle is a reconstruction (`ambush_arrival_corpus.py` takes
    the post-arrival centroid as the drop anchor and carries no terrain), so a
    floor baked in today would pin the fixture's error, not the port's.

    What IS pinned is the shape: every case classified, exactly one held (the
    synthetic `held_fully_occupied`), and a verdict line printed."""
    code = gate.main(["--arrival", "--fixtures", FIXTURES])
    out = capsys.readouterr().out
    assert "100 cases" in out and "1 held" in out
    assert "NO VERDICT" not in out
    assert ("floor OK" in out) == (code == 0)
    assert code in (0, 1)


def test_the_two_synthetic_cases_match_the_table():
    """The only two cases whose truth came STRAIGHT off the table
    (`tools/ambush_arrival_dump.gd` against the shipped
    `SoloController.arrive_one_ambush_unit`, no reconstruction in between):
    Repel Ambushers' 12" override, and a provably unplaceable board. Both must
    be exact — this is the claim `arrive_one` can actually stand behind, and it
    fails the moment the ring `max` or the held path moves."""
    cases = json.load(open(os.path.join(FIXTURES, "ambush_arrival.json")))["cases"]
    named = {c["case"]: c for c in cases}
    for name, want in (("ambush_vs_repel_ambushers", "exact"), ("held_fully_occupied", "held")):
        c = named[name]
        twin = gate.nml_core.arrive_one(
            c["zone"], c["objectives"], [dict(o) for o in c["occupied"]],
            [dict(e) for e in c["enemies"]], c["own_ring_m"],
            gate.radius_of(len(c["footprint"]), c["base_r"]), c["footprint"],
            c["base_r"], c["flying"],
        )
        assert gate.arrival_class(c["spot"], twin) == want, "%s: %s vs %s" % (
            name, c["spot"], twin,
        )


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
