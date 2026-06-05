#!/usr/bin/env python3
"""Extract the baseColor texture from a GLB to PNG + report a sharpness metric (Laplacian variance).
   glb_tex.py <in.glb> <out.png>
"""
import json, struct, sys
from pathlib import Path
from PIL import Image
import numpy as np


def read_glb(path):
    data = Path(path).read_bytes()
    off, gltf, binc = 12, None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off); off += 8
        chunk = data[off:off+clen]; off += clen
        if ctype == b"JSON": gltf = json.loads(chunk)
        elif ctype == b"BIN\x00": binc = chunk
    return gltf, binc


def main():
    gltf, binc = read_glb(sys.argv[1])
    bvs = gltf.get("bufferViews", [])
    # baseColorTexture image index
    mat = gltf["materials"][0]
    tex = gltf["textures"][mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]]
    # EXT_texture_webp stores the image index in the extension, not in texture.source
    img_idx = tex.get("source")
    if img_idx is None:
        img_idx = tex["extensions"]["EXT_texture_webp"]["source"]
    img = gltf["images"][img_idx]
    v = bvs[img["bufferView"]]
    blob = binc[v.get("byteOffset", 0): v.get("byteOffset", 0)+v["byteLength"]]
    out = Path(sys.argv[2]); out.write_bytes(blob)
    im = Image.open(out).convert("RGB"); im.save(out.with_suffix(".png"))
    g = np.asarray(im.convert("L"), dtype=np.float64)
    # Laplacian variance = sharpness; higher = sharper
    lap = (g[1:-1,1:-1]*4 - g[:-2,1:-1] - g[2:,1:-1] - g[1:-1,:-2] - g[1:-1,2:])
    print(f"{out.name}: {im.size} mime={img.get('mimeType')} sharpness(lapvar)={lap.var():.1f}")


if __name__ == "__main__":
    main()
