#!/usr/bin/env python3
"""Fixture-based tests for the off-board detector (d9) in tools/tactic_audit.py.

d9 is the measurement seam for issue #215 (the movement planner routing models off a
rectangular table). Its whole value in an A/B run rests on two things being pinned:

  1. the LINE FORMAT emitted by tools/offboard_audit.gd (GDScript, harness side), and
  2. the PARSER here (Python, analysis side).

They live in different languages and can drift silently, so the contract test below feeds
the byte-exact string the GDScript formatter produces. If someone edits the format on one
side only, that test goes red instead of the detector quietly reporting 0 forever.

Run:  python3 -m pytest tools/test_tactic_audit.py
"""

import importlib.util
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location(
    "tactic_audit", os.path.join(_HERE, "tactic_audit.py")
)
ta = importlib.util.module_from_spec(_SPEC)
sys.modules["tactic_audit"] = ta
_SPEC.loader.exec_module(ta)


# The byte-exact output of OffboardAudit.line() in tools/offboard_audit.gd:
#   "AUDIT off-board: %s — %d model(s), max overhang %.2f\" (%s)"
# Mirrored here on purpose — this literal IS the cross-language contract.
GD_LINE = 'AUDIT off-board: Orc Grunts — 2 model(s), max overhang 3.40" (after activation)'


def write_cap(tmp_path, battlelog):
    (tmp_path / "battlelog.txt").write_text(battlelog)
    return str(tmp_path)


def test_clean_log_scores_zero(tmp_path):
    """A legal board state must score a hard zero — the detector's baseline."""
    cap = write_cap(tmp_path, "R1 Orc Grunts advances\nR1 Orc Grunts: no shot — out of range\n")
    r = ta.audit(cap)
    assert r["d9_offboard_events"] == 0
    assert r["d9_offboard_models"] == 0
    assert r["d9_max_overhang_in"] == 0.0


def test_gdscript_line_is_parsed(tmp_path):
    """The exact harness line must be counted — the cross-language format contract."""
    cap = write_cap(tmp_path, "R1 something happened\n%s\nR1 more\n" % GD_LINE)
    r = ta.audit(cap)
    assert r["d9_offboard_events"] == 1
    assert r["d9_offboard_models"] == 2
    assert r["d9_max_overhang_in"] == pytest.approx(3.40)


def test_counts_models_and_keeps_worst_overhang(tmp_path):
    """Several offending units in one game: events count lines, models sum, overhang takes the max."""
    log = "\n".join([
        'AUDIT off-board: Orc Grunts — 2 model(s), max overhang 3.40" (after activation)',
        'AUDIT off-board: Wolf Riders — 1 model(s), max overhang 11.75" (after move)',
        'AUDIT off-board: Boar Boyz — 4 model(s), max overhang 0.90" (after activation)',
    ])
    r = ta.audit(write_cap(tmp_path, log))
    assert r["d9_offboard_events"] == 3
    assert r["d9_offboard_models"] == 7
    assert r["d9_max_overhang_in"] == pytest.approx(11.75)


def test_similar_lines_do_not_false_positive(tmp_path):
    """Prose about the table edge must NOT count — only the pinned machine line does."""
    log = "\n".join([
        "R2 Orc Grunts moves toward the table edge",
        "AI path clamped to the table edge (Orc Grunts)",
        "off-board: 3 models",
    ])
    r = ta.audit(write_cap(tmp_path, log))
    assert r["d9_offboard_events"] == 0


def test_existing_detectors_still_read_the_same_log(tmp_path):
    """d9 is additive: a log carrying both signals must still score D7 unchanged."""
    log = "\n".join([
        "R1 Orc Grunts: no shot — no line of sight to the target",
        GD_LINE,
    ])
    r = ta.audit(write_cap(tmp_path, log))
    assert r["d7_no_shot"] == 1
    assert r["d7_no_shot_los"] == 1
    assert r["d9_offboard_events"] == 1
