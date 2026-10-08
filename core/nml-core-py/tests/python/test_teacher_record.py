"""Teacher-data recorder (loop prep, 07.10.2026) — `core/nml-core-py/tools/teacher_record.py` on top of the stage-0
probe path (`tools/lab2_tree_probe.play_row`). The proofs:

  * KWARGS IDENTITY: at the stage-0 settings (wall allowance, budget 0, pair 10/3) the recorder builds EXACTLY the
    probe's own arm kwargs for L, L_tray and C — the stage-0 runner's moves are the recorder's moves;
  * PICK IDENTITY: one row played plain (the probe's call) and recorded (`record_cands` + the token capture) gives
    the same action digest — recording moves no pick;
  * ROWS: one token row per landed decision (= the row's timed decisions); the tree seat's rows carry `pi` summing
    to 1 with mass on the played label, the opponent's rows carry `tree_fired` 0 and `pi` 0; `outcome` follows the
    winner from each actor's view;
  * RESUMABLE + DETERMINISTIC: a second run replays nothing; the same seeds in two dirs give equal arrays;
  * STAMP LAW: `play_game(record_cands=True)` rows carry `cands.tree` ONLY where the tree fired.

Skipped without the private fixtures (terrain bank + 1000-pt lists) or onnxruntime (the shipped net at the leaves).
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path

import numpy as np
import pytest

pytest.importorskip("onnxruntime")
import nml_core  # noqa: E402,F401

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(REPO / "tools"))
import lab2_tree_probe as lab  # noqa: E402
import selfplay as sp  # noqa: E402
import teacher_record as tr  # noqa: E402

BANK = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1, ARMY2 = LISTS / "robot_legions_1000.json", LISTS / "blessed_sisters_1000.json"
needs_lists = pytest.mark.skipif(not (BANK.is_dir() and ARMY1.exists() and ARMY2.exists()),
                                 reason="private fixtures (terrain bank + lists) not on this box")
FAST = {"top_k": 2, "horizon": 1}


def cfg(out, **over):
    c = {"repo": str(REPO), "bank": str(BANK), "out": str(out), "knobs": FAST, "budget": 4, "pair": (2, 1),
         "allowance": 0, "prereg": "test"}
    c.update(over)
    return c


def block(terrain="27", army1="a", army2="b"):
    """One stage-0-shaped block (the `lab2_tree_probe.game_rows` manifest) with search keys for L, L_tray and T."""
    return {"block": "B", "cell": "c1", "mission": "duel", "army1": army1, "army2": army2,
            "seeds": {"terrain": terrain, "layout": "91002", "deploy": "91003", "play_general": ["91004", "91005"],
                      "tray": ["91006", "91007"],
                      "search": {"d%dc%d" % (d, c): {a: {"1": str(91100 + 10 * d + c), "2": str(91200 + 10 * d + c)}
                                                    for a in ("L", "L_tray", "T")} for d in (0, 1) for c in (1, 2)}}}


def fixture_rows(arm="L"):
    return lab.game_rows([block("27", str(ARMY1), str(ARMY2))], (arm,))


def action_digest(res):
    return hashlib.sha256(json.dumps([[x["side"], x["unit"], x["action"]] for x in res["planner_positions"]]
                                     + [res["winner"], res["vp"]], sort_keys=True).encode()).hexdigest()


def test_stage0_settings_build_the_probes_own_arm_kwargs():
    stage0 = cfg("/nonexistent", budget=0, pair=(10, 3), allowance=900_000)
    for arm in ("L", "L_tray", "C"):
        row = lab.game_rows([block()], (arm,))[0]
        assert tr.arm_kwargs(row, stage0) == lab._PROBE_ARM_KWARGS(row, 900_000), arm
    t = tr.arm_kwargs(lab.game_rows([block()], ("T",))[0], stage0)
    assert t.pop("deep_tree_leaf") == "terminal" and t == lab._PROBE_ARM_KWARGS(lab.game_rows([block()], ("L",))[0], 900_000)
    # budget-bound (no clock): the clock rule is dropped and the leaf budget rides
    kw = tr.arm_kwargs(lab.game_rows([block()], ("L",))[0], cfg("/nonexistent"))
    assert kw["deep_tree_budget"] == 4 and "deep_deadline_after_preselect" not in kw and kw["deep_deadline_us"] == 0


@needs_lists
def test_recording_moves_no_pick(tmp_path):
    row = [r for r in fixture_rows() if r["seat"] == 1 and r["d"] == 0][0]
    w, got, real = tr._init(cfg(tmp_path)), [], sp.play_game

    def spy(*args, **kwargs):
        got.append(real(*args, **kwargs))
        return got[-1]
    sp.play_game = spy
    try:
        plain, _ = tr.play(w, row, record=False)
        recorded, rows = tr.play(w, row, record=True)
    finally:
        sp.play_game = real
    assert plain["valid"] and recorded["valid"], (plain["reason"], recorded["reason"])
    assert action_digest(got[0]) == action_digest(got[1])
    assert len(rows) == len(got[1]["planner_positions"]) == len(recorded["decisions"]) > 0
    assert all("cands" not in p for p in got[0]["planner_positions"])


@needs_lists
def test_rows_resume_and_determinism(tmp_path):
    row = [r for r in fixture_rows() if r["seat"] == 2 and r["d"] == 1][0]
    for d in ("a", "b"):
        w = tr._init(cfg(tmp_path / d))
        os.makedirs(w["out"])
        first = tr._work(w, "x", [row])
        assert first[0]["valid"], json.load(open(tmp_path / d / (row["row_id"] + ".json")))["reason"]
        assert tr._work(w, "x", [row]) == first  # resumable: read back, no replay
    meta = json.load(open(tmp_path / "a" / (row["row_id"] + ".json")))
    za, zb = (np.load(tmp_path / d / (row["row_id"] + ".npz")) for d in ("a", "b"))
    assert sorted(za.files) == sorted(zb.files) and all(np.array_equal(za[k], zb[k], equal_nan=True) for k in za.files)
    n = len(za["label"])
    assert n == len(meta["decisions"]) == meta["teacher"]["rows"] > 0
    ptr, pi, fired, side = za["cands_ptr"], za["pi"].astype(np.float32), za["tree_fired"] > 0, za["side"]
    assert fired.sum() == meta["teacher"]["tree_rows"] > 0 and np.all(fired == (side == 2))
    assert np.all((za["label"] >= 0) & (za["label"] < np.diff(ptr)))
    for i in range(n):
        seg = pi[ptr[i]:ptr[i + 1]]
        if fired[i]:
            assert abs(float(seg.sum()) - 1.0) < 0.02 and seg[za["label"][i]] > 0 and 0.0 <= float(za["v_root"][i]) <= 1.0
        else:
            assert float(seg.sum()) == 0.0 and np.isnan(float(za["v_root"][i]))
    win = meta["winner"]
    assert np.array_equal(za["outcome"], np.where(win == "draw", 0, np.where(side == (1 if win == "p1" else 2), 1, -1)))
    assert meta["teacher"]["y_cand"] == (0.5 if win == "draw" else float(win == "p2"))
    for k in ("units", "objs", "terr", "cands"):
        assert za[k].shape[0] == za[k + "_ptr"][-1] and za[k].dtype == np.float16
    assert len(za["actor"]) == len(za["target"]) == len(za["hand_score"]) == len(pi) == ptr[-1]


@needs_lists
def test_exploration_off_is_main_on_is_seeded_and_stamped(tmp_path):
    row = [r for r in fixture_rows() if r["seat"] == 1 and r["d"] == 0][0]

    def rec(tag, **over):
        w = tr._init(cfg(tmp_path / tag, **over))
        os.makedirs(w["out"])
        assert tr._work(w, "x", [row])[0]["valid"]
        return np.load(tmp_path / tag / (row["row_id"] + ".npz")), json.load(open(tmp_path / tag / (row["row_id"] + ".json")))
    main, off = rec("main"), rec("off", explore_seed=-1)
    assert sorted(main[0].files) == sorted(off[0].files) and "explored" not in off[0].files and "explored" not in off[1]["teacher"]
    assert all(np.array_equal(main[0][k], off[0][k], equal_nan=True) for k in main[0].files)  # pick identity: OFF = main's record
    a, b, c = rec("a", explore_seed=5), rec("b", explore_seed=5), rec("c", explore_seed=6)
    assert a[1]["teacher"]["explored"] and all(np.array_equal(a[0][k], b[0][k], equal_nan=True) for k in a[0].files)
    assert 0 < int(a[0]["explored"].sum()) <= 8 * 2 and not np.array_equal(a[0]["label"], c[0]["label"])


@needs_lists
def test_play_game_stamps_tree_root_only_where_the_tree_fired():
    kw = dict(FAST, record_cands=True)
    tree = sp.play_game(27, ARMY1, ARMY2, REPO, BANK, None, deep_player=1, deep_search_mode="tree", deep_tree_budget=4, **kw)
    plain = sp.play_game(27, ARMY1, ARMY2, REPO, BANK, None, **kw)
    for r in tree["planner_positions"]:
        if r["side"] == 1:
            t = r["cands"]["tree"]
            assert set(t) == {"root", "completed", "deadline_hit"} and sum(x[1] for x in t["root"]) > 0
            assert any(x[0] == r["cands"]["played"] for x in t["root"])
        else:
            assert "tree" not in r["cands"]
    assert all("tree" not in r["cands"] for r in plain["planner_positions"])


@needs_lists
def test_sidecars_off_by_default_writes_the_same_record(tmp_path):
    # GREEN: the pair/fork sidecars feed no teacher row, so OFF (the recorder default) and ON give equal arrays and equal
    # decision search stamps. RED: a field fed FROM a sidecar (features) differs between the two runs, so the equality
    # check below can fail and the sidecars are real data, not an empty block.
    row = [r for r in fixture_rows() if r["seat"] == 1 and r["d"] == 0][0]
    seen, real = [], sp.play_game

    def spy(*args, **kwargs):
        seen.append((kwargs.get("sidecars"), real(*args, **kwargs)))
        return seen[-1][1]

    def rec(tag, **knobs):
        w = tr._init(cfg(tmp_path / tag, knobs=dict(FAST, **knobs)))
        os.makedirs(w["out"])
        assert tr._work(w, "x", [row])[0]["valid"]
        return np.load(tmp_path / tag / (row["row_id"] + ".npz")), json.load(open(tmp_path / tag / (row["row_id"] + ".json")))
    sp.play_game = spy
    try:
        off, on = rec("off"), rec("on", sidecars=True)
    finally:
        sp.play_game = real
    assert [s for s, _ in seen] == [False, True]
    assert sorted(off[0].files) == sorted(on[0].files) and all(np.array_equal(off[0][k], on[0][k], equal_nan=True) for k in off[0].files)
    assert [d.get("search") for d in off[1]["decisions"]] == [d.get("search") for d in on[1]["decisions"]]
    fed = [np.array([len(r.get("features", ())) for r in res["planner_positions"]]) for _, res in seen]
    assert not np.array_equal(fed[0], fed[1])  # RED: a sidecar-fed array differs
    assert all("fork" not in r and "features" not in r for r in seen[0][1]["planner_positions"])
    assert any("fork" in r for r in seen[1][1]["planner_positions"])
