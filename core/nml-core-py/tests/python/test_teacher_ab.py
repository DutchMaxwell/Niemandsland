"""Per-seat value nets on the teacher recorder (loop prep D-L2, 07.10.2026): `--net-cand` rides the ROW'S seat, `--net-inc`
the other seat, so `--arm I` (no deep core, both seats the incumbent 10/3 search) becomes an A/B of two value nets at
the shipped grade — the loop's gate games. The proofs:

  * with two nets, the row's `model_sha256` names both as `<cand>:<inc>`, every seat consulted its net (`net` counts > 0
    on both), and the OBJECTS prove the seating: the candidate net was called for the row's seat only, the incumbent net
    for the other seat only (the counts live on the net objects, keyed by side);
  * the mirror: a seat-2 row seats the candidate net on seat 2;
  * without the options nothing changes: one shipped net on both seats, `model_sha256` = the shipped sha.

The candidate "net" is the shipped file under another name (same weights): the plumbing is proven by identities and
counts, not by a strength number. Skipped without the private fixtures or onnxruntime.
"""
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

import pytest

pytest.importorskip("onnxruntime")
import nml_core  # noqa: E402,F401

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(REPO / "tools"))
import lab2_net  # noqa: E402
import lab2_tree_probe as lab  # noqa: E402
import teacher_record as tr  # noqa: E402

BANK = Path(os.path.expanduser("~/selfplay_out/terrain_bank"))
LISTS = Path(os.path.expanduser("~/nml-mission/farm/ai_lists"))
ARMY1, ARMY2 = LISTS / "robot_legions_1000.json", LISTS / "blessed_sisters_1000.json"
needs_lists = pytest.mark.skipif(not (BANK.is_dir() and ARMY1.exists() and ARMY2.exists()),
                                 reason="private fixtures (terrain bank + lists) not on this box")
SHIPPED = REPO / "assets" / "solo" / "brains" / "erlkoenig.onnx"


def cfg(out, **over):
    c = {"repo": str(REPO), "bank": str(BANK), "out": str(out), "knobs": {"top_k": 2, "horizon": 1}, "budget": 0, "pair": (2, 1),
         "allowance": 0, "prereg": "test", "net_cand": "", "net_inc": ""}
    c.update(over)
    return c


def i_rows():
    block = {"block": "B", "cell": "c1", "mission": "duel", "army1": str(ARMY1), "army2": str(ARMY2),
             "seeds": {"terrain": "27", "layout": "91002", "deploy": "91003", "play_general": ["91004", "91005"],
                       "tray": ["91006", "91007"], "search": {}}}
    return lab.game_rows([block], ("I",))


@needs_lists
@pytest.mark.parametrize("seat", [1, 2])
def test_two_nets_sit_on_their_seats_and_are_both_named(tmp_path, seat):
    cand = tmp_path / "cand.onnx"
    shutil.copy(SHIPPED, cand)
    w = tr._init(cfg(tmp_path / "out", net_cand=str(cand)))
    row = [r for r in i_rows() if r["seat"] == seat and r["d"] == 0][0]
    meta, rows = tr.play(w, row)
    assert meta["valid"], meta["reason"]
    sha = lab2_net._sha256(str(cand))
    assert meta["model_sha256"] == "%s:%s" % (sha, w["nets"][2].model_sha256)
    assert all(meta["net"][str(s)]["calls"] > 0 for s in (1, 2))
    # the objects prove the seating: the candidate net answered the row's seat only, the incumbent net the other seat only
    assert set(k for k, c in w["nets"][1].counts.items() if c["calls"] > 0) == {seat}
    assert set(k for k, c in w["nets"][2].counts.items() if c["calls"] > 0) == {3 - seat}
    assert rows and all(int(r["tree_fired"]) == 0 for r in rows)  # arm I: value rows only, no tree


@needs_lists
def test_without_the_options_one_shipped_net_serves_both_seats(tmp_path):
    w = tr._init(cfg(tmp_path / "out"))
    row = [r for r in i_rows() if r["seat"] == 1 and r["d"] == 1][0]
    meta, _ = tr.play(w, row)
    assert meta["valid"] and meta["model_sha256"] == lab2_net._sha256(str(SHIPPED))
    assert meta["teacher"] if "teacher" in meta else True
