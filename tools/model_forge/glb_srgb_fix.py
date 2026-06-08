#!/usr/bin/env python3
"""Fix a TRELLIS GLB's baseColor: linear->sRGB encode (+ mild de-green). The canonical post-TRELLIS step.

TRELLIS writes the baked baseColor as LINEAR pixel data, but glTF viewers read baseColor as sRGB (spec),
so it is decoded twice and comes out systematically dark/muddy. The principled, lossless fix is to apply
the sRGB OETF to the stored pixels (NOT an arbitrary brighten). The curve is per-channel identical, so a
separate mild white-balance neutralises the bake's green tint. Geometry/UVs untouched (raw GLB rewrite).

  median brightness ~66/255 -> ~139 ; green cast removed. Validated on the Hive Lord (Blender + GIMP).

NOTE: Godot currently brightens TRELLIS materials at runtime (opr_army_manager._brighten_trellis_materials).
Once GLBs are sRGB-fixed at this stage, that runtime hook must be removed or in-game minis over-brighten.

Usage: glb_srgb_fix.py <in.glb> <out.glb> [wb=0.6]
"""
from __future__ import annotations

import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from glb_sharpen import _read_glb, _basecolor_image_index, _pad4


def linear_to_srgb(a: np.ndarray) -> np.ndarray:
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(np.clip(a, 0, None), 1 / 2.4) - 0.055)


def correct(pil: Image.Image, wb: float) -> Image.Image:
    a = np.asarray(pil.convert("RGB")).astype(np.float32) / 255.0
    srgb = np.clip(linear_to_srgb(a), 0, 1)
    if wb > 0:
        flat = srgb.reshape(-1, 3)
        chart = flat[flat.mean(1) >= (12 / 255)]
        mean = chart.mean(0) if len(chart) else flat.mean(0)
        gain = 1.0 + wb * (mean.mean() / np.clip(mean, 1e-3, None) - 1.0)
        srgb = np.clip(srgb * gain, 0, 1)
    return Image.fromarray((srgb * 255).astype("uint8"), "RGB")


def srgb_fix(inp: Path, outp: Path, wb: float = 0.6) -> None:
    gltf, binc = _read_glb(inp.read_bytes())
    bvs = gltf["bufferViews"]
    img_idx = _basecolor_image_index(gltf)
    bv_i = gltf["images"][img_idx]["bufferView"]
    v = bvs[bv_i]
    blob = binc[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
    pil = Image.open(io.BytesIO(blob)).convert("RGB")
    out_img = correct(pil, wb)
    buf = io.BytesIO()
    out_img.save(buf, "WEBP", quality=95, method=6)
    new_img = buf.getvalue()

    order = sorted(range(len(bvs)), key=lambda i: bvs[i].get("byteOffset", 0))
    new_bin = bytearray()
    for i in order:
        vv = bvs[i]
        s = vv.get("byteOffset", 0)
        data = new_img if i == bv_i else binc[s:s + vv["byteLength"]]
        vv["byteOffset"] = len(new_bin)
        new_bin += data
        new_bin += b"\x00" * ((4 - len(new_bin) % 4) % 4)
        vv["byteLength"] = len(data)
    gltf["buffers"][0]["byteLength"] = len(new_bin)
    gltf["buffers"][0].pop("uri", None)
    json_bytes = _pad4(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), b" ")
    bin_bytes = _pad4(bytes(new_bin))
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(json_bytes), b"JSON") + json_bytes
    out += struct.pack("<I4s", len(bin_bytes), b"BIN\x00") + bin_bytes
    outp.write_bytes(out)


def main() -> int:
    inp, outp = Path(sys.argv[1]), Path(sys.argv[2])
    wb = float(sys.argv[3]) if len(sys.argv) > 3 else 0.6
    srgb_fix(inp, outp, wb)
    print(f"srgb-fixed {inp.name} -> {outp.name} (wb={wb})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
