"""RED-first test for tools/param_census.py: a registry param nobody reads must be
reported as NONE, a param read only by non-production code (test / benchmark / census
tool) must NOT count as a reader (the Morale case), and a param read in production
code must be reported with its file:line."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import param_census as census  # noqa: E402


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def _world(tmp_path):
    import json
    reg = tmp_path / "rules_mechanics_fake.json"
    entry = {"primitive": "P", "params": {"phantom_knob": 1, "benchmark_only_knob": 2,
                                          "genuinely_read_knob": 3}}
    _write(str(reg), json.dumps({"_meta": {"system": "fake"}, "common": {},
                                 "factions": {"f": {"Census Phantom": entry}}}))
    _write(str(tmp_path / "src" / "unit.rs"), 'let x = e.param_i("genuinely_read_knob");\n')
    _write(str(tmp_path / "src" / "bin" / "parity.rs"), 'let m = e.param_i("benchmark_only_knob");\n')
    _write(str(tmp_path / "test" / "rules_test.gd"), 'var m := e.param_i("benchmark_only_knob")\n')
    return str(reg), [str(tmp_path / "src")], [str(tmp_path / "src" / "bin"), str(tmp_path / "test")]


def test_unread_param_is_reported_none(tmp_path):
    reg, prod, nonprod = _world(tmp_path)
    rows = census.run(reg, prod, nonprod)
    by_param = {r.param: r for r in rows}
    assert by_param["phantom_knob"].readers == [] and by_param["phantom_knob"].nonprod == []


def test_benchmark_or_test_only_read_is_not_a_reader(tmp_path):
    reg, prod, nonprod = _world(tmp_path)
    rows = census.run(reg, prod, nonprod)
    by_param = {r.param: r for r in rows}
    assert by_param["benchmark_only_knob"].readers == []
    assert by_param["benchmark_only_knob"].nonprod  # listed as "read only by non-production code"


def test_production_reader_is_found_with_location(tmp_path):
    reg, prod, nonprod = _world(tmp_path)
    rows = census.run(reg, prod, nonprod)
    by_param = {r.param: r for r in rows}
    assert any("unit.rs" in h for h in by_param["genuinely_read_knob"].readers)
