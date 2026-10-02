#!/usr/bin/env python3
"""Tests for tools/lab2_source.py: real source games (1000 pt lists, bank, shipped net, top_k 2 / horizon 1).
Run on the laptop: ~/.cache/nml-stage0/venv/bin/python3 -m pytest -q tools/lab2_source_test.py
Skip with a named reason where nml_core, onnxruntime, the bank or the lists are absent (CI)."""
import importlib.util
import inspect
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(_HERE)
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.join(REPO, "core", "nml-core-py", "python"))
BANK = os.path.expanduser("~/selfplay_out/terrain_bank")
LISTS = os.path.expanduser("~/nml-mission/farm/ai_lists")
NEEDS = [m for m in ("nml_core", "onnxruntime") if importlib.util.find_spec(m) is None]
if not (os.path.isdir(BANK) and os.path.isdir(LISTS)):
    NEEDS.append("bank/lists")
pytestmark = pytest.mark.skipif(bool(NEEDS), reason="needs %s (laptop venv gate)" % ", ".join(NEEDS))
if not NEEDS:
    import nml_core
    import selfplay as sp
    import lab2_source as ls
    from lab2_net import ShippedNet

PLAY_KW = dict(top_k=2, horizon=1)


def row(cand, seed=29, mover=1):
    return dict(slot="s1", cell="c1", mission="domination", mover=str(mover), candidate=cand,
                list_p1="robot_legions_1000.json", list_p2="blessed_sisters_1000.json", terrain=str(seed),
                layout=str(seed + 1000), deploy=str(seed + 2000), play=str(seed + 3000), tray=str(seed + 4000),
                extra="x")


@pytest.fixture(scope="module")
def env():
    return nml_core.load(REPO), ShippedNet(REPO)


def run(env, rows, cap):
    core, net = env
    return ls.generate(sp, core, {"s1": rows}, REPO, BANK, LISTS, net, cap, PLAY_KW)


def test_second_candidate_is_taken_when_the_first_is_ineligible(env):
    positions, discarded, missing = run(env, [row("a", mover=3), row("b")], cap=20)
    assert missing == [] and [p["candidate"] for p in positions] == ["b"]
    assert [d["candidate"] for d in discarded] == ["a"] and discarded[0]["reason"] == "mover_mismatch"
    assert positions[0]["keys"] == {"extra": "x"} and positions[0]["mover"] == 1


def test_cap_one_with_an_ineligible_first_is_missing(env):
    positions, discarded, missing = run(env, [row("a", mover=3), row("b")], cap=1)
    assert positions == [] and missing == ["s1"] and len(discarded) == 1


def test_snapshot_round_trips_through_state_of(env):
    positions, _, _ = run(env, [row("b")], cap=1)
    snap = positions[0]
    state = env[0].state_of(snap["state"])
    assert state.plain() == snap["state"] and snap["state"]["round"] == snap["state"]["rounds_total"]
    assert all(2 <= len(state.pool(p, True)) <= 3 for p in (1, 2)) and len(snap["owners_before_round"]) > 0


def test_spy_reads_no_result_field():
    src = inspect.getsource(ls.Spy)
    for word in ("winner", "rounds_log", "verdict", "result", '"vp"', "expectation"):
        assert word not in src, word



def test_cli_writes_positions_proof_and_exit_code(tmp_path):
    import csv, json
    tsv, header, out = tmp_path / "s.tsv", tmp_path / "h.json", tmp_path / "p.json"
    with open(tsv, "w", newline="") as f:
        w = csv.DictWriter(f, list(row("a")), delimiter="\t")
        w.writeheader(), w.writerow(row("a"))
    header.write_text(json.dumps({"knobs": {"top_k": 2, "horizon": 1, "menu_wide": "table"}}))
    argv = ["source", "--slots", str(tsv), "--bank", BANK, "--lists", LISTS, "--header", str(header), "--out", str(out)]
    assert ls.main(argv) == 0
    data = json.loads(out.read_text())
    assert len(data["positions"]) == 1 and data["ignored_header_knobs"] == ["menu_wide"]
    assert data["net"]["1"]["calls"] > 0 and data["net"]["2"]["calls"] > 0
