"""PART C -- the public random-weight ONNX stand-in fixture.

`standin-v2x2.onnx` is a static-batch ONNX export of the v2 value-net
architecture with SEEDED RANDOM weights -- no trained knowledge -- plus its
golden leaf vectors and a provenance record. It exists so the runtime spike
is reviewable in the public repo without the private lab.

This test pins the fixture contract itself, stdlib only:

  * the `.onnx` sha256 is the hash the provenance attests for both exports;
  * every golden leaf carries the fixed token shapes -- units 24x72 (+24
    mask), objs 6x12 (+6), terr 18x12, glob 16;
  * every `expected` value is finite and in [-1, 1] (the value head's tanh
    range), with two member lists of one value per leaf;
  * `static_batch` is 32 and neither JSON carries a private `/home/` path.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core-godot" / "tests" / "fixtures" / "onnx"
GOLDEN = FIXTURES / "golden_standin-v2x2.json"
PROVENANCE = FIXTURES / "provenance_standin-v2x2.json"
ONNX = FIXTURES / "standin-v2x2.onnx"

# The export contract mirrors `core/nml-core/src/tokens.rs:26-28`
# (N_UNITS=24, N_OBJ=6, N_TERR=18) and `:42-45` (F_U=72, F_O=12, F_T=12,
# F_G=16). A shape drift here is a red test, not a fixture edit.
N_UNITS, F_U = 24, 72
N_OBJ, F_O = 6, 12
N_TERR, F_T = 18, 12
F_G = 16
STATIC_BATCH = 32


def _load(name):
    return json.loads((FIXTURES / name).read_bytes())


def _rows(x, outer, inner):
    return isinstance(x, list) and len(x) == outer and all(
        isinstance(r, list) and len(r) == inner for r in x)


def test_standin_onnx_hash_and_public_paths():
    prov = _load("provenance_standin-v2x2.json")
    attested = {prov["runs"][tag]["raw_sha256"] for tag in ("run1", "run2")}
    assert attested == {hashlib.sha256(ONNX.read_bytes()).hexdigest()}
    for name in ("golden_standin-v2x2.json", "provenance_standin-v2x2.json"):
        assert b"/home/" not in (FIXTURES / name).read_bytes(), name


def test_standin_golden_shapes_and_expected_range():
    golden = _load("golden_standin-v2x2.json")
    assert golden["static_batch"] == STATIC_BATCH
    leaves = golden["leaves"]
    for leaf in leaves:
        assert _rows(leaf["units"], N_UNITS, F_U), leaf["source"]
        assert len(leaf["units_mask"]) == N_UNITS, leaf["source"]
        assert _rows(leaf["objs"], N_OBJ, F_O), leaf["source"]
        assert len(leaf["objs_mask"]) == N_OBJ, leaf["source"]
        assert _rows(leaf["terr"], N_TERR, F_T), leaf["source"]
        assert len(leaf["glob"]) == F_G, leaf["source"]
    expected = golden["expected"]
    members = expected["member_values"]
    assert len(members) == 2, "the stand-in ensemble has two members"
    assert len(expected["value"]) == len(leaves)
    for member in members:
        assert len(member) == len(leaves)
    for value in expected["value"] + [v for m in members for v in m]:
        assert math.isfinite(value)
        assert -1.0 <= value <= 1.0