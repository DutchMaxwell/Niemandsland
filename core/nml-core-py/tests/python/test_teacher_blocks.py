"""Teacher block manifests (loop prep, 07.10.2026) — `core/nml-core-py/tools/teacher_blocks.py`: the blocks are the
stage-0 manifest shape (`tools/lab2_tree_probe.game_rows` builds 4 rows per block and arm, every tree arm finds its
registered search key), the terrain seeds are board ids of the bank, the same seed gives the same manifest and a
different seed a different one. Runs on a synthetic bank directory, no wheel needed."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "tools"))
import lab2_tree_probe as lab  # noqa: E402
import teacher_blocks as tb  # noqa: E402


def bank(tmp_path):
    b = tmp_path / "bank"
    b.mkdir()
    for i in (5, 17, 400):
        (b / ("board_%d.json" % i)).write_text("{}")
    (b / "notes.txt").write_text("not a board")
    return b


def test_manifest_shape_rows_and_determinism(tmp_path):
    out = tmp_path / "b.json"
    assert tb.main(["--out", str(out), "--n", "3", "--seed", "5", "--lists", "/l/x.json,/l/y.json", "--bank", str(bank(tmp_path))]) == 0
    blocks = json.load(open(out))
    assert [b["block"] for b in blocks] == ["G000000", "G000001", "G000002"]
    assert {b["seeds"]["terrain"] for b in blocks} <= {"5", "17", "400"}
    assert blocks[0]["army1"] == "/l/x.json" and blocks[0]["army2"] == "/l/y.json" and blocks[1]["army1"] == "/l/y.json"
    for arm in ("L", "T", "L_tray"):
        rows = lab.game_rows(blocks, (arm,))
        assert len(rows) == 12 and all(set(r["seeds"]["search"]) == {"1", "2"} for r in rows)
    assert len(lab.game_rows(blocks, ("I",))) == 12 and all(r["seeds"]["search"] == {} for r in lab.game_rows(blocks, ("I",)))
    assert tb.make_blocks(3, 5, ["/l/x.json", "/l/y.json"], str(tmp_path / "bank")) == blocks
    assert tb.make_blocks(3, 6, ["/l/x.json", "/l/y.json"], str(tmp_path / "bank")) != blocks
