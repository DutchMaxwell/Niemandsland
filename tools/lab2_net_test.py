#!/usr/bin/env python3
"""Tests for tools/lab2_net.py. Run: python3 -m pytest -q tools/lab2_net_test.py

The value check runs the committed stand-in ONNX (v1 24 x 90 window) on the committed parity
corpus and compares with the receipt of test_onnx_parity_receipt.py; the shipped-model checks run
the real erlkoenig.onnx. Both skip with a named reason where onnxruntime is absent (CI); the
laptop gate runs them in ~/.cache/nml-stage0/venv.
"""
import importlib.util
import json
import os
import sys

import pytest

_HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(_HERE)
_SPEC = importlib.util.spec_from_file_location("lab2_net", os.path.join(_HERE, "lab2_net.py"))
net = importlib.util.module_from_spec(_SPEC)
sys.modules["lab2_net"] = net
_SPEC.loader.exec_module(net)

FIX = os.path.join(REPO, "core", "nml-core-godot", "tests", "fixtures", "onnx")
STANDIN = os.path.join(FIX, "standin-v2x2.onnx")
sys.path.insert(0, os.path.join(REPO, "core", "nml-core-py", "tests", "python"))
import gen_onnx_parity_corpus as gen  # noqa: E402

try:
    import onnxruntime  # noqa: F401
    NEED = None
except ImportError:
    NEED = "onnxruntime not installed (CI); the laptop gate runs this in ~/.cache/nml-stage0/venv"
needs_ort = pytest.mark.skipif(NEED is not None, reason=NEED or "")

try:
    import numpy  # noqa: F401
    NEED_NP = None
except ImportError:
    NEED_NP = "numpy not installed"
needs_np = pytest.mark.skipif(NEED_NP is not None, reason=NEED_NP or "")


def core_token(row):
    """A flat parity-corpus row as the core's own token dict: 32 x 91 unit window (one 0 pad column)."""
    units, mask, objs, objs_mask, terr, glob = row
    rows = [units[r * 90:(r + 1) * 90] + [0.0] for r in range(24)] + [[0.0] * 91 for _ in range(8)]
    return {"units": rows, "units_mask": list(mask) + [0] * 8,
            "objs": [objs[r * 12:(r + 1) * 12] for r in range(6)], "objs_mask": list(objs_mask),
            "terr": [terr[r * 12:(r + 1) * 12] for r in range(18)], "glob": list(glob)}


def real_net():
    return net.ShippedNet(REPO)


def standin_net():
    return net.ShippedNet(REPO, onnx=STANDIN, sha256=net._sha256(STANDIN))


@needs_ort
def test_values_match_the_parity_receipt():
    receipt = json.load(open(os.path.join(FIX, "parity_pinned_10238.json")))
    expected = receipt["expected"]["value"]
    leaves = gen.load_leaves(gen.Path(FIX) / "parity_base_standin-v2x2.json")
    # Positions 0..47 are the real golden leaves (pad columns 88/89 are zero, as the game feeds them);
    # 48..59 and the mixed positions p >= 60 are synthetic with random pads the game never sends.
    # 48 leaves span two chunks, the last one zero-padded.
    positions = list(range(48))
    rows = {p: gen.row_of(leaves, p) for p in positions}
    got = standin_net().values([core_token(rows[p]) for p in positions])
    worst = max(abs(g - expected[p]) for g, p in zip(got, positions))
    assert worst <= 1e-6, worst


@needs_ort
def test_byte_flipped_model_refuses(tmp_path):
    raw = bytearray(open(os.path.join(REPO, net.BRAINS, "erlkoenig.onnx"), "rb").read())
    raw[len(raw) // 2] ^= 1
    bad = tmp_path / "erlkoenig.onnx"
    bad.write_bytes(bytes(raw))
    with pytest.raises(net.NetRefused):
        net.ShippedNet(REPO, onnx=str(bad))


@needs_ort
def test_shipped_model_loads_and_proof_starts_at_zero():
    n = real_net()
    assert (n.rows, n.width, n.static_batch) == (32, 91, 32)
    n.hook(1), n.hook(2)
    assert n.proof() == {1: {"calls": 0, "leaves": 0}, 2: {"calls": 0, "leaves": 0}, "model_sha256": n.model_sha256}


@needs_ort
def test_too_many_live_units_raises_and_hook_counts():
    leaves = gen.load_leaves(gen.Path(FIX) / "parity_base_standin-v2x2.json")
    n = standin_net()
    tok = core_token(gen.row_of(leaves, 0))
    h = n.hook(1)
    assert len(h([tok, tok, tok], 1)) == 3
    assert n.proof()[1] == {"calls": 1, "leaves": 3}
    full = dict(tok, units_mask=[1] * 25 + [0] * 7)
    with pytest.raises(net.TooManyUnits):
        h([full], 1)
    assert n.proof()[1] == {"calls": 1, "leaves": 3}


class _DynSession:
    """The standin session behind a dynamic-batch face: the batch axis is a name, run() takes ANY batch (the real
    model's 32 slots are filled slice by slice inside) and logs the batch it was handed."""

    def __init__(self, real):
        self.real, self.batches = real, []

    def get_inputs(self):
        ins = self.real.get_inputs()
        return [type("I", (), {"shape": ["N"] + list(ins[0].shape[1:])})()] + list(ins[1:])

    def get_modelmeta(self):
        return self.real.get_modelmeta()

    def run(self, names, feed):
        import numpy as np
        b = feed["units"].shape[0]
        self.batches.append(b)
        outs = []
        for i in range(0, b, 32):
            part = {k: v[i:i + 32] for k, v in feed.items()}
            n = part["units"].shape[0]
            pad = {k: np.concatenate([v, np.zeros((32 - n,) + v.shape[1:], v.dtype)]) for k, v in part.items()}
            outs.append([o[:n] for o in self.real.run(names, pad)])
        return [np.concatenate([o[j] for o in outs]) for j in range(len(outs[0]))]


@needs_ort
def test_dynamic_batch_packs_exact_rows_and_matches_the_static_values():
    # GREEN: a dynamic-batch model gets exactly len(leaves) rows per call (chunks of <= MAX_DYNAMIC_BATCH) and the same
    # values as the padded static path. RED: the static model (the shipped one) is still padded to 32 -- the packing
    # branch is the only thing that moved.
    leaves = gen.load_leaves(gen.Path(FIX) / "parity_base_standin-v2x2.json")
    toks = [core_token(gen.row_of(leaves, p)) for p in range(7)]
    static, dyn = standin_net(), standin_net()
    spy = _DynSession(dyn.session)
    dyn.session, dyn.static_batch = spy, None
    want = static.values(toks)
    assert dyn.values(toks) == want and spy.batches == [7]
    dyn.values(toks * 20)  # 140 leaves -> 128 + 12
    assert spy.batches == [7, 128, 12]
    seen = []
    real_run = static.session.run
    static.session.run = lambda n, f: (seen.append(f["units"].shape[0]), real_run(n, f))[1]
    static.values(toks)
    assert seen == [32]


class _FakeValueSession:
    """A session whose graph exposes output [0] = mean, and, with members, output [1] = per-member (n, 2).

    No .onnx file, no GPU: `run` fabricates the two outputs for whatever batch it is handed, so the
    batching walk can be exercised directly.
    """

    def __init__(self, with_members):
        self.with_members = with_members

    def get_outputs(self):
        return [object(), object()] if self.with_members else [object()]

    def run(self, names, feed):
        n = feed["units"].shape[0]
        mean = numpy.arange(1, n + 1, dtype=numpy.float32)
        if not self.with_members:
            return [mean]
        return [mean, numpy.stack([mean - 0.25, mean + 0.25], axis=1)]


def fake_net(with_members):
    n = net.ShippedNet.__new__(net.ShippedNet)
    n.np = numpy
    n.rows, n.width, n.static_batch = 32, 91, 32
    n.weight, n.counts = 1.0, {}
    n.session = _FakeValueSession(with_members)
    return n


def fake_token():
    return {"units": [[0.0] * 91] * 32, "units_mask": [0] * 32,
            "objs": [[0.0] * 12] * 6, "objs_mask": [0] * 6,
            "terr": [[0.0] * 12] * 18, "glob": [0.0] * 16}


@needs_np
def test_member_values_shape_and_mean_match_values():
    n = fake_net(with_members=True)
    toks = [fake_token() for _ in range(3)]
    members = n.member_values(toks)
    assert members.shape == (3, 2)
    assert numpy.allclose(members.mean(axis=1), n.values(toks), atol=1e-6)


@needs_np
def test_member_values_refuses_without_output_one():
    n = fake_net(with_members=False)
    with pytest.raises(net.NetRefused) as excinfo:
        n.member_values([fake_token()])
    assert "output" in str(excinfo.value)
