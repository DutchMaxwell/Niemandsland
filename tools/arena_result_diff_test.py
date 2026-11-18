#!/usr/bin/env python3
"""Fixture tests for tools/arena_result_diff.py.

Retargeting the arena harness (PLAN G steps 8/9) must not move a single number,
which is only provable if the diff tool itself can fail. These tests pin the
four answers the step names: equal -> 0, one value changed -> 1, a `profile`
change with --ignore -> 0, empty -> 2. Unpaired files are the same refusal as an
empty run: a comparison that silently covers fewer games is not a comparison.

Run:  python3 -m pytest tools/arena_result_diff_test.py
"""

import importlib.util
import json
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "arena_result_diff", os.path.join(_HERE, "arena_result_diff.py")
)
ard = importlib.util.module_from_spec(_SPEC)
sys.modules["arena_result_diff"] = ard
_SPEC.loader.exec_module(ard)


def _game(seed=7, winner="p1"):
    return {"seed": seed, "dice_seed": seed * 11, "winner": winner,
            "p1": {"vp": 12, "objectives": 2}, "p2": {"vp": 9, "objectives": 1},
            "board": [[0, 0, 0, 1.5], [2, 0, 0, 0]],
            "profile": {"plan": 1000, "resolve": 2000}}


def _write(dir_path, name, record):
    os.makedirs(dir_path, exist_ok=True)
    with open(os.path.join(dir_path, name), "w", encoding="utf-8") as fh:
        json.dump(record, fh)


def _run(a, b, *extra):
    return ard.main([str(a), str(b)] + list(extra))


def test_equal_dirs_exit_0(tmp_path):
    for d in ("a", "b"):
        _write(tmp_path / d, "arena_x_vs_y_s7_d11.json", _game())
    assert _run(tmp_path / "a", tmp_path / "b") == 0


def test_one_value_changed_exit_1_and_path_printed(tmp_path, capsys):
    _write(tmp_path / "a", "arena_x_vs_y_s7_d11.json", _game())
    other = _game()
    other["p1"]["vp"] = 13
    _write(tmp_path / "b", "arena_x_vs_y_s7_d11.json", other)
    assert _run(tmp_path / "a", tmp_path / "b") == 1
    out = capsys.readouterr().out
    assert "p1.vp" in out


def test_ignore_profile_exit_0(tmp_path):
    _write(tmp_path / "a", "arena_x_vs_y_s7_d11.json", _game())
    other = _game()
    other["profile"]["plan"] = 9999
    _write(tmp_path / "b", "arena_x_vs_y_s7_d11.json", other)
    assert _run(tmp_path / "a", tmp_path / "b", "--ignore", "profile") == 0
    assert _run(tmp_path / "a", tmp_path / "b") == 1


def test_empty_dirs_exit_2(tmp_path):
    os.makedirs(tmp_path / "a")
    os.makedirs(tmp_path / "b")
    assert _run(tmp_path / "a", tmp_path / "b") == 2


def test_unpaired_file_exit_2(tmp_path):
    _write(tmp_path / "a", "arena_x_vs_y_s7_d11.json", _game())
    _write(tmp_path / "a", "arena_x_vs_y_s11_d11.json", _game(seed=11))
    _write(tmp_path / "b", "arena_x_vs_y_s7_d11.json", _game())
    assert _run(tmp_path / "a", tmp_path / "b") == 2


def test_first_20_paths_cap(tmp_path, capsys):
    _write(tmp_path / "a", "arena_x_vs_y_s7_d11.json", _game())
    other = _game()
    other["board"] = [[i, 0, 0, 1.5] for i in range(30)]
    _write(tmp_path / "b", "arena_x_vs_y_s7_d11.json", other)
    assert _run(tmp_path / "a", tmp_path / "b") == 1
    lines = [ln for ln in capsys.readouterr().out.splitlines() if "board[" in ln]
    assert len(lines) == 20
