#!/usr/bin/env python3
"""Sharpen a GLB's baseColor texture in place (pure Python, no Blender, geometry untouched).

TRELLIS bakes a soft texture (the baked UV atlas is much lower-frequency than the input image).
This extracts the baseColor image, applies an unsharp mask, re-encodes it at high quality, and rewrites
the GLB binary buffer with the new image — recomputing bufferView offsets so geometry/UVs are bit-for-bit
unchanged. No Blender round-trip (that re-encode is what washed the textures out).

Usage: glb_sharpen.py <in.glb> <out.glb> [radius=3] [percent=150]
"""
from __future__ import annotations

import io
import json
import struct
import sys
from pathlib import Path

from PIL import Image, ImageFilter


def _read_glb(data: bytes):
    off, gltf, binc = 12, None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == b"JSON":
            gltf = json.loads(chunk)
        elif ctype == b"BIN\x00":
            binc = chunk
    return gltf, binc


def _basecolor_image_index(gltf) -> int:
    mat = gltf["materials"][0]
    tex = gltf["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]
    idx = tex.get("source")
    if idx is None:
        idx = tex["extensions"]["EXT_texture_webp"]["source"]
    return idx


def _pad4(b: bytes, fill: bytes = b"\x00") -> bytes:
    return b + fill * ((4 - len(b) % 4) % 4)


def main() -> int:
    inp, outp = Path(sys.argv[1]), Path(sys.argv[2])
    radius = float(sys.argv[3]) if len(sys.argv) > 3 else 3.0
    percent = int(sys.argv[4]) if len(sys.argv) > 4 else 150

    gltf, binc = _read_glb(inp.read_bytes())
    bvs = gltf["bufferViews"]
    img_idx = _basecolor_image_index(gltf)
    img = gltf["images"][img_idx]
    bv_i = img["bufferView"]

    # extract -> unsharp -> re-encode (high quality, keep webp + dims)
    v = bvs[bv_i]
    start = v.get("byteOffset", 0)
    blob = binc[start:start + v["byteLength"]]
    pil = Image.open(io.BytesIO(blob)).convert("RGB")
    sharp = pil.filter(ImageFilter.UnsharpMask(radius=radius, percent=percent, threshold=2))
    buf = io.BytesIO()
    sharp.save(buf, "WEBP", quality=95, method=6)
    new_img = buf.getvalue()

    # rebuild the BIN buffer: copy every bufferView (replacing the baseColor image), 4-byte aligned,
    # assigning fresh sequential offsets so a size change can't corrupt other views.
    order = sorted(range(len(bvs)), key=lambda i: bvs[i].get("byteOffset", 0))
    new_bin = bytearray()
    for i in order:
        v = bvs[i]
        s = v.get("byteOffset", 0)
        data = new_img if i == bv_i else binc[s:s + v["byteLength"]]
        new_off = len(new_bin)
        new_bin += data
        new_bin += b"\x00" * ((4 - len(new_bin) % 4) % 4)
        v["byteOffset"] = new_off
        v["byteLength"] = len(data)

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
    print(f"sharpened {inp.name} -> {outp.name} (r={radius} pct={percent}, tex {pil.size})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
