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


def test_allowance_is_4x_median_capped_floored_and_at_least_1us():
    assert lab.allowance_us([1.0, 2.0, 3.0]) == 8000          # 4 x 2 ms = 8000 us
    assert lab.allowance_us([900.0]) == 1_000_000             # capped at 1000 ms
    assert lab.allowance_us([0.0000001]) == 1                 # never below 1 us
    assert lab.allowance_us([1.00000049]) == 4000             # rounded DOWN


def test_a_short_timing_cell_fails_the_instrument():
    import pytest
    ok = [{"cell": "c1", "i": i} for i in range(12)] + [{"cell": "c2", "i": i} for i in range(12)]
    assert {c: len(v) for c, v in lab.pick_states(ok).items()} == {"c1": 12, "c2": 12}
    with pytest.raises(SystemExit):
        lab.pick_states(ok[:-1])


def test_measure_takes_one_warmup_and_three_timed_calls():
    n = []
    t = lab.measure(lambda: n.append(1))
    assert len(n) == 4 and len(t) == 3


def test_projected_mde_matches_the_prereg_formula_and_the_chi2_constant():
    # chi2 quantile(0.10, df=12) = 6.3038 (table value); F = 12 / 6.3038.
    assert abs(lab.CHI2_Q10_DF12 - 6.3038) < 1e-4
    v = 12 * (1 / 12) ** 2 * 0.25 / 40  # 12 cells of s2 = 0.25, n_c = 40
    want = 100 * (2.5758293 + 0.8416212) * (12 / 6.3038 * v) ** 0.5
    assert abs(lab.projected_mde({"c%d" % i: 0.25 for i in range(12)}, 40) - want) < 1e-3
    assert lab.projected_mde({"c": 0.0}, 40) == 0.0  # zero variance is reported, not hidden


def test_streams_are_shared_across_arms_and_distinct_across_positions_and_replicates():
    seeds = {(p, r): lab.stream_pair(Nm, p, r)[0].state for p in range(3) for r in range(8)}
    assert len(set(seeds.values())) == 24 and seeds[(0, 0)] == 740_000_000
    assert lab.stream_pair(Nm, 1, 2)[0].state == lab.stream_pair(Nm, 1, 2)[0].state  # the same pair for every arm


def test_position_gains_are_mean_stream_differences():
    y = {"I": [0.0, 0.5, 1.0, 0.0] * 2, "L": [1.0] * 8, "T": [0.5] * 8}
    g = lab.position_gains(y)
    assert abs(g["A_L"] - 0.625) < 1e-12 and abs(g["A_T"] - 0.125) < 1e-12 and abs(g["A_TL"] + 0.5) < 1e-12


def test_bootstrap_known_winner_identical_arms_and_four_games_are_not_four_blocks():
    np = __import__("pytest").importorskip("numpy")
    cells = ["c%d" % i for i in range(12)]
    mk = lambda v: {c: {"g%d" % j: {"A_T": v, "A_L": v, "A_TL": 0.0} for j in range(5)} for c in cells}
    win = lab.bootstrap_intervals(mk(0.2), resamples=300, seed=1)
    assert abs(win["A_T"]["point"] - 20.0) < 1e-9 and win["A_T"]["lo"] > 0       # a known winning arm
    zero = lab.bootstrap_intervals(mk(0.0), resamples=300, seed=1)
    assert all(v["point"] == 0 and v["lo"] == 0 and v["hi"] == 0 for v in zero.values())  # identical arms: all gains zero
    # two boards (gains 0 and 0.4) in every cell; counting each board's four correlated games as four
    # independent clusters narrows the interval, and the scorer must be the WIDER one (clusters = boards)
    boards = lambda reps: {c: {"b%d_%d" % (b, j): {"A_T": 0.4 * b, "A_L": 0.0, "A_TL": 0.0} for b in (0, 1) for j in range(reps)} for c in cells}
    w_boards = lab.bootstrap_intervals(boards(1), resamples=300, seed=1)["A_T"]
    w_games = lab.bootstrap_intervals(boards(4), resamples=300, seed=1)["A_T"]
    assert w_boards["hi"] - w_boards["lo"] > w_games["hi"] - w_games["lo"]
