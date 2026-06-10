#!/usr/bin/env python3
"""Generate the shipping-container face textures for the blocker terrain pieces.

Mirrors generate_trees.py, minus the chroma key: each panel is ONE full-bleed Gemini
render of a container face (long corrugated side / door end / roof), in two weathered
colourways for table variety. The in-game blocker is a 6x3x2.5" box built from quads
wearing these faces (terrain_overlay.gd).

Output:  assets/terrain/props/containers/<name>.webp  (git-ignored, delivered via R2)
Manifest: assets/containers_manifest.json             (sha256 + size per panel)
Upload:  --upload-r2 pushes the panels to terrain-source/containers/.
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

from google import genai
from google.genai import types
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
OUT_DIR = ROOT / "assets" / "terrain" / "props" / "containers"
MANIFEST_PATH = ROOT / "assets" / "containers_manifest.json"
GEMINI_KEY_FILE = Path(__file__).resolve().parent / ".gemini_key"
R2_PREFIX = "terrain-source/containers"
BASE_URL = "https://assets.akesberg.de/terrain-source/containers"

MODELS = ["gemini-3-pro-image", "gemini-3-pro-image-preview"]
PANEL_WIDTH = 1024  # output width in px; height follows the face aspect

_BASE = (
    "Photorealistic flat orthographic texture of a weathered {colour} steel shipping "
    "container {face}, filling the entire frame edge to edge, photographed perfectly "
    "straight on with no perspective. {detail} Worn paint, rust streaks, scratches, "
    "faded stencil markings, grime along the edges. Even flat lighting, no shadows cast "
    "on the surface, no background visible, no text overlays."
)

# face name -> (aspect for Gemini, prompt face, prompt detail)
FACES = {
    "side": ("21:9", "long side wall",
             "Vertical corrugation across the whole wall, corner posts at both ends."),
    "end": ("5:4", "door end",
            "Two full-height cargo doors with vertical lock rods, hinges and door seals."),
    "top": ("16:9", "roof seen from directly above",
            "Lengthwise corrugated roof sheet with riveted seams, puddle stains and rust patches."),
}
COLOURS = {
    "red": "rust-red",
    "blue": "faded steel-blue",
}

# Biome themes: name prefix + prompt suffix layered onto every face render.
THEMES = {
    "": "",
    "tundra_": (
        " IN DEEP WINTER, HEAVILY SNOWED IN: a thick bright-white blanket of fresh snow "
        "covers the entire top edge and every ledge, large patches of snow and rime cling "
        "to the face itself, filling the corrugation grooves and recesses, icicles hang "
        "from protruding edges, heavy frost over the paint. The white snow must dominate "
        "and be clearly visible against the paint colour."
    ),
}

LOG = logging.getLogger("generate_containers")


def _load_key() -> str:
    if GEMINI_KEY_FILE.exists():
        key = GEMINI_KEY_FILE.read_text(encoding="utf-8").strip()
        if key:
            return key
    return os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""


def _generate(client: genai.Client, prompt: str, aspect: str) -> bytes | None:
    for model in MODELS:
        try:
            cfg = types.GenerateContentConfig(
                response_modalities=["IMAGE"],
                image_config=types.ImageConfig(aspect_ratio=aspect, image_size="2K"),
            )
            resp = client.models.generate_content(model=model, contents=[prompt], config=cfg)
            for cand in (resp.candidates or []):
                for part in (cand.content.parts or []):
                    data = getattr(getattr(part, "inline_data", None), "data", None)
                    if data:
                        LOG.info("rendered via %s (%s)", model, aspect)
                        return data
        except Exception as exc:  # noqa: BLE001 - best-effort across models
            LOG.warning("%s failed: %s", model, str(exc)[:120])
    return None


def _save(data: bytes, name: str) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    img = Image.open(io.BytesIO(data)).convert("RGB")
    scale = PANEL_WIDTH / img.width
    img = img.resize((PANEL_WIDTH, max(1, round(img.height * scale))), Image.LANCZOS)
    path = OUT_DIR / f"{name}.webp"
    img.save(path, "WEBP", quality=92, method=6)
    LOG.info("wrote %s (%dx%d)", path.relative_to(ROOT), img.width, img.height)
    return path


def write_manifest(paths: dict[str, Path]) -> None:
    # Merge into the existing manifest so a themed run keeps the other themes' panels.
    if MANIFEST_PATH.exists():
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    else:
        manifest = {"version": 1, "base_url": BASE_URL, "panels": {}}
    for name, path in sorted(paths.items()):
        data = path.read_bytes()
        sha = hashlib.sha256(data).hexdigest()
        manifest["panels"][name] = {
            # Version query busts the CDN edge cache on re-publish (stale-byte guard).
            "url": f"{name}.webp?v={sha[:8]}",
            "sha256": sha,
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
    ap.add_argument("--theme", choices=sorted(THEMES), default="",
                    help="biome theme prefix (e.g. tundra_ = snowed-in containers)")
    args = ap.parse_args(argv)

    theme_suffix = THEMES[args.theme]
    client: genai.Client | None = None
    paths: dict[str, Path] = {}
    for colour_key, colour in COLOURS.items():
        for face_key, (aspect, face, detail) in FACES.items():
            name = f"{args.theme}container_{colour_key}_{face_key}"
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
            data = _generate(client,
                    _BASE.format(colour=colour, face=face, detail=detail) + theme_suffix, aspect)
            if not data:
                LOG.error("Gemini returned no image for %s", name)
                return 1
            paths[name] = _save(data, name)

    write_manifest(paths)
    if args.upload_r2:
        return upload_r2(paths)
    return 0


if __name__ == "__main__":
    sys.exit(main())
