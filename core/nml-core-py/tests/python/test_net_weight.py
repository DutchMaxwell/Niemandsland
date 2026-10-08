"""`--net-cand-weight` / `--net-inc-weight`: the ONNX leaf hook scales its value (the shipped game's pick = argmax(rs + w * net)).
Needs neither a model file nor the private terrain bank: the session is faked.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

pytest.importorskip("onnxruntime")
pytest.importorskip("nml_core")

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "python"))
sys.path.insert(0, str(REPO / "tools"))
import lab2_net  # noqa: E402
import teacher_record as tr  # noqa: E402

VALUES = [0.25, -0.5, 0.125]


def _net(weight):
    """A ShippedNet without an onnx session: only `values()` is faked."""
    net = lab2_net.ShippedNet.__new__(lab2_net.ShippedNet)
    net.weight, net.counts = weight, {}
    net.values = lambda tokens: list(VALUES[:len(tokens)])
    return net


def test_hook_weight_scales_and_weight_one_is_a_noop():
    leaves = [object()] * 3
    base = _net(1.0).hook(1)(leaves, 1)
    assert base == VALUES
    assert _net(2.0).hook(1)(leaves, 1) == [2.0 * v for v in VALUES]
    # the constructor takes the keyword and defaults to 1.0
    import inspect
    assert inspect.signature(lab2_net.ShippedNet.__init__).parameters["weight"].default == 1.0


def _header(tmp_path, monkeypatch, extra):
    cap = {}
    (tmp_path / "g.json").unlink(missing_ok=True)
    monkeypatch.setattr(tr, "play", lambda w, row: ({"valid": False, "winner": "p1"}, []))
    monkeypatch.setattr(tr.lab, "write_row", lambda out, meta: (tmp_path / "g.json").write_text(json.dumps(meta)))
    monkeypatch.setattr(tr.lab, "game_rows", lambda blocks, arms: [{"row_id": "g", "seat": 1, "d": 0, "arm": "I"}])
    monkeypatch.setattr(tr.lab2_pool, "run_clusters", lambda rows, workers, init, work, args: cap.update(cfg=args[0]) or [])
    blocks = tmp_path / "b.json"
    blocks.write_text("{}")
    tr.main(["--blocks", str(blocks), "--out", str(tmp_path), "--bank", "x", "--repo", "y"] + extra)
    w = dict(cap["cfg"], out=str(tmp_path))
    tr._work(w, 0, [{"row_id": "g", "seat": 1, "d": 0, "arm": "I"}])
    return json.loads((tmp_path / "g.json").read_text())["teacher"]


def test_header_carries_the_weights_only_when_given(tmp_path, monkeypatch):
    t = _header(tmp_path, monkeypatch, ["--net-cand-weight", "2.0"])
    assert t["net_cand_weight"] == 2.0
    assert "net_inc_weight" not in t
    plain = _header(tmp_path, monkeypatch, [])
    assert "net_cand_weight" not in plain and "net_inc_weight" not in plain
