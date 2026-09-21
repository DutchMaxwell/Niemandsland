"""Pin the ONNX<->tract parity receipt contract, stdlib only.

`parity_pinned_10238.json` carries the Python (onnxruntime) reference values
for a deterministic corpus of 10,238 token positions seeded from the public
stand-in leaves. `tests/onnx_parity.rs` rebuilds the same corpus and asserts
`max_abs <= tolerance`; this test proves the receipt belongs to exactly that
corpus (sha256 of the float32 inputs, recomputed through the same generator)
and that its expected values are finite, in the value head's tanh range, two
member lists long, and within the commit-size budget.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core-godot" / "tests" / "fixtures" / "onnx"
RECEIPT = FIXTURES / "parity_pinned_10238.json"
ONNX = FIXTURES / "standin-v2x2.onnx"
GOLDEN = FIXTURES / "parity_base_standin-v2x2.json"   # the FROZEN 11.09. golden = the parity corpus base (golden_standin-v2x2.json tracks the core tokens since 21.09.)
MAX_FIXTURE_BYTES = 2_000_000

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gen_onnx_parity_corpus as gen  # noqa: E402


def _load(path):
    return json.loads(path.read_bytes())


def test_parity_receipt_contract():
    raw = RECEIPT.read_bytes()
    assert len(raw) <= MAX_FIXTURE_BYTES, "receipt grew past the 2 MB data budget"
    receipt = json.loads(raw)

    assert receipt["schema"] == 1
    assert receipt["tolerance"] == 1e-5
    assert receipt["static_batch"] == 32
    assert receipt["inputs"] == gen.INPUT_NAMES
    assert receipt["outputs"] == gen.OUTPUT_NAMES

    corpus = receipt["corpus"]
    count = corpus["count"]
    assert count >= 10_000, count
    assert corpus["seed"] == gen.SEED
    assert corpus["base_fixture"] == "parity_base_standin-v2x2.json"
    assert corpus["base_leaves"] == 60
    assert corpus["spec"] == gen.SPEC

    expected = receipt["expected"]
    value = expected["value"]
    members = expected["member_values"]
    assert len(value) == count
    assert len(members) == 2, "the stand-in ensemble has two members"
    assert all(len(member) == count for member in members)
    for number in value + [v for member in members for v in member]:
        assert math.isfinite(number)
        assert -1.0 <= number <= 1.0

    reference = receipt["reference"]
    assert reference["runtime"] == "onnxruntime"
    assert reference["provider"] == "CPUExecutionProvider"
    assert reference["intra_op_threads"] == 1
    assert reference["onnx_sha256"] == hashlib.sha256(ONNX.read_bytes()).hexdigest()
    assert reference["golden_sha256"] == hashlib.sha256(GOLDEN.read_bytes()).hexdigest()
    assert reference["golden60_max_abs"] <= receipt["tolerance"]
    assert reference["golden60_member_max_abs"] <= receipt["tolerance"]

    leaves = gen.load_leaves(GOLDEN)
    assert gen.corpus_digest(leaves, count, corpus["seed"]) == corpus["input_sha256"]
