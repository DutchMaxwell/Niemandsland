#!/usr/bin/env python3
"""Fixture tests for tools/act_wall_summary.py, the [ACT_WALL] (NML_ACT_WALL=1) summariser.

Ten known decisions 100,000..1,000,000 us = 100..1000 ms after floor(us/1000): nearest rank
values[min(len-1, int(p*len))] gives p50 = values[5] = 600, p90 = p99 = max = 1000, mean 550,
over1s 0.0 % — exactly 1,000,000 us is one second, not OVER one second.
Run:  python3 -m pytest -q tools/act_wall_summary_test.py
"""

import importlib.util
import json
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "act_wall_summary", os.path.join(_HERE, "act_wall_summary.py"))
aws = importlib.util.module_from_spec(_SPEC)
sys.modules["act_wall_summary"] = aws
_SPEC.loader.exec_module(aws)

SUMMARY = "acts=10 files=1 p50=600 p90=1000 p99=1000 max=1000 mean=550 over1s=0.0%"


def _log(path, rows):
    """rows: (driver, round, seat, us) -> one [ACT_WALL] line each, plus noise."""
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("Godot Engine v4.6.stable\n[Graphics] window on screen 0 of 0\n")
        for d, r, p, us in rows:
            fh.write(f"[ACT_WALL] {d} r{r} p{p} us={us}\n")
    return str(path)


def _known(tmp_path):
    """Round 1 = 100k..600k us (6 acts), round 2 = 700k..1000k us (4 acts)."""
    rows = [("harness", 1, 1, u) for u in range(100_000, 700_000, 100_000)]
    rows += [("harness", 2, 2, u) for u in range(700_000, 1_100_000, 100_000)]
    return _log(tmp_path / "known.log", rows)


def test_known_decisions_and_round_split(tmp_path, capsys):
    rc = aws.main([_known(tmp_path)])
    assert rc == 0
    assert capsys.readouterr().out.splitlines() == [
        SUMMARY, "r1: acts=6 p50=400 p90=600", "r2: acts=4 p50=900 p90=1000"]


def test_driver_filter_and_files_count(tmp_path, capsys):
    log = _log(tmp_path / "d.log", [
        ("interactive", 1, 1, 100_000), ("interactive", 1, 2, 200_000),
        ("interactive", 1, 1, 1_500_000), ("harness", 1, 2, 700_000),
        ("harness", 1, 1, 800_000), ("harness", 1, 2, 900_000)])
    noise = _log(tmp_path / "noise.log", [])       # 0 acts -> not counted in files
    for driver, want in [
            ("interactive", "acts=3 files=1 p50=200 p90=1500 p99=1500 max=1500 mean=600 over1s=33.3%"),
            ("harness", "acts=3 files=1 p50=800 p90=900 p99=900 max=900 mean=800 over1s=0.0%"),
            ("any", "acts=6 files=1 p50=800 p90=1500 p99=1500 max=1500 mean=700 over1s=16.7%")]:
        aws.main([log, noise, "--driver", driver])
        assert capsys.readouterr().out.splitlines()[0] == want


def test_json_keys_and_values(tmp_path, capsys):
    aws.main([_known(tmp_path), "--json"])
    obj = json.loads(capsys.readouterr().out)
    assert set(obj) == {"acts", "files", "p50_ms", "p90_ms", "p99_ms", "max_ms",
                        "mean_ms", "over1s_pct", "rounds"}
    assert [obj[k] for k in ("acts", "files", "p50_ms", "p90_ms", "p99_ms",
                             "max_ms", "mean_ms", "over1s_pct")] \
        == [10, 1, 600, 1000, 1000, 1000, 550, 0.0]
    assert obj["rounds"] == {"1": {"acts": 6, "p50_ms": 400, "p90_ms": 600},
                             "2": {"acts": 4, "p90_ms": 1000, "p50_ms": 900}}


def test_log_without_lines_exits_2_loudly(tmp_path, capsys):
    assert aws.main([_log(tmp_path / "empty.log", [])]) == 2
    err = capsys.readouterr()
    assert err.out == "" and err.err == "no [ACT_WALL] lines found\n"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
