#!/usr/bin/env python3
"""Fixture tests for tools/assert_ship_probe.py, the pass/fail reader of the macOS ship proof.

The GOOD log is the shape a real exported build printed on 26.09.2026 (Linux export, same probe
scene); every RED case flips exactly one thing, so a green run proves the reader can fail.
Run:  python3 -m pytest -q tools/assert_ship_probe_test.py
"""

import importlib.util
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "assert_ship_probe", os.path.join(_HERE, "assert_ship_probe.py"))
asp = importlib.util.module_from_spec(_SPEC)
sys.modules["assert_ship_probe"] = asp
_SPEC.loader.exec_module(asp)

SHA = "bb5568f646d97295b9f460254305ef6d18a9e830924a984b237651116b1e5e36"
REPORT = {"arch": "arm64", "brain_sha": SHA, "class_present": True, "core_calls": 1,
          "core_enabled": True, "declines": "{  }", "ok": True, "os": "macOS",
          "picked": True, "planner": True}


def _log(report=None, opponent="opponent: erlkoenig brain=onnx bb5568f6 top_k=10 horizon=3 move=core",
         noise=""):
    rep = dict(REPORT if report is None else report)
    return "\n".join([
        "Initialize godot-rust (API v4.6.stable.official, runtime v4.6.stable.official)",
        "WARNING: ObjectDB instances leaked at exit (run with --verbose for details).",
        noise, opponent, "NML_SHIP_PROBE " + json.dumps(rep), ""])


def _check(text, os_name="macOS", arch="arm64", code=0):
    return asp.check(text, os_name, arch, code)


def test_a_complete_erlkoenig_run_passes():
    assert _check(_log()) == []


def test_missing_marker_fails():
    assert any("no NML_SHIP_PROBE" in p for p in _check("opponent: erlkoenig brain=onnx\n"))


def test_a_false_leg_fails():
    for key in ("class_present", "core_enabled", "planner", "picked", "ok"):
        assert _check(_log({**REPORT, key: False})), key


def test_zero_core_calls_or_empty_sha_fails():
    assert any("core_calls" in p for p in _check(_log({**REPORT, "core_calls": 0})))
    assert any("brain_sha" in p for p in _check(_log({**REPORT, "brain_sha": ""})))


def test_wrong_architecture_or_os_fails():
    assert any("slice" in p for p in _check(_log(), arch="x86_64"))
    assert any("os" in p for p in _check(_log(), os_name="Linux"))


def test_the_tree_fallback_line_fails():
    text = _log(opponent="opponent: tree — core off, brain none, move=gdscript")
    problems = _check(text)
    assert any("no `opponent: erlkoenig`" in p for p in problems)
    assert any("opponent: tree" in p for p in problems)


def test_fatal_markers_fail():
    for noise in ("ERROR: GDExtension dynamic library not found: 'res://core/nml_core.gdextension'.",
                  "SCRIPT ERROR: Parse Error: Identifier not declared", "Parse Error: x"):
        assert any("fatal marker" in p for p in _check(_log(noise=noise))), noise


def test_a_nonzero_exit_code_fails():
    assert any("exited with code 142" in p for p in _check(_log(), code=142))


def test_main_returns_the_verdict_through_the_exit_code(tmp_path):
    good = tmp_path / "good.log"
    good.write_text(_log(), encoding="utf-8")
    bad = tmp_path / "bad.log"
    bad.write_text(_log({**REPORT, "core_calls": 0}), encoding="utf-8")
    assert asp.main([str(good), "--os", "macOS", "--arch", "arm64", "--exit-code", "0"]) == 0
    assert asp.main([str(bad), "--os", "macOS", "--arch", "arm64"]) == 1
