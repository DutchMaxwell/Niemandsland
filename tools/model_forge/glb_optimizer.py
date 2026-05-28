"""
GLB-Optimierung fuer OpenTTS-Tabletop-Minis
============================================

TRELLIS produziert GLBs mit ~500k Tris und 4096^2 Texturen (~20MB pro Mini).
Fuer 16mm-Wargaming-Minis ist das ~10x ueberdimensioniert. Diese Pipeline
dezimiert das Mesh und verkleinert die Texturen, ohne sichtbaren Qualitaets-
verlust auf typischer Spielfeld-Distanz.

Workflow pro GLB:
    1. gltfpack -si 0.1 -noq  (Mesh-Decimation auf ~10%, KEINE Quantisierung)
    2. Pillow Texture-Resize auf max 1024^2, WebP Q85

Wichtig: -noq verhindert die KHR_mesh_quantization-Extension. Godot 4.6.1
(Flatpak) lehnt GLBs mit dieser Extension als required ab.

Typische Ergebnisse:
    19 MB -> 2.5 MB (-87%)
    854 Units (vorher ~16 GB) -> ~2 GB Repository-Footprint
"""

from __future__ import annotations

import io
import json
import platform
import shutil
import struct
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image


# =============================================================================
# KONSTANTEN
# =============================================================================

DEFAULT_SIMPLIFY_RATIO: float = 0.1
DEFAULT_TEXTURE_MAX_DIM: int = 1024
DEFAULT_WEBP_QUALITY: int = 85

GLB_MAGIC: bytes = b"glTF"
GLB_CHUNK_JSON: int = 0x4E4F534A  # "JSON"
GLB_CHUNK_BIN: int = 0x004E4942   # "BIN\0"


# =============================================================================
# DATENKLASSEN
# =============================================================================

@dataclass
class OptimizeResult:
    """Ergebnis einer GLB-Optimierung."""

    success: bool
    input_bytes: int
    output_bytes: int
    error: str = ""

    @property
    def reduction_percent(self) -> float:
        if self.input_bytes == 0:
            return 0.0
        return (1.0 - self.output_bytes / self.input_bytes) * 100.0


# =============================================================================
# GLTFPACK-LOOKUP
# =============================================================================

def find_gltfpack() -> Path | None:
    """
    Sucht das gltfpack-Binary an mehreren Stellen:
        1. tools/model_forge/bin/gltfpack-{platform}
        2. tools/model_forge/bin/gltfpack
        3. PATH (which gltfpack)

    Returns Path oder None wenn nicht gefunden.
    """
    bin_dir = Path(__file__).parent / "bin"
    suffix = ".exe" if platform.system() == "Windows" else ""
    platform_name = {
        "Linux": "linux",
        "Darwin": "macos",
        "Windows": "windows",
    }.get(platform.system(), "")

    candidates = [
        bin_dir / f"gltfpack-{platform_name}{suffix}",
        bin_dir / f"gltfpack{suffix}",
    ]
    for c in candidates:
        if c.exists() and c.is_file():
            return c

    on_path = shutil.which("gltfpack")
    if on_path:
        return Path(on_path)

    return None


# =============================================================================
# GLB-PARSING (NUR JSON+BIN-CHUNKS, KEINE EXTERNE LIB NOETIG)
# =============================================================================

def _parse_glb(path: Path) -> tuple[dict, bytes]:
    """Parst eine GLB in (gltf_json_dict, bin_chunk_bytes)."""
    data = path.read_bytes()
    magic, _version, length = struct.unpack("<4sII", data[:12])
    if magic != GLB_MAGIC:
        raise ValueError(f"Keine gueltige GLB-Datei: {path}")

    offset = 12
    json_data: bytes | None = None
    bin_data: bytes = b""
    while offset < length:
        clen, ctype = struct.unpack("<II", data[offset:offset + 8])
        chunk_data = data[offset + 8:offset + 8 + clen]
        if ctype == GLB_CHUNK_JSON:
            json_data = chunk_data
        elif ctype == GLB_CHUNK_BIN:
            bin_data = chunk_data
        offset += 8 + clen

    if json_data is None:
        raise ValueError(f"GLB ohne JSON-Chunk: {path}")
    return json.loads(json_data.decode("utf-8")), bin_data


def _write_glb(gltf: dict, bin_data: bytes, out_path: Path) -> None:
    """Schreibt eine GLB aus gltf_dict + bin_bytes mit korrektem Padding."""
    json_str = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_str) % 4 != 0:
        json_str += b" "
    bin_padded = bytearray(bin_data)
    while len(bin_padded) % 4 != 0:
        bin_padded.append(0)

    total_len = 12 + 8 + len(json_str) + 8 + len(bin_padded)
    with out_path.open("wb") as f:
        f.write(struct.pack("<4sII", GLB_MAGIC, 2, total_len))
        f.write(struct.pack("<II", len(json_str), GLB_CHUNK_JSON))
        f.write(json_str)
        f.write(struct.pack("<II", len(bin_padded), GLB_CHUNK_BIN))
        f.write(bytes(bin_padded))


# =============================================================================
# TEXTURE-RESIZE
# =============================================================================

def _downscale_textures(
    in_path: Path,
    out_path: Path,
    max_dim: int,
    quality: int,
) -> None:
    """
    Liest GLB, skaliert alle eingebetteten Bilder (PNG/JPEG/WebP) auf max_dim
    Pixel maximale Kantenlaenge runter, kodiert als WebP und schreibt eine
    neue GLB mit korrigierten BufferViews.
    """
    gltf, bin_data = _parse_glb(in_path)
    replacements: dict[int, bytes] = {}

    for img in gltf.get("images", []):
        bv_idx = img.get("bufferView")
        if bv_idx is None:
            continue
        bv = gltf["bufferViews"][bv_idx]
        img_bytes = bytes(bin_data[bv["byteOffset"]:bv["byteOffset"] + bv["byteLength"]])

        try:
            pil_img = Image.open(io.BytesIO(img_bytes))
        except Exception:
            continue

        if max(pil_img.size) > max_dim:
            ratio = max_dim / max(pil_img.size)
            new_size = (int(pil_img.size[0] * ratio), int(pil_img.size[1] * ratio))
            pil_img = pil_img.resize(new_size, Image.LANCZOS)

        buf = io.BytesIO()
        pil_img.save(buf, format="WEBP", quality=quality, method=6)
        replacements[bv_idx] = buf.getvalue()
        img["mimeType"] = "image/webp"

    new_bin = bytearray()
    new_buffer_views: list[dict] = []
    for bv_idx, bv in enumerate(gltf["bufferViews"]):
        offset = len(new_bin)
        new_data = replacements.get(
            bv_idx,
            bytes(bin_data[bv["byteOffset"]:bv["byteOffset"] + bv["byteLength"]]),
        )
        new_bin.extend(new_data)
        while len(new_bin) % 4 != 0:
            new_bin.append(0)
        new_bv = dict(bv)
        new_bv["byteOffset"] = offset
        new_bv["byteLength"] = len(new_data)
        new_buffer_views.append(new_bv)

    gltf["bufferViews"] = new_buffer_views
    gltf["buffers"][0]["byteLength"] = len(new_bin)
    _write_glb(gltf, bytes(new_bin), out_path)


# =============================================================================
# OEFFENTLICHE API
# =============================================================================

def optimize_glb(
    input_path: Path,
    output_path: Path,
    *,
    simplify_ratio: float = DEFAULT_SIMPLIFY_RATIO,
    texture_max_dim: int = DEFAULT_TEXTURE_MAX_DIM,
    webp_quality: int = DEFAULT_WEBP_QUALITY,
) -> OptimizeResult:
    """
    Optimiert eine GLB-Datei: Mesh-Decimation + Texture-Downscale.

    Args:
        input_path: Quell-GLB
        output_path: Ziel-GLB (wird ueberschrieben). Darf gleich input_path sein.
        simplify_ratio: gltfpack -si Wert (0.1 = 10% der Tris behalten)
        texture_max_dim: Maximale Texture-Kantenlaenge in Pixeln
        webp_quality: WebP-Encode-Quality (0-100, 85 = sauberer Kompromiss)

    Returns:
        OptimizeResult mit Erfolg + Vorher/Nachher-Bytes
    """
    if not input_path.exists():
        return OptimizeResult(False, 0, 0, f"Eingabe-Datei nicht gefunden: {input_path}")

    input_bytes = input_path.stat().st_size

    gltfpack = find_gltfpack()
    if gltfpack is None:
        return OptimizeResult(
            False,
            input_bytes,
            input_bytes,
            "gltfpack nicht gefunden (suche in tools/model_forge/bin/ und PATH)",
        )

    # gltfpack erwartet Input mit .glb/.gltf/.obj-Endung. Wenn nicht der Fall,
    # kopieren wir das Original nach Tempfile mit korrekter Endung.
    tmp_input = output_path.parent / (output_path.stem + ".tmp-input.glb")
    tmp_intermediate = output_path.parent / (output_path.stem + ".tmp-decimated.glb")

    try:
        if input_path.suffix.lower() != ".glb":
            shutil.copy2(input_path, tmp_input)
            gltfpack_input = tmp_input
        else:
            gltfpack_input = input_path

        # Schritt 1: Mesh-Decimation, KEINE Quantisierung (-noq fuer Godot-Kompatibilitaet)
        result = subprocess.run(
            [
                str(gltfpack),
                "-i", str(gltfpack_input),
                "-o", str(tmp_intermediate),
                "-si", str(simplify_ratio),
                "-noq",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return OptimizeResult(
                False,
                input_bytes,
                input_bytes,
                f"gltfpack fehlgeschlagen: {result.stderr.strip() or result.stdout.strip()}",
            )
        if not tmp_intermediate.exists():
            return OptimizeResult(
                False,
                input_bytes,
                input_bytes,
                "gltfpack lief durch, aber Ausgabe-Datei fehlt",
            )

        # Schritt 2: Texture-Downscale
        _downscale_textures(tmp_intermediate, output_path, texture_max_dim, webp_quality)

    finally:
        for tmp in (tmp_input, tmp_intermediate):
            if tmp.exists() and tmp != output_path and tmp != input_path:
                tmp.unlink(missing_ok=True)

    output_bytes = output_path.stat().st_size if output_path.exists() else 0
    return OptimizeResult(True, input_bytes, output_bytes)


# =============================================================================
# CLI-ENTRY (fuer Tests)
# =============================================================================

def _cli() -> None:
    if len(sys.argv) < 3:
        print("Usage: python glb_optimizer.py <input.glb> <output.glb>", file=sys.stderr)
        sys.exit(2)
    res = optimize_glb(Path(sys.argv[1]), Path(sys.argv[2]))
    print(
        f"in={res.input_bytes/1024/1024:.2f} MB  "
        f"out={res.output_bytes/1024/1024:.2f} MB  "
        f"reduction={res.reduction_percent:.1f}%"
    )
    if not res.success:
        print(f"ERROR: {res.error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    _cli()
