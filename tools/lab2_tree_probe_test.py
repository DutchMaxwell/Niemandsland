#!/usr/bin/env python3
"""Tests for tools/lab2_tree_probe.py (pilot part 1) against a stub core, so no nml_core is needed.

The stub core answers every action with the truth record's own next state, rolls and stream
positions; a replay of the truth passes, and each RED control (VP +1 on the recorded next state,
one recorded die face changed) must FAIL the replay check. Run: python3 -m pytest -q tools/lab2_tree_probe_test.py
"""
import importlib.util
import os
import subprocess
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("lab2_tree_probe", os.path.join(_HERE, "lab2_tree_probe.py"))
lab = importlib.util.module_from_spec(_SPEC)
sys.modules["lab2_tree_probe"] = lab
_SPEC.loader.exec_module(lab)

TRUTH = {"before": {"vp": [0, 0], "u": 1}, "action": {"kind": 1}, "rng_state": 7, "tray_state": 0,
         "faces_before": 0, "after": {"vp": [2, 1], "u": 2}, "rolls": [{"faces": [3, 4]}],
         "tray_state_after": 2, "rng_state_after": 9, "dice_seed": 5}


class St:
    def __init__(self, d):
        self.d = d

    def plain(self):
        return self.d


class Core:
    def state_of(self, plain):
        return St(plain)

    def resolve_with_tray(self, st, action, rng, tray):
        tray.state, rng.state = TRUTH["tray_state_after"], TRUTH["rng_state_after"]
        return St(TRUTH["after"]), {"rolls": TRUTH["rolls"]}


class Nm:
    BUILD_INFO = {"commit": "abc", "rules_epoch": 68}

    class Rng:
        def __init__(self, seed):
            self.state = seed

    class Tray:
        def __init__(self, seed):
            self.state = 0

        def roll(self, n):
            self.state += n


def test_the_truth_replays_clean():
    r = lab.replay_transition(Nm, Core(), TRUTH)
    assert r["ok"], r["checks"]


def test_red_vp_and_red_die_fail_the_check():
    assert not lab.replay_transition(Nm, Core(), lab.red_vp(TRUTH))["checks"]["state"]
    assert not lab.replay_transition(Nm, Core(), lab.red_die(TRUTH))["checks"]["rolls"]
    assert TRUTH["after"]["vp"] == [2, 1] and TRUTH["rolls"][0]["faces"] == [3, 4]  # the originals are untouched


def test_an_environment_mismatch_is_reported():
    _, bad = lab.env_stamp(Nm, "", {"commit": "zzz", "rules_epoch": 68, "model_sha256": None})
    assert bad == ["commit"]


def test_dry_run_prints_the_plan_and_exits_0():
    out = subprocess.run([sys.executable, os.path.join(_HERE, "lab2_tree_probe.py"), "pilot",
                          "--namespace", "t", "--dry-run", "--workers", "4", "--wall-hours", "6",
                          "--rss-gib", "6"], capture_output=True, text=True, timeout=60)
    assert out.returncode == 0 and "dry-run plan" in out.stdout and "RED-VP" in out.stdout, out.stdout + out.stderr
