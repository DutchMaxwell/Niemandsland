#!/usr/bin/env python3
"""Fixture tests for tools/act_wall_summary.py, the [ACT_WALL] (NML_ACT_WALL=1) summariser.

Ten known decisions 100,000..1,000,000 us = 100..1000 ms after floor(us/1000): nearest rank
values[min(len-1, int(p*len))] gives p50 = values[5] = 600, p90 = p99 = max = 1000, mean 550,
over1s 0.0 % — exactly 1,000,000 us is one second, not OVER one second.
The --phases fixture is ten activations whose [ACT_PHASE] lines put move at 90 % of the
two slowest and 10 % of the eight fast ones; both blocks are pinned line by line.
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


# Phase fixture: move = 90 % of the two slowest activations, 10 % of the eight fast ones.
FAST = {"select": 45_000, "act": 54_700, "book": 200, "other": 100, "move": 10_000}
SLOW1 = {"select": 45_000, "act": 954_700, "book": 200, "other": 100, "move": 900_000}
SLOW2 = {"select": 45_000, "act": 1_154_700, "book": 200, "other": 100, "move": 1_080_000}
PHASE_ROWS = [(1, 1 + i % 2, 100_000, FAST) for i in range(8)]
PHASE_ROWS += [(2, 1, 1_000_000, SLOW1), (2, 2, 1_200_000, SLOW2)]

WALL_OUT = [
    "acts=10 files=1 p50=100 p90=1200 p99=1200 max=1200 mean=300 over1s=10.0%",
    "r1: acts=8 p50=100 p90=100", "r2: acts=2 p50=1200 p90=1200"]

PHASES_OUT = [
    "phases all (acts=10):",
    "act: sum_ms=2547 share=84.9% median_ms=54",
    "move: sum_ms=2060 share=68.7% median_ms=10",
    "select: sum_ms=450 share=15.0% median_ms=45",
    "book: sum_ms=2 share=0.1% median_ms=0",
    "other: sum_ms=1 share=0.0% median_ms=0",
    "phases slowest10 (acts=1):",
    "act: sum_ms=1154 share=96.2% median_ms=1154",
    "move: sum_ms=1080 share=90.0% median_ms=1080",
    "select: sum_ms=45 share=3.8% median_ms=45",
    "book: sum_ms=0 share=0.0% median_ms=0",
    "other: sum_ms=0 share=0.0% median_ms=0"]


def _phase_log(path, rows=None, phases=True):
    """rows: (round, seat, total_us, {phase: us}) -> [ACT_WALL] + optional [ACT_PHASE]."""
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("Godot Engine v4.6.stable\n[Graphics] window on screen 0 of 0\n")
        for r, p, total, d in (PHASE_ROWS if rows is None else rows):
            if phases:
                pairs = " ".join(f"{k}={v}" for k, v in reversed(list(d.items())))
                fh.write(f"[ACT_PHASE] r{r} p{p} total_us={total} {pairs}\n")
            fh.write(f"[ACT_WALL] harness r{r} p{p} us={total}\n")
    return str(path)


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


def test_phase_blocks_for_all_and_slowest10(tmp_path, capsys):
    assert aws.main([_phase_log(tmp_path / "ph.log"), "--phases"]) == 0
    assert capsys.readouterr().out.splitlines() == WALL_OUT + PHASES_OUT


def test_phase_json_blocks(tmp_path, capsys):
    aws.main([_phase_log(tmp_path / "ph.log"), "--phases", "--json"])
    phases = json.loads(capsys.readouterr().out)["phases"]
    assert set(phases) == {"all", "slowest10"}
    assert phases["all"]["acts"] == 10 and phases["slowest10"]["acts"] == 1
    assert set(phases["all"]) - {"acts"} == {"act", "move", "select", "book", "other"}
    assert phases["all"]["move"] == {"sum_ms": 2060, "share_pct": 68.7, "median_ms": 10}
    assert phases["slowest10"]["select"] == {"sum_ms": 45, "share_pct": 3.8, "median_ms": 45}


def test_default_output_is_byte_identical_next_to_phase_lines(tmp_path, capsys):
    aws.main([_phase_log(tmp_path / "with.log")])
    with_phases = capsys.readouterr().out
    aws.main([_phase_log(tmp_path / "without.log", phases=False)])
    assert with_phases == capsys.readouterr().out
    assert with_phases.splitlines() == WALL_OUT


def test_phases_flag_without_phase_lines(tmp_path, capsys):
    assert aws.main([_phase_log(tmp_path / "w.log", phases=False), "--phases"]) == 0
    err = capsys.readouterr()
    assert err.out.splitlines() == WALL_OUT
    assert err.err == "no [ACT_PHASE] lines found\n"
    aws.main([_phase_log(tmp_path / "w.log", phases=False), "--phases", "--json"])
    out = capsys.readouterr()
    assert "phases" not in json.loads(out.out)
    assert out.err == "no [ACT_PHASE] lines found\n"


def test_phases_flag_without_any_line_exits_2_loudly(tmp_path, capsys):
    assert aws.main([_log(tmp_path / "none.log", []), "--phases"]) == 2
    err = capsys.readouterr()
    assert err.out == ""
    assert err.err == "no [ACT_WALL] lines found\nno [ACT_PHASE] lines found\n"


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-v"]))
