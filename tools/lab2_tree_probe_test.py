#!/usr/bin/env python3
"""Tests for tools/lab2_tree_probe.py (pilot part 1) against a stub core, so no nml_core is needed.

The stub core answers every action with the truth record's own next state, rolls and stream
positions; a replay of the truth passes, and each RED control (VP +1 on the recorded next state,
one recorded die face changed) must FAIL the replay check. Run: python3 -m pytest -q tools/lab2_tree_probe_test.py
"""
import importlib.util
import json
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


def test_streams_come_from_the_position_eval_keys_and_are_shared_across_arms():
    pos = {"eval": [{"general": str(900_000_000_000_000_001 + r), "tray": str(r + 7)} for r in range(8)]}
    pairs = [lab.eval_streams(Nm, pos, r) for r in range(8)]
    assert [p[0].state for p in pairs] == [900_000_000_000_000_001 + r for r in range(8)]  # 63-bit seeds, no float
    assert lab.eval_streams(Nm, pos, 2)[0].state == lab.eval_streams(Nm, pos, 2)[0].state  # the same pair for every arm
    assert not hasattr(lab, "stream_pair") and not hasattr(lab, "STREAM_BASE")


def test_arm_headers_differ_only_in_tree_leaf_and_a_stray_knob_is_refused(monkeypatch):
    base = {"knobs": {"top_k": 10}}
    assert lab.arm_headers_differ_only_in_leaf(base, 5)
    monkeypatch.setitem(lab.ARM_KNOBS, "T", dict(lab.ARM_KNOBS["T"], tree_budget=64))
    assert not lab.arm_headers_differ_only_in_leaf(base, 5)


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


def _blocks(n=2, cell="c1", mission="duel"):
    return [{"block": "b%d" % i, "cell": cell, "mission": mission, "army1": "a", "army2": "b",
             "seeds": {"terrain": "1%d" % i, "layout": "2%d" % i, "deploy": "3%d" % i, "play_general": ["4%d" % i, "5%d" % i],
                       "tray": ["6%d" % i, "7%d" % i],
                       "search": {"d%dc%d" % (d, s): {arm: {o: "%d%d%d%d%d" % (pre, i, d, s, int(o)) for o in ("1", "2")}
                                                      for arm, pre in (("I", 7), ("L", 8), ("C", 9))}
                                  for d in (0, 1) for s in (1, 2)}}}
            for i in range(n)]


def test_manifest_has_four_games_per_arm_per_block_with_both_seats_and_two_dice():
    rows = lab.game_rows(_blocks())
    assert len(lab.game_rows(_blocks(1))) == 12 and len(rows) == 2 * 3 * 4 and len({r["row_id"] for r in rows}) == len(rows)
    assert len(lab.game_rows(_blocks(1), ("L", "C"))) == 8
    one = [r for r in rows if r["block"] == "b0" and r["arm"] == "L"]
    assert sorted((r["seeds"]["tray"], r["seat"]) for r in one) == [("60", 1), ("60", 2), ("70", 1), ("70", 2)]
    assert [r["seeds"]["search"] for r in one][0] == {"1": "80011", "2": "80012"} and all(r["mission"] == "duel" for r in rows)
    assert all(r["army1"] == "a" and r["army2"] == "b" for r in rows)  # armies stay on their physical seats


def test_every_game_takes_the_search_keys_registered_for_its_own_dice_and_seat():
    rows = lab.game_rows(_blocks(1))
    L = {(r["d"], r["seat"]): r["seeds"]["search"] for r in rows if r["arm"] == "L"}
    assert L == {(d, s): {"1": "80%d%d1" % (d, s), "2": "80%d%d2" % (d, s)} for d in (0, 1) for s in (1, 2)}
    assert len({json.dumps(v, sort_keys=True) for v in L.values()}) == 4      # four games, four streams
    assert all(r["seeds"]["search"] == {} for r in rows if r["arm"] == "I")   # I searches nothing
    gap = _blocks(1)
    del gap[0]["seeds"]["search"]["d1c2"]["L"]
    try:
        lab.game_rows(gap)
        raise AssertionError("a tree arm without its registered key must refuse the manifest")
    except SystemExit as e:
        assert "d1c2/L" in str(e)


def test_arm_kwargs_split_the_tree_from_the_one_ply_pool_deadline():
    L, C = lab.arm_kwargs({"arm": "L"}, 7), lab.arm_kwargs({"arm": "C"}, 7)
    assert L["deep_search_mode"] == "tree" and L["deep_deadline_us"] == 7 and "deep_tree_wall_ms" not in L
    assert C == {"deep_top_k": 32, "deep_horizon": 3, "deep_deadline_us": 7}


def test_board_scores_are_per_board_and_a_missing_or_short_board_fails():
    import pytest
    rows = lab.game_rows(_blocks(1))
    ys = {"L": [1.0, 1.0, 0.5, 0.5], "C": [0.5, 0.5, 0.0, 0.0], "I": [1.0, 0.0, 1.0, 0.0]}
    done = [(r, ys[r["arm"]].pop()) for r in rows]
    s = lab.board_scores(done)["c1"]["b0"]
    assert abs(s["B_LI"] - 0.25) < 1e-12 and abs(s["B_LC"] - 0.5) < 1e-12 and set(s) == {"B_LI", "B_LC"}  # I rows change nothing
    assert lab.i_seat1_means(done) == {"c1": {"b0": 0.5}}
    with pytest.raises(SystemExit):
        lab.board_scores([d for d in done if d[0]['arm'] != 'I'][:-1])


class StampNm:
    """A stand-in nml_core for the pilot's environment gate (no replay ever runs)."""
    BUILD_INFO = {"commit": "abc", "rules_epoch": 68, "dirty": False}
    __file__ = __file__
    nml_core = None   # the compiled submodule; a test that needs a wheel stamp plants one


def _wheel(tmp_path, monkeypatch, binary):
    """A wheel-shaped nml_core: the package shim plus a compiled submodule holding `binary`."""
    pkg = tmp_path / "nml_core"
    pkg.mkdir(exist_ok=True)
    (pkg / "__init__.py").write_text("from .nml_core import *\n")
    so = pkg / "nml_core.cpython-314-x86_64-linux-gnu.so"
    so.write_bytes(binary)
    monkeypatch.setattr(StampNm, "__file__", str(pkg / "__init__.py"))
    monkeypatch.setattr(StampNm, "nml_core", type("Ext", (), {"__file__": str(so)}))
    return so


def _pilot(monkeypatch, extra, build_info=None):
    monkeypatch.setitem(sys.modules, "nml_core", StampNm)
    monkeypatch.setattr(StampNm, "BUILD_INFO", build_info or StampNm.BUILD_INFO)
    return lab.main(["pilot", "--namespace", "t", *extra])


FULL = ["--expect-commit", "abc", "--expect-epoch", "68", "--expect-model-sha", "m", "--expect-wheel-sha", "w"]


def test_a_non_dry_pilot_without_every_expectation_stops_with_exit_2(monkeypatch, capsys):
    assert _pilot(monkeypatch, FULL[:6]) == 2          # no --expect-wheel-sha
    assert "missing" in capsys.readouterr().out
    assert _pilot(monkeypatch, []) == 2


def test_a_dirty_build_stops_the_pilot(monkeypatch, capsys):
    assert _pilot(monkeypatch, FULL, {"commit": "abc", "rules_epoch": 68, "dirty": True}) == 2
    assert "dirty" in capsys.readouterr().out


def test_the_strict_stamp_records_dirty_and_the_wheel_sha(tmp_path, monkeypatch):
    _wheel(tmp_path, monkeypatch, b"build one")
    stamp, bad = lab.env_stamp(StampNm, "", {"commit": "abc", "rules_epoch": 68, "model_sha256": None,
                                              "wheel_sha256": None}, strict=True)
    assert stamp["dirty"] is False and len(stamp["wheel_sha256"]) == 64
    assert bad == ["missing:model_sha256", "missing:wheel_sha256"]


def test_the_wheel_stamp_hashes_the_compiled_module_so_a_changed_binary_fails(tmp_path, monkeypatch):
    import hashlib
    so = _wheel(tmp_path, monkeypatch, b"build one")
    want = hashlib.sha256(b"build one").hexdigest()
    stamp, bad = lab.env_stamp(StampNm, "", {"wheel_sha256": want})
    assert stamp["wheel_sha256"] == want and bad == []
    so.write_bytes(b"build two")   # another binary behind the SAME __init__.py shim
    assert lab.env_stamp(StampNm, "", {"wheel_sha256": want})[1] == ["wheel_sha256"]
    monkeypatch.setattr(StampNm, "nml_core", None)   # only the shim left: no stamp, never the shim's sha
    assert lab.env_stamp(StampNm, "", {"wheel_sha256": want}) == ({**stamp, "wheel_sha256": None}, ["wheel_sha256"])


class SpySp:
    """A stand-in selfplay: records every play_game call; `quiet` leaves the net hooks uncalled; `boom` declines."""
    def __init__(self, net, quiet=False, boom=None):
        self.calls, self.net, self.quiet, self.boom = [], net, quiet, boom

    def _pick_for(self, *a, **k):
        return {}

    @__import__("contextlib").contextmanager
    def forced_picks(self, fn):
        yield

    def play_game(self, *args, **kw):
        self.calls.append((args, kw))
        if self.boom:
            raise self.boom
        if not self.quiet:
            for side in (1, 2):
                kw["leaf_value_fn"][side]([], side)
        return {"winner": "p1", "knobs": {"top_k": 2}, "planner_positions": []}


class CountNet:
    model_sha256 = "cd" * 32

    def __init__(self):
        self.counts = {1: {"calls": 0, "leaves": 0}, 2: {"calls": 0, "leaves": 0}}

    def hook(self, side):
        def fn(leaves, _side=None):
            self.counts[side]["calls"] += 1
            self.counts[side]["leaves"] += len(leaves)
            return []
        return fn


class Declining(Exception):
    pass


NmStub = type("NmStub", (), {"Unsupported": Declining})
CTX = {"prereg": "p" * 64, "build": {"commit": "abc", "dirty": False, "rules_epoch": 68, "wheel_sha256": "w"}}
PRINCIPLES_ROW = ("schema prereg_sha256 row_id split part cell source arm opponent seat replicate seeds build model_sha256 "
                  "header_sha256 net decisions y winner valid reason wall_s rss_hwm_mib done").split()


def test_a_cell_7_row_plays_breakthrough_with_the_split_seeds_and_the_live_ledger():
    row = lab.game_rows(_blocks(1, "c7", "breakthrough"), ("L",))[0]
    net = CountNet()
    sp = SpySp(net)
    rec = lab.play_row(NmStub, sp, row, "repo", "bank", {"top_k": 3}, net, 5, CTX)
    (args, kw), = sp.calls
    assert kw["mission"] == "breakthrough" and kw["objectives"] == "mission" and kw["live_ledger"] is True
    assert args[0] == 10 and (kw["layout_seed"], kw["deploy_seed"], kw["play_seed"], kw["dice_seed"]) == (20, 30, 40, 60)
    assert kw["search_seeds"] == {1: 80011, 2: 80012} and kw["deep_player"] == 1 and kw["leaf_value_w"] == 1.0
    assert kw["deep_deadline_us"] == 5 and rec["valid"] and rec["net"]["1"] == {"calls": 1, "leaves": 0}
    assert list(rec) == PRINCIPLES_ROW and rec["seeds"]["search_general"] == "80011" and rec["rss_hwm_mib"] > 0


def test_an_i_row_has_no_deep_core_and_a_never_called_hook_is_invalid():
    row = lab.game_rows(_blocks(1), ("I",))[0]
    sp = SpySp(CountNet(), quiet=True)
    rec = lab.play_row(NmStub, sp, row, "repo", "bank", {}, sp.net, 5, CTX)
    assert "deep_player" not in sp.calls[0][1] and "search_seeds" not in sp.calls[0][1]
    assert rec["valid"] is False and rec["reason"] == "net_inactive" and "search_general" not in rec["seeds"]


def test_a_declined_game_is_an_invalid_row_and_the_next_row_runs():
    rows = lab.game_rows(_blocks(1), ("L",))[:2]
    net = CountNet()
    bad = lab.play_row(NmStub, SpySp(net, boom=Declining("unported: x")), rows[0], "r", "b", {}, net, 5, CTX)
    good = lab.play_row(NmStub, SpySp(net), rows[1], "r", "b", {}, net, 5, CTX)
    assert bad["valid"] is False and bad["reason"] == "unsupported: unported: x" and bad["y"] is None and list(bad) == PRINCIPLES_ROW
    assert good["valid"] is True and good["y"] == 0.5 * 0 + (1.0 if rows[1]["seat"] == 1 else 0.0)


class TimingCore:
    """A stub core: records the live header knobs and every planner call's kwargs."""
    def __init__(self):
        self.knobs, self.calls = {}, []

    def set_header(self, header):
        self.knobs = dict(header["knobs"])

    def state_of(self, plain):
        return plain

    def plan_with_rollout(self, state, player, statics, **kw):
        self.calls.append((dict(self.knobs), kw))
        return {"trace": {"tree": {"completed": 1, "deadline_hit": False}}}


def _timing_run(monkeypatch, tmp_path, B_us=None):
    import types
    core, hooked = TimingCore(), []
    net = types.SimpleNamespace(model_sha256="ab" * 32, hook=lambda side: (lambda leaves, _s=None: hooked.append(side) or []))
    monkeypatch.setitem(sys.modules, "nml_core", types.SimpleNamespace(load=lambda repo: core))
    monkeypatch.setitem(sys.modules, "lab2_net", types.SimpleNamespace(ShippedNet=lambda repo: net))
    if B_us is not None:
        monkeypatch.setattr(lab, "allowance_us", lambda times: B_us)
    states = [{"cell": "c1", "state": {"i": i}, "player": 1 + i % 2} for i in range(2)]
    (tmp_path / "s.json").write_text(json.dumps(states))
    (tmp_path / "h.json").write_text(json.dumps({"knobs": {"top_k": 10}}))
    out = str(tmp_path / "t.txt")
    rc = lab.main(["timing", "--states", str(tmp_path / "s.json"), "--header", str(tmp_path / "h.json"), "--statics", "{}",
                   "--per-cell", "2", "--hardware", "laptop-x", "--out", out])
    return rc, core, out


def test_timing_prices_every_call_with_the_net_and_passes_the_allowance_as_deadline_us(monkeypatch, tmp_path):
    rc, core, out = _timing_run(monkeypatch, tmp_path, B_us=900)
    assert rc == 0 and core.calls
    assert all(kw["leaf_value_w"] == 1.0 and callable(kw["leaf_value_fn"]) for _, kw in core.calls)  # incumbent calls too
    tree = [k for k, _ in core.calls if k.get("search_mode") == "tree"]
    assert tree and all(k["deadline_us"] == 900 and "tree_wall_ms" not in k for k in tree)  # 900 us stays 900 (not 0 ms = OFF)
    assert any("search_mode" not in k for k, _ in core.calls)


def test_timing_stamps_hardware_and_labels_the_sweep(monkeypatch, tmp_path):
    rc, core, out = _timing_run(monkeypatch, tmp_path)
    meta = json.load(open(out + ".json"))["_meta"]
    assert meta["hardware"] == "laptop-x" and meta["model_sha256"] == "ab" * 32 and "diagnostic" in meta["sweep"]
    text = open(out).read()
    assert "hardware: laptop-x" in text and "D-ONLY DIAGNOSTIC" in text
