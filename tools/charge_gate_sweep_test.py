#!/usr/bin/env python3
"""Contract tests for the issue #183 arena sweep metrics."""

import importlib.util
import json
from pathlib import Path
import sys


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("charge_gate_sweep", HERE / "charge_gate_sweep.py")
charge_gate_sweep = importlib.util.module_from_spec(SPEC)
sys.modules["charge_gate_sweep"] = charge_gate_sweep
SPEC.loader.exec_module(charge_gate_sweep)


def test_capture_metrics_counts_only_applied_charge_actions_and_shortfalls(tmp_path):
    decisions = [
        {"kind": "action", "chosen": "charges"},
        {"kind": "action", "chosen": "rushes"},
        {"kind": "planner", "chosen": "charges"},
        {"kind": "action", "chosen": "charges"},
    ]
    (tmp_path / "decisions.json").write_text(json.dumps(decisions), encoding="utf-8")
    (tmp_path / "battlelog.txt").write_text(
        "R1 A charges B\nR1 A's charge falls short (0.7\")\nR2 C charges D\n",
        encoding="utf-8",
    )
    assert charge_gate_sweep.capture_metrics(tmp_path) == (2, 1, 1)


def test_aggregate_reports_paired_outcomes_and_charge_totals():
    rows = [
        {"winner": "p1", "charges_declared": 2, "charges_ended_short": 1, "wasted_activations": 1},
        {"winner": "p2", "charges_declared": 3, "charges_ended_short": 0, "wasted_activations": 0},
        {"winner": "draw", "charges_declared": 1, "charges_ended_short": 0, "wasted_activations": 0},
    ]
    assert charge_gate_sweep.aggregate(rows) == {
        "games": 3,
        "charges_declared": 6,
        "charges_ended_short": 1,
        "wasted_activations": 1,
        "outcomes": {"p1": 1, "draw": 1, "p2": 1},
    }
