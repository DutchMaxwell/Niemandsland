#!/usr/bin/env python3
"""Fixture tests for tools/geom_probe.py.

The probe exists because the shipped judge sees state tokens only; the candidate landing geometry is dropped. The
RED pins the core claim: the signature is a step function of the landing, so crossing a forest edge (1 inch) flips
it while translating 1 inch across open ground does not. Also pinned: the OBB point test, the side un-mirror of the
`terr` decode, the distinct-signature count over a synthetic shard, and the CLI report.

Run:  python3 -m pytest tools/geom_probe_test.py
"""
import importlib.util
import json
import os

import pytest

np = pytest.importorskip("numpy")
_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("geom_probe", os.path.join(_HERE, "geom_probe.py"))
gp = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(gp)


def forest_edge():
    """One 4x4 inch forest piece at the table centre (half-extent 2 inch, axis-aligned)."""
    return [gp.Obb(0.0, 0.0, 2.0, 2.0, 0.0, gp.FOREST)]


def test_cover_edge_differs_and_open_ground_matches():
    t = forest_edge()
    inside = gp.signature(1.0, 0.0, t)   # 1 inch inside the edge (edge at x = 2)
    outside = gp.signature(3.0, 0.0, t)  # 1 inch outside
    assert inside != outside
    assert inside[0] == gp.FOREST and inside[1] == 1
    assert outside[0] == gp.NONE and outside[1] == 0
    a = gp.signature(10.0, 0.0, t)       # two open-ground cells 1 inch apart
    b = gp.signature(11.0, 0.0, t)
    assert a == b
    assert a[0] == gp.NONE and a[1] == 0


def test_point_in_obb_respects_yaw():
    obb = gp.Obb(0.0, 0.0, 2.0, 1.0, 0.0, gp.RUINS)
    assert gp.point_in_obb(1.9, 0.9, obb)
    assert not gp.point_in_obb(2.1, 0.0, obb)
    turned = gp.Obb(0.0, 0.0, 2.0, 1.0, 1.5707963267948966, gp.RUINS)
    assert gp.point_in_obb(0.9, 1.9, turned)      # rotated 90 deg -> the long axis is now y
    assert not gp.point_in_obb(1.9, 0.0, turned)


def test_terrain_kind_bits():
    assert gp.gives_cover(gp.FOREST) and gp.gives_cover(gp.RUINS)
    assert not gp.gives_cover(gp.CONTAINER)
    assert gp.is_difficult(gp.FOREST) and not gp.is_difficult(gp.RUINS)
    assert gp.is_dangerous(gp.DANGEROUS) and not gp.is_dangerous(gp.FOREST)


def test_decode_terrain_unmirrors_by_side():
    row = [0.65, -0.45, 0.375, 0.375, 1.0, 0.0, 0, 1, 0, 0, 1, 1]  # forest at (19.5, -13.5) inch, side 1
    one = gp.decode_terrain([row], 1)
    two = gp.decode_terrain([row], 2)
    assert one[0].kind == gp.FOREST and one[0].cx == pytest.approx(19.5) and one[0].cy == pytest.approx(-13.5)
    assert two[0].cx == pytest.approx(-19.5) and two[0].cy == pytest.approx(13.5)


def _shard():
    """A 2-decision shard: d0 has a cover landing, two open landings, and a HOLD fallback (dropped); d1 is all open."""
    z = {}
    z["side"] = np.array([1, 1], np.int8)
    z["terr_ptr"] = np.array([0, 1, 1], np.int64)
    z["terr"] = np.array([[0.0, 0.0, 2.0 / 12.0, 2.0 / 12.0, 1.0, 0.0, 0, 1, 0, 0, 1, 1]], np.float16)
    z["geom_ptr"] = np.array([0, 4, 6], np.int64)
    z["geom_kind"] = np.array([1, 1, 0, 1, 1, 1], np.int8)          # index 2 is HOLD (dest-less fallback)
    z["geom_cell"] = np.array([94, 1458, 1458, 1458, 1458, 1458], np.int16)
    z["geom_x_in"] = np.array([37.0, 39.0, 37.0, 46.0, 46.0, 47.0], np.float32)   # 0-origin: 36 = centre
    z["geom_y_in"] = np.array([24.0, 24.0, 24.0, 24.0, 24.0, 24.0], np.float32)
    z["geom_rs"] = np.array([0.3, 0.3, 0.3, 0.3, 0.3, 0.3], np.float16)
    return z


def test_probe_counts_distinct_signatures(tmp_path):
    p = tmp_path / "shard.npz"
    np.savez(p, **_shard())
    v = gp.probe(str(p))
    assert v["n_decisions"] == 2 and v["n_landings"] == 5   # the HOLD fallback is not a landing
    assert v["distinct_median"] == 1.5   # d0 -> 2 distinct (cover + open), d1 -> 1
    assert v["flat_rs_decisions"] == 2   # both decisions have flat rs (max-min < 0.0019)
    assert v["flat_rs_distinct_median"] == 1.5


def test_probe_skips_a_shard_without_geom(tmp_path):
    p = tmp_path / "plain.npz"
    np.savez(p, side=np.array([1], np.int8), terr_ptr=np.array([0, 0], np.int64),
             terr=np.zeros((0, 12), np.float16))
    v = gp.probe(str(p))
    assert v["n_shards_skipped"] == 1 and v["n_decisions"] == 0


def test_main_writes_report(tmp_path):
    d = tmp_path / "corpus"
    d.mkdir()
    np.savez(d / "shard.npz", **_shard())
    out = tmp_path / "GATE.json"
    rc = gp.main(["--corpus", str(d), "--out", str(out)])
    assert rc == 0
    v = json.loads(out.read_text())
    assert v["n_shards"] == 1 and v["n_decisions"] == 2
