#!/usr/bin/env python3
"""Generate the minefield textures for the dangerous-terrain pieces (grassland).

Two panels, mirroring the trees/containers recipes:
- mine_top: bird's-eye anti-tank mine (pressure-plate disc), magenta chroma key ->
  keyed-alpha circle laid on top of an olive cylinder in-game.
- warning_sign: weathered rectangular minefield warning sign, full-bleed RGB, shown on
  a post at the field's corners.

Output:  assets/terrain/props/hazards/<name>.webp  (git-ignored, delivered via R2)
Manifest: assets/hazards_manifest.json
Upload:  --upload-r2 pushes the panels to terrain-source/hazards/.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import logging
import os
import sys
from pathlib import Path

import numpy as np
from google import genai
from google.genai import types
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent.parent
OUT_DIR = ROOT / "assets" / "terrain" / "props" / "hazards"
MANIFEST_PATH = ROOT / "assets" / "hazards_manifest.json"
GEMINI_KEY_FILE = Path(__file__).resolve().parent / ".gemini_key"
R2_PREFIX = "terrain-source/hazards"
BASE_URL = "https://assets.akesberg.de/terrain-source/hazards"

MODELS = ["gemini-3-pro-image", "gemini-3-pro-image-preview"]
PANEL_SIZE = 768  # px; both panels are small props

# name -> (prompt, keyed: chroma-key magenta to alpha?)
PANELS = {
    "mine_top": ((
        "Top-down bird's-eye view of a single round olive-drab anti-tank landmine, like a "
        "TM-62: a flat metal disc with a circular central pressure plate, radial seams, a "
        "carrying handle on the rim, worn dark olive paint with scratches and dust. Seen from "
        "directly above, perfectly centered. The ENTIRE background is FLAT PURE MAGENTA "
        "(255,0,255). Even flat lighting, no shadow, no text."
    ), True),
    "warning_sign": ((
        "Photorealistic flat orthographic texture of a weathered rectangular metal minefield "
        "warning sign filling the entire frame edge to edge: red border, white background, a "
        "black skull and crossbones above the stencil text 'MINES', rust streaks, bullet "
        "dents, faded paint. Photographed perfectly straight on, even flat lighting, no "
        "shadow, no background visible."
    ), False),
}

LOG = logging.getLogger("generate_hazards")


def _load_key() -> str:
    if GEMINI_KEY_FILE.exists():
        key = GEMINI_KEY_FILE.read_text(encoding="utf-8").strip()
        if key:
            return key
    return os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""


def _generate(client: genai.Client, prompt: str) -> bytes | None:
    for model in MODELS:
        try:
            cfg = types.GenerateContentConfig(
                response_modalities=["IMAGE"],
                image_config=types.ImageConfig(aspect_ratio="1:1", image_size="1K"),
            )
            resp = client.models.generate_content(model=model, contents=[prompt], config=cfg)
            for cand in (resp.candidates or []):
                for part in (cand.content.parts or []):
                    data = getattr(getattr(part, "inline_data", None), "data", None)
                    if data:
                        LOG.info("rendered via %s", model)
                        return data
        except Exception as exc:  # noqa: BLE001
            LOG.warning("%s failed: %s", model, str(exc)[:120])
    return None


def _key_magenta(data: bytes) -> Image.Image:
    """Chroma-key the magenta backdrop to alpha and crop to the subject (trees recipe)."""
    rgb = np.asarray(Image.open(io.BytesIO(data)).convert("RGB"), dtype=np.uint8)
    r, g, b = rgb[:, :, 0].astype(int), rgb[:, :, 1].astype(int), rgb[:, :, 2].astype(int)
    magenta = (r > 150) & (g < 95) & (b > 150)
    mask_img = Image.fromarray((~magenta * 255).astype(np.uint8), "L")
    mask_img = mask_img.filter(ImageFilter.MinFilter(3))
    mask = np.asarray(mask_img) > 127
    rgba = np.dstack([rgb, (mask * 255).astype(np.uint8)])
    rgba[~mask] = 0
    img = Image.fromarray(rgba, "RGBA")
    bbox = img.getbbox()
    if bbox is None:
        raise RuntimeError("chroma key removed the whole image")
    return img.crop(bbox)


def _save(img: Image.Image, name: str) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    scale = PANEL_SIZE / max(img.width, img.height)
    img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))),
                     Image.LANCZOS)
    path = OUT_DIR / f"{name}.webp"
    if img.mode == "RGBA":
        img.save(path, "WEBP", lossless=True, method=6)
    else:
        img.save(path, "WEBP", quality=92, method=6)
    LOG.info("wrote %s (%dx%d)", path.relative_to(ROOT), img.width, img.height)
    return path


def write_manifest(paths: dict[str, Path]) -> None:
    manifest = {"version": 1, "base_url": BASE_URL, "panels": {}}
    for name, path in sorted(paths.items()):
        data = path.read_bytes()
        manifest["panels"][name] = {
            "url": f"{name}.webp",
            "sha256": hashlib.sha256(data).hexdigest(),
            "size": len(data),
        }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    LOG.info("wrote %s (%d panels)", MANIFEST_PATH.relative_to(ROOT), len(paths))


def upload_r2(paths: dict[str, Path]) -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from publish_manifest import _load_r2_config  # noqa: PLC0415

    cfg = _load_r2_config("", "")
    if any(not cfg[k] for k in ("access_key", "secret_key", "endpoint", "bucket")):
        LOG.error("missing R2 config")
        return 2
    import boto3  # noqa: PLC0415
    from botocore.config import Config  # noqa: PLC0415

    s3 = boto3.client(
        "s3", endpoint_url=cfg["endpoint"],
        aws_access_key_id=cfg["access_key"], aws_secret_access_key=cfg["secret_key"],
        region_name="auto", config=Config(signature_version="s3v4"),
    )
    for name, path in sorted(paths.items()):
        s3.put_object(
            Bucket=cfg["bucket"], Key=f"{R2_PREFIX}/{name}.webp", Body=path.read_bytes(),
            ContentType="image/webp",
            CacheControl="public, max-age=86400",
        )
        LOG.info("uploaded %s/%s.webp", R2_PREFIX, name)
    return 0


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--force", action="store_true", help="re-render even if a panel exists")
    ap.add_argument("--upload-r2", action="store_true", help="push panels to R2 + manifest")
    args = ap.parse_args(argv)

    client: genai.Client | None = None
    paths: dict[str, Path] = {}
    for name, (prompt, keyed) in PANELS.items():
        path = OUT_DIR / f"{name}.webp"
        if path.exists() and not args.force:
            LOG.info("skip (exists): %s", path.relative_to(ROOT))
            paths[name] = path
            continue
        if client is None:
            key = _load_key()
            if not key:
                LOG.error("no Gemini key (.gemini_key or GEMINI_API_KEY)")
                return 2
            client = genai.Client(api_key=key)
        data = _generate(client, prompt)
        if not data:
            LOG.error("Gemini returned no image for %s", name)
            return 1
        img = _key_magenta(data) if keyed else Image.open(io.BytesIO(data)).convert("RGB")
        paths[name] = _save(img, name)

    write_manifest(paths)
    if args.upload_r2:
        return upload_r2(paths)
    return 0


if __name__ == "__main__":
    sys.exit(main())
