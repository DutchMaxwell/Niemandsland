#!/usr/bin/env python3
"""Inspect a .glb: tris/verts, textures (count + resolution + format), materials/PBR, bbox.

Parses the binary glTF container directly (no heavy deps) so it works in any venv.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

# glTF accessor component type sizes / element counts
_COMP_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
_TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def _read_glb(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    magic, _ver, _len = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise ValueError("not a binary glTF")
    off, gltf, bin_chunk = 12, None, b""
    while off < len(data):
        clen, ctype = struct.unpack_from("<I4s", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == b"JSON":
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == b"BIN\x00":
            bin_chunk = chunk
    if gltf is None:
        raise ValueError("no JSON chunk")
    return gltf, bin_chunk


def _img_dims(blob: bytes) -> tuple[int, int, str] | None:
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", blob[16:24])
        return w, h, "png"
    if blob[:2] == b"\xff\xd8":  # jpeg
        i = 2
        while i < len(blob):
            if blob[i] != 0xFF:
                i += 1
                continue
            marker = blob[i + 1]
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                h, w = struct.unpack(">HH", blob[i + 5:i + 9])
                return w, h, "jpeg"
            seg = struct.unpack(">H", blob[i + 2:i + 4])[0]
            i += 2 + seg
        return None
    if blob[:4] == b"RIFF" and blob[8:12] == b"WEBP":
        fmt = blob[12:16]
        if fmt == b"VP8X":
            w = 1 + int.from_bytes(blob[24:27], "little")
            h = 1 + int.from_bytes(blob[27:30], "little")
            return w, h, "webp"
        if fmt == b"VP8 ":
            w = struct.unpack("<H", blob[26:28])[0] & 0x3FFF
            h = struct.unpack("<H", blob[28:30])[0] & 0x3FFF
            return w, h, "webp"
        if fmt == b"VP8L":
            b = blob[21:26]
            bits = int.from_bytes(b, "little")
            w = (bits & 0x3FFF) + 1
            h = ((bits >> 14) & 0x3FFF) + 1
            return w, h, "webp(lossless)"
    return None


def inspect(path: Path) -> dict:
    gltf, _ = _read_glb(path)
    accessors = gltf.get("accessors", [])
    meshes = gltf.get("meshes", [])

    tris = verts = 0
    for m in meshes:
        for prim in m.get("primitives", []):
            pos = prim.get("attributes", {}).get("POSITION")
            if pos is not None:
                verts += accessors[pos].get("count", 0)
            idx = prim.get("indices")
            if idx is not None:
                tris += accessors[idx].get("count", 0) // 3
            elif pos is not None:
                tris += accessors[pos].get("count", 0) // 3

    # textures
    images = gltf.get("images", [])
    bufviews = gltf.get("bufferViews", [])
    _gltf2, bin_chunk = _read_glb(path)
    tex_info = []
    for img in images:
        bv = img.get("bufferView")
        dims = None
        if bv is not None and bv < len(bufviews):
            v = bufviews[bv]
            start = v.get("byteOffset", 0)
            blob = bin_chunk[start:start + v.get("byteLength", 0)]
            dims = _img_dims(blob)
        tex_info.append({
            "mime": img.get("mimeType", "?"),
            "dims": f"{dims[0]}x{dims[1]}" if dims else "?",
            "fmt": dims[2] if dims else "?",
        })

    # materials / PBR
    mats = gltf.get("materials", [])
    pbr_channels = set()
    for mat in mats:
        pbr = mat.get("pbrMetallicRoughness", {})
        if "baseColorTexture" in pbr:
            pbr_channels.add("baseColor")
        if "metallicRoughnessTexture" in pbr:
            pbr_channels.add("metallicRoughness")
        if "normalTexture" in mat:
            pbr_channels.add("normal")
        if "occlusionTexture" in mat:
            pbr_channels.add("occlusion")
        if "emissiveTexture" in mat:
            pbr_channels.add("emissive")

    # bbox from POSITION accessor min/max
    bbox = None
    for a in accessors:
        if a.get("type") == "VEC3" and "min" in a and "max" in a and len(a["min"]) == 3:
            bbox = {"min": a["min"], "max": a["max"]}
            break
    dims_m = None
    if bbox:
        dims_m = [round(bbox["max"][i] - bbox["min"][i], 4) for i in range(3)]

    return {
        "file": path.name,
        "size_mb": round(path.stat().st_size / 1e6, 2),
        "triangles": tris,
        "vertices": verts,
        "meshes": len(meshes),
        "materials": len(mats),
        "pbr_channels": sorted(pbr_channels),
        "textures": tex_info,
        "extensions_used": gltf.get("extensionsUsed", []),
        "bbox_dims": dims_m,
    }


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        print(json.dumps(inspect(Path(arg)), indent=2))
