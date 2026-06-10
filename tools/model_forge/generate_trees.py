#!/usr/bin/env python3
"""Generate the deciduous-tree billboard panels for the grassland forests.

Mirrors generate_ruin_walls.py: each tree is ONE Gemini render of a single deciduous
tree on a flat pure-magenta backdrop; PIL chroma-keys the magenta to see-through alpha
(with an erosion pass that bites off the key fringe), crops to the silhouette, anchors
the trunk to the bottom edge and writes a lossless-alpha WebP. The in-game renderer
shows each tree as two crossed alpha-scissor quads (terrain_overlay.gd).

Output:  assets/terrain/props/trees/<name>.webp   (git-ignored, delivered via R2)
Manifest: assets/trees_manifest.json              (sha256 + size per panel)
Upload:  --upload-r2 pushes the panels to terrain-source/trees/<name>.webp using the
         same .r2_credentials as publish_manifest.py.

Cost note: one Gemini image per tree — regenerate sparingly (--force).
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
OUT_DIR = ROOT / "assets" / "terrain" / "props" / "trees"
MANIFEST_PATH = ROOT / "assets" / "trees_manifest.json"
GEMINI_KEY_FILE = Path(__file__).resolve().parent / ".gemini_key"
R2_PREFIX = "terrain-source/trees"
BASE_URL = "https://assets.akesberg.de/terrain-source/trees"

MODELS = ["gemini-3-pro-image", "gemini-3-pro-image-preview"]
PANEL_HEIGHT = 1024  # output height in px; width follows the silhouette

# One prompt per tree panel: distinct deciduous silhouettes (NO conifers/cones), full
# tree from trunk base to crown, flat magenta backdrop for the chroma key.
TREE_PROMPTS = {
    "tree_a": (
        "A single mature oak tree in full summer leaf, photographed straight on. Broad, "
        "irregular, organic crown of dense leaf clumps with small see-through gaps between "
        "the clumps, a few individual branches visible inside the crown, sturdy bark-textured "
        "trunk widening to a root flare at the very bottom edge of the frame. Natural greens "
        "with subtle colour variation. The ENTIRE background is FLAT PURE MAGENTA (255,0,255), "
        "including the gaps between leaf clumps. No ground, no shadow, no text. The whole tree "
        "is fully inside the frame and fills it."
    ),
    "tree_b": (
        "A single tall ash tree in full summer leaf, photographed straight on. Slightly "
        "asymmetric, loose organic crown made of several distinct leaf masses with open sky "
        "gaps between them, slender visible branches, a slim bark-textured trunk reaching the "
        "very bottom edge of the frame. Natural mid greens. The ENTIRE background is FLAT PURE "
        "MAGENTA (255,0,255), including the gaps inside the crown. No ground, no shadow, no "
        "text. The whole tree is fully inside the frame and fills it."
    ),
    "tree_c": (
        "A single compact linden tree in full summer leaf, photographed straight on. Rounded "
        "but clearly irregular, lumpy organic crown with ragged edges and a few see-through "
        "gaps, short sturdy bark-textured trunk reaching the very bottom edge of the frame. "
        "Rich warm greens. The ENTIRE background is FLAT PURE MAGENTA (255,0,255), including "
        "the gaps inside the crown. No ground, no shadow, no text. The whole tree is fully "
        "inside the frame and fills it."
    ),
    # Bird's-eye crowns: a horizontal "crown cap" quad hides the bare X of the two
    # crossed side quads when the table is viewed from above.
    "tree_a_top": (
        "Top-down bird's-eye view of the crown of a single mature oak tree in full summer "
        "leaf, seen from directly above. Broad irregular organic outline of dense leaf clumps "
        "with a few small see-through gaps, natural greens with subtle colour variation. The "
        "ENTIRE background is FLAT PURE MAGENTA (255,0,255), including the gaps. No ground, "
        "no shadow, no text. The crown is fully inside the frame and fills it."
    ),
    "tree_b_top": (
        "Top-down bird's-eye view of the crown of a single tall ash tree in full summer leaf, "
        "seen from directly above. Loose, slightly asymmetric organic outline of several "
        "distinct leaf masses with open gaps between them, natural mid greens. The ENTIRE "
        "background is FLAT PURE MAGENTA (255,0,255), including the gaps. No ground, no "
        "shadow, no text. The crown is fully inside the frame and fills it."
    ),
    "tree_c_top": (
        "Top-down bird's-eye view of the crown of a single compact linden tree in full summer "
        "leaf, seen from directly above. Rounded but clearly irregular, lumpy organic outline "
        "with ragged edges and a few see-through gaps, rich warm greens. The ENTIRE background "
        "is FLAT PURE MAGENTA (255,0,255), including the gaps. No ground, no shadow, no text. "
        "The crown is fully inside the frame and fills it."
    ),
    # Desert theme (arid_desert biome): cacti + a yucca instead of deciduous trees.
    "desert_tree_a": (
        "A single tall saguaro cactus, photographed straight on. Thick ribbed green trunk "
        "with two or three upward-curving arms at different heights, fine spines along the "
        "ribs, sun-bleached dusty green, the trunk base at the very bottom edge of the frame. "
        "The ENTIRE background is FLAT PURE MAGENTA (255,0,255). No ground, no shadow, no "
        "text. The whole cactus is fully inside the frame and fills it."
    ),
    "desert_tree_b": (
        "A tight natural cluster of organ-pipe cactus stems, photographed straight on: "
        "several ribbed green columns of clearly different heights rising from one base, "
        "fine pale spines, dusty desert green, the base at the very bottom edge of the "
        "frame. The ENTIRE background is FLAT PURE MAGENTA (255,0,255), including the gaps "
        "between the stems. No ground, no shadow, no text. The whole cluster is fully inside "
        "the frame and fills it."
    ),
    "desert_tree_c": (
        "A single joshua tree (yucca), photographed straight on: a short shaggy fibrous "
        "brown trunk forking into a few twisting branches, each ending in a spiky rosette of "
        "stiff green-grey blades, the trunk base at the very bottom edge of the frame. The "
        "ENTIRE background is FLAT PURE MAGENTA (255,0,255), including the gaps between the "
        "branches. No ground, no shadow, no text. The whole tree is fully inside the frame "
        "and fills it."
    ),
    "desert_tree_a_top": (
        "Top-down bird's-eye view of a tall saguaro cactus seen from directly above: the "
        "round ribbed trunk tip in the centre with two or three arm tips beside it, dusty "
        "green. The ENTIRE background is FLAT PURE MAGENTA (255,0,255). No ground, no "
        "shadow, no text. Fully inside the frame."
    ),
    "desert_tree_b_top": (
        "Top-down bird's-eye view of a tight cluster of organ-pipe cactus stems seen from "
        "directly above: several round ribbed column tips of different sizes packed "
        "together, dusty desert green. The ENTIRE background is FLAT PURE MAGENTA "
        "(255,0,255), including gaps between stems. No ground, no shadow, no text. Fully "
        "inside the frame."
    ),
    "desert_tree_c_top": (
        "Top-down bird's-eye view of a joshua tree (yucca) seen from directly above: a few "
        "spiky rosettes of stiff green-grey blades radiating from twisting branches. The "
        "ENTIRE background is FLAT PURE MAGENTA (255,0,255), including the gaps. No ground, "
        "no shadow, no text. Fully inside the frame."
    ),
    # Tundra theme (frozen_tundra biome): snow-laden conifers.
    "tundra_tree_a": (
        "A single tall mature spruce tree heavily laden with fresh snow, photographed "
        "straight on: layered dark-green conifer branches bending under thick white snow "
        "caps, a snow-dusted trunk reaching the very bottom edge of the frame, irregular "
        "natural silhouette with small gaps between the branch layers. The ENTIRE background "
        "is FLAT PURE MAGENTA (255,0,255), including the gaps. No ground, no shadow, no "
        "text. The whole tree is fully inside the frame and fills it."
    ),
    "tundra_tree_b": (
        "A single slender snow-covered fir tree, photographed straight on: a narrow conical "
        "conifer with short snow-capped branch tiers, dark green needles showing under the "
        "snow, slim trunk reaching the very bottom edge of the frame, slightly asymmetric "
        "natural outline. The ENTIRE background is FLAT PURE MAGENTA (255,0,255), including "
        "the gaps between branch tiers. No ground, no shadow, no text. The whole tree is "
        "fully inside the frame and fills it."
    ),
    "tundra_tree_c": (
        "A single small squat mountain pine in winter, photographed straight on: a short "
        "wide conifer with clearly separated dark-green branch tiers, each tier carrying a "
        "moderate cap of snow on top with plenty of dark green needles visible below, a "
        "sturdy visible brown trunk at the very bottom edge of the frame. Strong depth and "
        "shape readability, not buried in snow. The ENTIRE background is FLAT PURE MAGENTA "
        "(255,0,255), including the gaps between the branch tiers. No ground, no shadow, "
        "no text. The whole tree is fully inside the frame and fills it."
    ),
    "tundra_tree_a_top": (
        "Top-down bird's-eye view of a tall snow-laden spruce seen from directly above: a "
        "star of layered conifer branches radiating from the centre, thick white snow on "
        "top with dark green needles showing at the edges. The ENTIRE background is FLAT "
        "PURE MAGENTA (255,0,255), including the gaps. No ground, no shadow, no text. Fully "
        "inside the frame."
    ),
    "tundra_tree_b_top": (
        "Top-down bird's-eye view of a slender snow-covered fir seen from directly above: a "
        "small tight star of short branch tiers under fresh snow, dark green tips. The "
        "ENTIRE background is FLAT PURE MAGENTA (255,0,255), including the gaps. No ground, "
        "no shadow, no text. Fully inside the frame."
    ),
    "tundra_tree_c_top": (
        "Top-down bird's-eye view of a squat snow-laden mountain pine seen from directly "
        "above: a dense irregular clump of snowy conifer branches, white snow with green "
        "needle edges. The ENTIRE background is FLAT PURE MAGENTA (255,0,255), including "
        "the gaps. No ground, no shadow, no text. Fully inside the frame."
    ),
}

LOG = logging.getLogger("generate_trees")


# ==============================================================================
# GEMINI
# ==============================================================================

def _load_key() -> str:
    if GEMINI_KEY_FILE.exists():
        key = GEMINI_KEY_FILE.read_text(encoding="utf-8").strip()
        if key:
            return key
    return os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""


def _generate(client: genai.Client, prompt: str, aspects: list[str]) -> bytes | None:
    """Return raw image bytes for the first model/aspect that yields an image."""
    for model in MODELS:
        for aspect in aspects:
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
            except Exception as exc:  # noqa: BLE001 - best-effort across models/aspects
                LOG.warning("%s/%s failed: %s", model, aspect, str(exc)[:120])
    return None


# ==============================================================================
# CHROMA KEY -> RGBA PANEL
# ==============================================================================

def key_tree(data: bytes, anchor_bottom: bool = True) -> Image.Image:
    """Chroma-key the magenta backdrop to alpha, bite off the fringe, crop the silhouette.

    Side panels keep the trunk on the bottom edge (anchor_bottom); top-view crowns are
    cropped with an even pad on all sides.
    """
    rgb = np.asarray(Image.open(io.BytesIO(data)).convert("RGB"), dtype=np.uint8)
    r, g, b = rgb[:, :, 0].astype(int), rgb[:, :, 1].astype(int), rgb[:, :, 2].astype(int)
    magenta = (r > 150) & (g < 95) & (b > 150)

    # Opaque tree mask, eroded so the magenta key fringe around leaf edges disappears.
    tree_mask = Image.fromarray((~magenta * 255).astype(np.uint8), "L")
    tree_mask = tree_mask.filter(ImageFilter.MinFilter(3))
    mask = np.asarray(tree_mask) > 127

    # Despill: any remaining magenta tint on edge pixels pulls toward green foliage.
    spill = mask & (r > g) & (b > g)
    rgb = rgb.copy()
    avg = ((rgb[:, :, 0].astype(int) + rgb[:, :, 2].astype(int)) // 2).astype(np.uint8)
    rgb[:, :, 0] = np.where(spill, np.minimum(rgb[:, :, 0], rgb[:, :, 1]), rgb[:, :, 0])
    rgb[:, :, 2] = np.where(spill, np.minimum(rgb[:, :, 2], avg), rgb[:, :, 2])

    rgba = np.dstack([rgb, (mask * 255).astype(np.uint8)])
    img = Image.fromarray(rgba, "RGBA")

    # Crop to the silhouette with a tiny side/top pad; keep the trunk on the bottom edge.
    bbox = img.getbbox()
    if bbox is None:
        raise RuntimeError("chroma key removed the whole image (no tree found)")
    left, top, right, bottom = bbox
    pad_x = max(4, (right - left) // 50)
    pad_y = max(4, (bottom - top) // 50)
    bottom_edge = bottom if anchor_bottom else min(img.height, bottom + pad_y)
    img = img.crop((max(0, left - pad_x), max(0, top - pad_y),
                    min(img.width, right + pad_x), bottom_edge))

    scale = PANEL_HEIGHT / img.height
    return img.resize((max(1, round(img.width * scale)), PANEL_HEIGHT), Image.LANCZOS)


def _save(img: Image.Image, name: str) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{name}.webp"
    # Lossless keeps the hard alpha edges the scissor threshold relies on.
    img.save(path, "WEBP", lossless=True, method=6)
    LOG.info("wrote %s (%dx%d)", path.relative_to(ROOT), img.width, img.height)
    return path


# ==============================================================================
# MANIFEST + R2
# ==============================================================================

def write_manifest(paths: dict[str, Path]) -> None:
    # Merge into the existing manifest: keep panels of other themes AND the "models"
    # section maintained by generate_tree_models.py.
    if MANIFEST_PATH.exists():
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest.setdefault("panels", {})
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
    missing = [k for k in ("access_key", "secret_key", "endpoint", "bucket") if not cfg[k]]
    if missing:
        LOG.error("missing R2 config: %s", ", ".join(missing))
        return 2
    import boto3  # noqa: PLC0415
    from botocore.config import Config  # noqa: PLC0415

    s3 = boto3.client(
        "s3", endpoint_url=cfg["endpoint"],
        aws_access_key_id=cfg["access_key"], aws_secret_access_key=cfg["secret_key"],
        region_name="auto", config=Config(signature_version="s3v4"),
    )
    for name, path in sorted(paths.items()):
        key = f"{R2_PREFIX}/{name}.webp"
        s3.put_object(
            Bucket=cfg["bucket"], Key=key, Body=path.read_bytes(),
            ContentType="image/webp",
            # Named (mutable) keys: short edge cache; the runtime cache is sha-addressed.
            CacheControl="public, max-age=86400",
        )
        LOG.info("uploaded %s", key)
    return 0


# ==============================================================================
# MAIN
# ==============================================================================

def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--force", action="store_true",
                    help="re-render via Gemini even if a panel webp already exists")
    ap.add_argument("--upload-r2", action="store_true",
                    help="push the panels to R2 and refresh the manifest")
    ap.add_argument("--only", default="",
                    help="generate a single panel (e.g. tree_b)")
    args = ap.parse_args(argv)

    names = [args.only] if args.only else list(TREE_PROMPTS)
    client: genai.Client | None = None
    paths: dict[str, Path] = {}
    for name in names:
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
        is_top = name.endswith("_top")
        data = _generate(client, TREE_PROMPTS[name], ["1:1"] if is_top else ["3:4", "2:3", "1:1"])
        if not data:
            LOG.error("Gemini returned no image for %s", name)
            return 1
        paths[name] = _save(key_tree(data, not is_top), name)

    # Include any pre-existing panels not regenerated this run.
    for name in TREE_PROMPTS:
        path = OUT_DIR / f"{name}.webp"
        if name not in paths and path.exists():
            paths[name] = path

    write_manifest(paths)
    if args.upload_r2:
        return upload_r2(paths)
    return 0


if __name__ == "__main__":
    sys.exit(main())
