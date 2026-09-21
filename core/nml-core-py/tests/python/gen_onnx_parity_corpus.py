#!/usr/bin/env python3
"""Build the ONNX<->tract parity corpus receipt: a deterministic pinned corpus
of >=10k token positions seeded from the public stand-in leaves, plus the
Python (onnxruntime) reference values the Rust tract side is compared against.

The corpus is pure integer arithmetic over the 60 golden leaves
(`golden_standin-v2x2.json`), so the Rust side (`tests/onnx_parity.rs`) rebuilds
it bit-for-bit; the receipt carries the sha256 of the exact float32 inputs the
reference ran on. Only the reference leg needs `onnxruntime` (CPU, one intra-op
thread, the 1.28.0 version the `ort` arm binds); corpus building and
`corpus_digest` are stdlib only and run inside the pytest suite.

Regenerate the checked-in receipt (seed and count are the defaults):

  python3 core/nml-core-py/tests/python/gen_onnx_parity_corpus.py \\
      --onnx core/nml-core-godot/tests/fixtures/onnx/standin-v2x2.onnx \\
      --out core/nml-core-godot/tests/fixtures/onnx/parity_pinned_10238.json

Corpus spec (v1):
  * positions 0..59 are golden leaves 0..59, in order, unchanged;
  * position p >= 60 picks base leaves a = splitmix64(seed ^ p) % 60 and
    b = splitmix64(seed ^ p ^ 0xA5A5A5A5A5A5A5A5) % 60;
  * each unit row (24), objective row (6) and terrain row (18) comes from a or
    b by bit 0 of splitmix64(seed ^ (p*K) ^ (block*64 + row)) with block 1/2/3;
    a unit/objective row's mask entry travels with its row;
  * glob (16) comes whole from a or b (block 4, row 0);
  * K = 0x9E3779B97F4A7C15, every step wrapping u64.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FIXTURES = REPO / "core" / "nml-core-godot" / "tests" / "fixtures" / "onnx"

SCHEMA = 1
SEED = 20260913
COUNT = 10238
TOLERANCE = 1e-5
STATIC_BATCH = 32
M64 = (1 << 64) - 1
K = 0x9E3779B97F4A7C15
MIX2 = 0xA5A5A5A5A5A5A5A5

INPUT_NAMES = ["units", "units_mask", "objs", "objs_mask", "terr", "glob"]
OUTPUT_NAMES = ["value", "member_values"]
SHAPES = {
    "units": (24, 90), "units_mask": (24,), "objs": (6, 12),
    "objs_mask": (6,), "terr": (18, 12), "glob": (16,),
}
SPEC = ("corpus v1: 0..59 = golden leaves in order; p>=60 mixes two base leaves "
        "a=splitmix64(seed^p)%60, b=splitmix64(seed^p^0xA5A5A5A5A5A5A5A5)%60, "
        "row source = bit0(splitmix64(seed^(p*0x9E3779B97F4A7C15)^(block*64+row))), "
        "blocks unit=1 obj=2 terr=3 glob=4 (glob whole-vector, row 0), masks "
        "travel with their row")


def splitmix64(x: int) -> int:
    x = (x + 0x9E3779B97F4A7C15) & M64
    z = x
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
    return z ^ (z >> 31)


def pick(p: int, block: int, row: int, seed: int = SEED) -> bool:
    return splitmix64(seed ^ ((p * K) & M64) ^ ((block * 64 + row) & M64)) & 1 == 0


def pair(p: int, seed: int = SEED):
    return splitmix64(seed ^ p) % 60, splitmix64(seed ^ p ^ MIX2) % 60


def _flat(leaf):
    return (sum(leaf["units"], []), list(leaf["units_mask"]),
            sum(leaf["objs"], []), list(leaf["objs_mask"]),
            sum(leaf["terr"], []), list(leaf["glob"]))


def load_leaves(golden_path: Path):
    """60 leaves, each six flat lists in `INPUT_NAMES` order."""
    return [_flat(leaf) for leaf in json.loads(golden_path.read_bytes())["leaves"]]


def row_of(leaves, p: int, seed: int = SEED):
    if p < len(leaves):
        return leaves[p]
    a, b = pair(p, seed)
    la, lb = leaves[a], leaves[b]
    units, units_mask, objs, objs_mask, terr, glob = [], [], [], [], [], []
    for r in range(24):
        src = la if pick(p, 1, r, seed) else lb
        units += src[0][r * 90:(r + 1) * 90]
        units_mask.append(src[1][r])
    for r in range(6):
        src = la if pick(p, 2, r, seed) else lb
        objs += src[2][r * 12:(r + 1) * 12]
        objs_mask.append(src[3][r])
    for r in range(18):
        src = la if pick(p, 3, r, seed) else lb
        terr += src[4][r * 12:(r + 1) * 12]
    glob = list((la if pick(p, 4, 0, seed) else lb)[5])
    return units, units_mask, objs, objs_mask, terr, glob


def corpus_digest(leaves, count: int, seed: int = SEED) -> str:
    """sha256 over the float32 inputs in row order, all six blocks, LE bytes."""
    h = hashlib.sha256()
    for p in range(count):
        for block in row_of(leaves, p, seed):
            h.update(struct.pack("<%df" % len(block), *block))
    return h.hexdigest()


def _run_reference(onnx_path: Path, leaves, count: int, seed: int):
    import numpy as np
    import onnxruntime as ort

    opts = ort.SessionOptions()
    opts.intra_op_num_threads = 1
    opts.inter_op_num_threads = 1
    session = ort.InferenceSession(str(onnx_path), sess_options=opts,
                                   providers=["CPUExecutionProvider"])
    names = [i.name for i in session.get_inputs()]
    if names != INPUT_NAMES:
        raise SystemExit("onnx_parity: input names %s != %s" % (names, INPUT_NAMES))
    value = np.zeros(count, dtype=np.float64)
    member = np.zeros((count, 2), dtype=np.float64)
    for start in range(0, count, STATIC_BATCH):
        chunk = [row_of(leaves, p, seed)
                 for p in range(start, min(start + STATIC_BATCH, count))]
        feed = {}
        for idx, name in enumerate(INPUT_NAMES):
            shape = (STATIC_BATCH,) + SHAPES[name]
            arr = np.zeros(shape, dtype=np.float32)
            for i, row in enumerate(chunk):
                arr[i] = np.asarray(row[idx], dtype=np.float32).reshape(SHAPES[name])
            feed[name] = arr
        out_value, out_member = session.run(OUTPUT_NAMES, feed)
        rows = len(chunk)
        value[start:start + rows] = np.asarray(out_value, dtype=np.float64)[:rows]
        member[start:start + rows] = np.asarray(
            out_member, dtype=np.float64).reshape(STATIC_BATCH, -1)[:rows]
    return value, member, ort.__version__


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--onnx", type=Path, default=FIXTURES / "standin-v2x2.onnx")
    ap.add_argument("--golden", type=Path, default=FIXTURES / "parity_base_standin-v2x2.json")
    ap.add_argument("--out", type=Path, default=FIXTURES / "parity_pinned_10238.json")
    ap.add_argument("--count", type=int, default=COUNT)
    ap.add_argument("--seed", type=int, default=SEED)
    args = ap.parse_args()
    if args.count < 10_000:
        raise SystemExit("onnx_parity: count %d < 10000" % args.count)

    leaves = load_leaves(args.golden)
    golden = json.loads(args.golden.read_bytes())
    golden_value = golden["expected"]["value"]
    golden_member = golden["expected"]["member_values"]
    digest = corpus_digest(leaves, args.count, args.seed)

    value, member, ort_version = _run_reference(args.onnx, leaves, args.count, args.seed)
    golden60 = max(abs(float(value[i]) - golden_value[i])
                   for i in range(len(golden_value)))
    golden60_member = max(abs(float(member[i, m]) - golden_member[m][i])
                          for i in range(len(golden_value)) for m in range(2))
    if max(golden60, golden60_member) > golden["tolerance"]:
        raise SystemExit("onnx_parity: reference does not reproduce the published "
                         "golden (%.3e)" % max(golden60, golden60_member))

    receipt = {
        "schema": SCHEMA,
        "label": "parity-pinned-%d" % args.count,
        "tolerance": golden["tolerance"],
        "static_batch": STATIC_BATCH,
        "inputs": INPUT_NAMES,
        "outputs": OUTPUT_NAMES,
        "corpus": {
            "count": args.count,
            "seed": args.seed,
            "base_fixture": args.golden.name,
            "base_leaves": len(leaves),
            "spec": SPEC,
            "input_sha256": digest,
            "input_bytes": args.count * (24 * 90 + 24 + 6 * 12 + 6 + 18 * 12 + 16) * 4,
        },
        "reference": {
            "runtime": "onnxruntime",
            "version": ort_version,
            "provider": "CPUExecutionProvider",
            "intra_op_threads": 1,
            "static_batch": STATIC_BATCH,
            "onnx_sha256": hashlib.sha256(args.onnx.read_bytes()).hexdigest(),
            "golden_sha256": hashlib.sha256(args.golden.read_bytes()).hexdigest(),
            "golden60_max_abs": golden60,
            "golden60_member_max_abs": golden60_member,
            "generated_by": "core/nml-core-py/tests/python/gen_onnx_parity_corpus.py",
        },
        "expected": {
            "value": [float(v) for v in value],
            "member_values": [[float(member[i, m]) for i in range(args.count)]
                              for m in range(2)],
        },
    }
    args.out.write_bytes(json.dumps(receipt, separators=(",", ":")).encode())
    print("ONNXPAR REFERENCE count=%d seed=%d input_sha256=%s ort=%s "
          "golden60_max_abs=%.3e golden60_member_max_abs=%.3e bytes=%d out=%s"
          % (args.count, args.seed, digest, ort_version, golden60, golden60_member,
             args.out.stat().st_size, args.out))


if __name__ == "__main__":
    main()
