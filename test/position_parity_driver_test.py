"""Falsification tests for the parity instrument, independent of Godot."""

import copy
import importlib.util
from pathlib import Path
import pytest

spec = importlib.util.spec_from_file_location(
    "position_parity", Path(__file__).parents[1] / "tools/position_parity.py"
)
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


def example():
    fixtures = {
        "cases": [
            {
                "id": "one",
                "action": {"unit": "u"},
                "units": [{"id": "u", "positions": [[0, 0, 0]], "attached": []}],
            }
        ]
    }
    report = {
        "rows": [
            {
                "id": "one",
                "table_end": [[0, 0, 0]],
                "rust_end": [[0, 0, 0]],
                "model_ids": ["u:0"],
                "rust_model_ids": ["u:0"],
                "rust_ok": True,
                "table_stages": [],
                "rust_capabilities": [],
                "timing_us": {"table": 1, "rust": 2},
                "boundary_reason": "",
            }
        ]
    }
    return fixtures, report


def test_regression_is_detected_when_one_model_moves_an_inch():
    f, r = example()
    baseline = {"fixture_sha256": "same", "measurement": p.measure(f, r)}
    r["rows"][0]["rust_end"][0][0] = p.IN2M
    assert p.regressions(baseline, p.measure(f, r), "same")


def test_missing_stage_is_a_decline_even_with_identical_endpoints():
    f, r = example()
    r["rows"][0]["table_stages"] = [
        "charge_final_placement",
        "final_placement",
        "charge_snap",
    ]
    measured = p.measure(f, r)
    assert measured["summary"]["equal"] == 0
    assert measured["summary"]["within_0.5in"] == 0
    assert measured["summary"]["declined"] == 1
    assert measured["summary"]["by_reason"]["charge_final_placement"] == 1
    assert measured["summary"]["by_reason"]["charge_snap"] == 1
    assert measured["summary"]["models"]["declined"] == 1


def test_timing_is_excluded_but_endpoint_drift_is_not():
    _, a = example()
    b = copy.deepcopy(a)
    b["rows"][0]["timing_us"] = {"table": 999, "rust": 999}
    assert p.stable_rows(a) == p.stable_rows(b)
    b["rows"][0]["rust_end"][0][0] = 0.00001
    assert p.stable_rows(a) != p.stable_rows(b)


@pytest.mark.parametrize(
    "mutation", ["empty", "duplicate", "missing_model", "nan", "bool", "2d"]
)
def test_incomplete_or_invalid_results_fail_closed(mutation):
    f, r = example()
    if mutation == "empty":
        r["rows"] = []
    if mutation == "duplicate":
        r["rows"] *= 2
    if mutation == "missing_model":
        r["rows"][0]["rust_model_ids"] = []
    if mutation == "nan":
        r["rows"][0]["rust_end"][0][0] = float("nan")
    if mutation == "bool":
        r["rows"][0]["rust_end"][0][0] = True
    if mutation == "2d":
        r["rows"][0]["rust_end"] = [[0, 0]]
        r["rows"][0]["table_end"] = [[0, 0]]
    with pytest.raises(ValueError):
        p.measure(f, r)


def test_fixture_drift_requires_an_explicit_reasoned_baseline_update():
    f, r = example()
    m = p.measure(f, r)
    assert p.regressions({"fixture_sha256": "old", "measurement": m}, m, "new")


def test_new_decline_cannot_be_hidden_by_other_improvements():
    f, r = example()
    before = p.measure(f, r)
    r["rows"][0]["table_stages"] = ["whole_unit_shorten"]
    assert p.regressions(
        {"fixture_sha256": "same", "measurement": before}, p.measure(f, r), "same"
    )


def test_existing_decline_does_not_hide_a_worse_endpoint_bucket():
    f, r = example()
    r["rows"][0]["table_stages"] = ["base_shapes"]
    before = p.measure(f, r)
    r["rows"][0]["rust_end"][0][0] = p.IN2M
    assert p.regressions(
        {"fixture_sha256": "same", "measurement": before}, p.measure(f, r), "same"
    )


def test_ordinary_move_boundary_failure_also_declines_the_position():
    f, r = example()
    f["cases"][0]["formation_call"] = {"model_pos": [[0, 0]]}
    r["rows"][0]["formation"] = {
        "ok": False,
        "reason": "parse_error",
        "table": [[0, 0]],
        "recorded": [[0, 0]],
        "rust": [],
    }
    measured = p.measure(f, r)
    assert measured["summary"]["declined"] == 1
    assert measured["summary"]["by_reason"]["parse_error"] == 1
    assert measured["summary"]["formation"]["declined"] == 1


def test_reference_nan_is_rejected_even_when_rust_declines():
    f, r = example()
    r["rows"][0].update(rust_ok=False, boundary_reason="parse_error", rust_end=[])
    r["rows"][0]["table_end"][0][0] = float("nan")
    with pytest.raises(ValueError):
        p.measure(f, r)


def test_both_answers_cannot_silently_drop_an_attached_model():
    f, r = example()
    f["cases"][0].update(
        action={"unit": "u"},
        units=[
            {"id": "u", "positions": [[0, 0, 0]], "attached": ["h"]},
            {"id": "h", "positions": [[0, 0, 1]], "attached": []},
        ],
    )
    with pytest.raises(ValueError):
        p.measure(f, r)


def test_formation_answers_must_include_every_input_model():
    f, r = example()
    f["cases"][0]["formation_call"] = {"model_pos": [[0, 0], [1, 0]]}
    r["rows"][0]["formation"] = {
        "ok": True,
        "table": [[0, 0]],
        "rust": [[0, 0]],
        "recorded": [[0, 0], [1, 0]],
    }
    with pytest.raises(ValueError):
        p.measure(f, r)


def test_stale_output_cannot_pass_when_engine_writes_nothing(tmp_path, monkeypatch):
    from types import SimpleNamespace

    args = SimpleNamespace(
        godot="unused", fixtures=tmp_path / "fixtures.json", timeout=1
    )
    raw = tmp_path / "stale.json"
    raw.write_text('{"schema":1,"rows":[]}')
    monkeypatch.setattr(p.fcntl, "flock", lambda *a: None)
    monkeypatch.setattr(p, "available_mb", lambda: 5000)
    monkeypatch.setattr(p, "busy_godot", lambda: [])
    monkeypatch.setattr(
        p.subprocess, "run", lambda *a, **k: SimpleNamespace(returncode=0)
    )
    with pytest.raises(RuntimeError):
        p.run_godot(args, raw, tmp_path / "run.log")


def test_saved_report_paths_must_be_distinct(monkeypatch, tmp_path):
    import sys

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "position_parity.py",
            "--out",
            str(tmp_path),
            "--check-report",
            "one.json",
            "--check-report",
            "one.json",
        ],
    )
    with pytest.raises(SystemExit) as error:
        p.main()
    assert error.value.code == 2
