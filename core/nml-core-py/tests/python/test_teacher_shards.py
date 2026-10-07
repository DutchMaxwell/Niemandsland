"""Teacher shard packer (loop prep, 07.10.2026) — `core/nml-core-py/tools/teacher_shards.py` on SYNTHETIC games in the
recorder's packed layout (netlab/SHARD_SCHEMA.md + the teacher columns), so this runs without fixtures or a wheel:

  * two games pack into one shard whose ptr columns re-base, `game_id` follows the sorted game order and the json names
    the games; an INVALID game (json valid false) and a json without its npz are left out;
  * only FULL shards land unless `--final`; a rerun writes nothing new (resumable by the json's existence);
  * RED: a poisoned game (pi mass doubled on a tree row; a label outside its menu) is REFUSED naming the position, and
    no shard file lands.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import teacher_shards as ts  # noqa: E402

F_U, F_O, F_T, F_G, F_C = 91, 12, 12, 16, 40


def synthetic_game(rng, n_pos, tree_side=1):
    """One game's packed arrays: ragged token blocks, pi = a normalised random distribution on the tree side's rows."""
    rows = {k: [] for k in ("units", "objs", "terr", "cands", "actor", "target", "hand_score", "pi")}
    flat = {k: [] for k in ("label", "tree_fired", "v_root", "v_pick", "completed", "outcome", "side", "round", "seq")}
    glob = []
    for i in range(n_pos):
        nu, no, nc, side = int(rng.integers(6, 12)), int(rng.integers(3, 6)), int(rng.integers(4, 9)), 1 + i % 2
        rows["units"].append(rng.standard_normal((nu, F_U)).astype(np.float16))
        rows["objs"].append(rng.standard_normal((no, F_O)).astype(np.float16))
        rows["terr"].append(rng.standard_normal((18, F_T)).astype(np.float16))
        rows["cands"].append(rng.standard_normal((nc, F_C)).astype(np.float16))
        rows["actor"].append(rng.integers(0, nu, nc).astype(np.int16))
        rows["target"].append(np.where(rng.random(nc) < 0.5, -1, rng.integers(0, nu, nc)).astype(np.int16))
        rows["hand_score"].append(np.full(nc, np.nan, np.float16))
        fired = side == tree_side
        pi = rng.random(nc) if fired else np.zeros(nc)
        pi = (pi / pi.sum()).astype(np.float16) if fired else pi.astype(np.float16)
        rows["pi"].append(pi)
        glob.append(rng.standard_normal(F_G).astype(np.float16))
        flat["label"].append(int(pi.argmax()) if fired else int(rng.integers(0, nc)))
        flat["tree_fired"].append(int(fired))
        flat["v_root"].append(rng.random() if fired else np.nan)
        flat["v_pick"].append(rng.random() if fired else np.nan)
        flat["completed"].append(64 if fired else 0)
        flat["outcome"].append(1 if side == 1 else -1)
        flat["side"].append(side)
        flat["round"].append(1 + i // 4)
        flat["seq"].append(i)
    out = {"game_id": np.zeros(n_pos, np.int32), "glob": np.stack(glob)}
    for k in ("units", "objs", "terr", "cands"):
        out[k + "_ptr"] = np.concatenate([[0], np.cumsum([len(r) for r in rows[k]])]).astype(np.int64)
        out[k] = np.concatenate(rows[k])
    for k in ("actor", "target", "hand_score", "pi"):
        out[k] = np.concatenate(rows[k])
    dt = {"label": np.int16, "tree_fired": np.int8, "v_root": np.float16, "v_pick": np.float16, "completed": np.int32,
          "outcome": np.int8, "side": np.int8, "round": np.int8, "seq": np.int16}
    for k, t in dt.items():
        out[k] = np.asarray(flat[k], t)
    return out


def write_game(d, name, z, valid=True, npz=True):
    os.makedirs(d, exist_ok=True)
    if npz:
        np.savez(os.path.join(d, name + ".npz"), **z)
    json.dump({"row_id": name, "valid": valid, "winner": "p1", "decisions": []}, open(os.path.join(d, name + ".json"), "w"))


def test_two_games_pack_into_one_shard_and_rerun_is_a_noop(tmp_path):
    rng = np.random.default_rng(3)
    g = tmp_path / "games"
    a, b = synthetic_game(rng, 7), synthetic_game(rng, 5)
    write_game(g, "B01_L_d0_s1", a)
    write_game(g, "B01_L_d0_s2", b)
    write_game(g, "B02_L_d0_s1", synthetic_game(rng, 4), valid=False)   # INVALID: left out
    write_game(g, "B02_L_d0_s2", synthetic_game(rng, 4), npz=False)     # no npz: left out
    assert ts.main(["shard", "--games", str(g), "--out", str(tmp_path / "s"), "--shard-size", "2"]) == 0
    meta = json.load(open(tmp_path / "s" / "teacher_shard_00000.json"))
    z = np.load(tmp_path / "s" / "teacher_shard_00000.npz")
    assert meta["games_named"] == ["B01_L_d0_s1", "B01_L_d0_s2"] and meta["positions"] == 12 and meta["games"] == 2
    assert z["game_id"].tolist() == [0] * 7 + [1] * 5 and meta["tree_positions"] == int((z["tree_fired"] > 0).sum())
    for k in ("units", "objs", "terr", "cands"):
        assert z[k + "_ptr"].tolist() == np.concatenate([[0], np.cumsum(np.concatenate([np.diff(a[k + "_ptr"]), np.diff(b[k + "_ptr"])]))]).tolist()
        assert np.array_equal(z[k], np.concatenate([a[k], b[k]]))
    assert np.array_equal(z["pi"], np.concatenate([a["pi"], b["pi"]])) and np.array_equal(z["label"], np.concatenate([a["label"], b["label"]]))
    before = os.stat(tmp_path / "s" / "teacher_shard_00000.npz").st_mtime_ns
    assert ts.main(["shard", "--games", str(g), "--out", str(tmp_path / "s"), "--shard-size", "2"]) == 0
    assert os.stat(tmp_path / "s" / "teacher_shard_00000.npz").st_mtime_ns == before
    assert ts.main(["check", "--shard", str(tmp_path / "s" / "teacher_shard_00000.npz")]) == 0


def test_partial_shard_only_with_final(tmp_path):
    rng = np.random.default_rng(4)
    g = tmp_path / "games"
    for i in range(3):
        write_game(g, "B%02d_L_d0_s1" % i, synthetic_game(rng, 3))
    assert ts.main(["shard", "--games", str(g), "--out", str(tmp_path / "s"), "--shard-size", "2"]) == 0
    assert sorted(os.listdir(tmp_path / "s")) == ["teacher_shard_00000.json", "teacher_shard_00000.npz"]
    assert ts.main(["shard", "--games", str(g), "--out", str(tmp_path / "s"), "--shard-size", "2", "--final"]) == 0
    meta = json.load(open(tmp_path / "s" / "teacher_shard_00001.json"))
    assert meta["games_named"] == ["B02_L_d0_s1"] and meta["game_id_base"] == 2
    assert np.load(tmp_path / "s" / "teacher_shard_00001.npz")["game_id"].tolist() == [2, 2, 2]


@pytest.mark.parametrize("poison", ["pi", "label"])
def test_poisoned_game_is_refused_naming_the_position(tmp_path, poison):
    z = synthetic_game(np.random.default_rng(5), 6)
    i = int(np.flatnonzero(z["tree_fired"] > 0)[1])
    if poison == "pi":
        z["pi"][z["cands_ptr"][i]:z["cands_ptr"][i + 1]] *= 2
    else:
        z["label"][i] = z["cands_ptr"][i + 1] - z["cands_ptr"][i]
    write_game(tmp_path / "g", "P_L_d0_s1", z)
    with pytest.raises(SystemExit, match="position %d" % i):
        ts.main(["shard", "--games", str(tmp_path / "g"), "--out", str(tmp_path / "s"), "--shard-size", "1"])
    assert not os.path.exists(tmp_path / "s" / "teacher_shard_00000.npz")
