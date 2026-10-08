#!/usr/bin/env python3
"""The shipped value net as a Python leaf hook for the stage-0 lab driver (tree plan step 15).

`ShippedNet(repo)` loads assets/solo/brains/erlkoenig.onnx through onnxruntime (CPU, one intra-op
thread) and packs token dicts exactly as core/nml-core-godot/src/onnx_hook.rs does: the v1 window
(24 x 90) takes each core row as its first DESIGN_FIELDS columns, the vocab-3 window (32 x 91)
takes the row whole; more live units than the model has rows RAISES, a board is never truncated;
the last chunk is zero-padded to the static batch. `hook(side)` is the `leaf_value_fn[side]`
callable (`fn(leaves, side) -> list[float]`, weight 1.0 = the game's onnx_weight default) and
counts calls and leaves; `proof()` is the per-seat evidence that the net was really consulted.
Needs onnxruntime + numpy (the stage-0 venv), nothing from nml_core.
"""
import hashlib
import json
import os

DESIGN_FIELDS = 88
V1_UNITS = 90
MAX_DYNAMIC_BATCH = 128
TOKEN_TAIL = ",objs6x12,terr18x12,glob16,vocab1017,bag17"
BRAINS = os.path.join("assets", "solo", "brains")


class NetRefused(Exception):
    """The model file is not the artefact the stage-0 prereg names."""


class TooManyUnits(Exception):
    """A leaf has more live units than the model has rows (the Rust side declines the same way)."""


def _sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def _schema(text):
    head = text.removeprefix("units").removesuffix(TOKEN_TAIL)
    rows, width = head.split("x")
    return int(rows), int(width)


class ShippedNet:
    def __init__(self, repo, onnx=None, sha256=None, weight=1.0):
        import numpy as np
        import onnxruntime as ort
        self.np = np
        self.onnx = onnx or os.path.join(repo, BRAINS, "erlkoenig.onnx")
        if sha256 is None:
            with open(os.path.join(repo, BRAINS, "erlkoenig.json")) as f:
                sha256 = json.load(f)["sha256"]
        self.model_sha256 = _sha256(self.onnx)
        if self.model_sha256 != sha256:
            raise NetRefused("model sha256 %s != expected %s" % (self.model_sha256, sha256))
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 1
        opts.inter_op_num_threads = 1
        self.session = ort.InferenceSession(self.onnx, sess_options=opts, providers=["CPUExecutionProvider"])
        meta = self.session.get_modelmeta().custom_metadata_map
        self.rows, self.width = _schema(meta["nml.token_schema"])
        batch_dim = self.session.get_inputs()[0].shape[0]
        # A static export (the shipped model: 32) pads every call to its batch; a dynamic-batch export (batch axis a name or
        # None) packs exactly the live leaves, in chunks of at most MAX_DYNAMIC_BATCH.
        self.static_batch = batch_dim if isinstance(batch_dim, int) else None
        self.weight = float(weight)
        self.counts = {}

    def values(self, tokens):
        """One value per token dict, in order; the same packing as `OnnxHook::run_tokens`."""
        np, rows, width = self.np, self.rows, self.width
        cap = self.static_batch or MAX_DYNAMIC_BATCH
        out = []
        for start in range(0, len(tokens), cap):
            chunk = tokens[start:start + cap]
            wide = self.static_batch or len(chunk)
            for t in chunk:
                live = int(sum(1 for m in t["units_mask"] if m))
                if live > rows:
                    raise TooManyUnits("%d live units > %d model rows" % (live, rows))
            feed = {"units": np.zeros((wide, rows, width), np.float32), "units_mask": np.zeros((wide, rows), np.float32),
                    "objs": np.zeros((wide, 6, 12), np.float32), "objs_mask": np.zeros((wide, 6), np.float32),
                    "terr": np.zeros((wide, 18, 12), np.float32), "glob": np.zeros((wide, 16), np.float32)}
            take = DESIGN_FIELDS if width == V1_UNITS else width
            for i, t in enumerate(chunk):
                for j, row in enumerate(t["units"][:rows]):
                    feed["units"][i, j, :take] = row[:take]
                feed["units_mask"][i, :] = t["units_mask"][:rows]
                feed["objs"][i] = t["objs"]
                feed["objs_mask"][i] = t["objs_mask"]
                feed["terr"][i] = t["terr"]
                feed["glob"][i] = t["glob"]
            out.extend(float(v) for v in self.session.run(None, feed)[0][:len(chunk)])
        return out

    def hook(self, side):
        self.counts.setdefault(side, {"calls": 0, "leaves": 0})

        def fn(leaves, _side=None):
            values = self.values(leaves)
            self.counts[side]["calls"] += 1
            self.counts[side]["leaves"] += len(leaves)
            # the shipped game's pick = argmax(rs + w * net); w == 1.0 stays an untouched no-op
            return values if self.weight == 1.0 else [self.weight * v for v in values]
        return fn

    def proof(self):
        return dict({s: dict(c) for s, c in sorted(self.counts.items())}, model_sha256=self.model_sha256)
