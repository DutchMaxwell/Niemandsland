#!/usr/bin/env python3
"""Generate the Niemandsland biome battlemaps: one non-tiling, scale-locked, high-res
ground texture per biome via Gemini 3 Pro Image ("Nano Banana Pro"), sharpened and saved
as WebP.

Each battlemap is a SINGLE cohesive image authored for the standard 6x4 ft table (3:2),
so there is no visible tiling. Prompts lock the real-world scale (the frame covers ~1.8 x
1.2 m, every feature tiny) so ground detail matches 28-32 mm miniatures. The native 4K
render (~5056x3392) is upscaled 1.5x + unsharp-masked for crispness, then written as WebP.

Output -> assets/terrain/biomes/<biome>.webp  (git-ignored; delivered via R2, see
publish_biomes.py and docs/ASSET_DELIVERY.md).

Run with the model_forge venv (needs google-genai + Pillow + a Gemini key):
    cd tools/model_forge && ./venv/bin/python3 generate_battlemaps.py
    ./venv/bin/python3 generate_battlemaps.py --only frozen_tundra   # one biome
    ./venv/bin/python3 generate_battlemaps.py --force                # regenerate all

The key is read from .gemini_key (or the GEMINI_API_KEY / GOOGLE_API_KEY env var).
"""
from __future__ import annotations

import argparse
import io
import logging
import os
import sys
from pathlib import Path

from google import genai
from google.genai import types
from PIL import Image, ImageFilter

THIS_DIR: Path = Path(__file__).resolve().parent
GEMINI_KEY_FILE: Path = THIS_DIR / ".gemini_key"
OUT_DIR: Path = THIS_DIR.parent.parent / "assets" / "terrain" / "biomes"

# Image models in preference order: Nano Banana Pro (highest native res + flexible
# aspect), then the classic flash-image as a fallback for keys without Pro access.
MODELS: list[str] = ["gemini-3-pro-image", "gemini-2.5-flash-image"]
IMAGE_SIZES: list[str] = ["4K", "2K"]  # try the largest the model accepts first
ASPECT_RATIO: str = "3:2"              # matches the 6x4 ft reference table

# Crispness pass applied to the native render (interpolation + sharpen, no new detail).
UPSCALE_FACTOR: float = 1.5
UNSHARP = {"radius": 2.0, "percent": 120, "threshold": 2}
WEBP_QUALITY: int = 92

# Per-biome surface description. The shared template wraps these with the framing +
# scale lock; keep descriptions to fine, small, evenly-distributed features (no big rocks).
BIOMES: dict[str, str] = {
    "temperate_grassland": (
        "dense fine green meadow grass with small patches of bare brown dirt and mud, "
        "scattered tiny pebbles, and only occasional very small wildflowers"
    ),
    "arid_desert": (
        "fine golden desert sand with gentle small dune ripples, small patches of dry "
        "cracked clay earth, and sparsely scattered small weathered stones"
    ),
    "frozen_tundra": (
        "packed snow and pale blue ice with small patches of frozen dark soil and gravel, "
        "thin hairline cracks, light wind-swept drifts and a few small frost-covered pebbles"
    ),
    "volcanic_ash": (
        "fine black and grey volcanic ash and small cooled lava-rock fragments with thin "
        "glowing orange lava cracks and scattered small charred debris"
    ),
    "alien_jungle": (
        "fine exotic teal and violet low jungle vegetation and moss with small "
        "bioluminescent specks, thin twisting surface roots and scattered tiny glowing spores"
    ),
    "urban_ruins": (
        "cracked grey concrete and asphalt with fine rubble, small broken brick fragments, "
        "dust, gravel and scattered small debris"
    ),
}

PROMPT_TEMPLATE: str = (
    "Top-down orthographic ground texture for a tabletop wargame, representing a LARGE "
    "ground area of approximately 1.8 by 1.2 meters - a 6 by 4 foot battlefield - seen "
    "straight from directly overhead (nadir view, camera ~3 meters above looking straight "
    "down). Surface: {desc}. IMPORTANT SCALE: because the frame covers such a wide area, "
    "every feature must be SMALL and fine - individual elements are tiny, each no more than "
    "about one percent of the image width; render many hundreds of small, evenly distributed "
    "fine details instead of a few large ones. Absolutely no large objects, no big rocks or "
    "boulders, no oversized foreground elements. One single cohesive, non-repeating scene "
    "filling the entire 3:2 frame, with gentle large-scale variation. Photorealistic, "
    "extremely detailed, fine-grained, very high resolution. Even flat overhead lighting "
    "with no directional or baked shadows and uniform exposure. No miniatures, no figures, "
    "no grid lines, no text, no labels, no watermark, no border, no vignette."
)


def _load_key() -> str:
    if GEMINI_KEY_FILE.exists():
        key = GEMINI_KEY_FILE.read_text(encoding="utf-8").strip()
        if key:
            return key
    return os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY") or ""


def _generate(client: genai.Client, prompt: str, log: logging.Logger) -> bytes | None:
    """Generate one image, trying the preferred model + largest image size first."""
    for model in MODELS:
        for size in IMAGE_SIZES:
            try:
                cfg = types.GenerateContentConfig(
                    response_modalities=["IMAGE"],
                    image_config=types.ImageConfig(aspect_ratio=ASPECT_RATIO, image_size=size),
                )
                resp = client.models.generate_content(model=model, contents=[prompt], config=cfg)
                for cand in (resp.candidates or []):
                    for part in (cand.content.parts or []):
                        if getattr(part, "inline_data", None) and part.inline_data.data:
                            log.info("    rendered with %s @ %s/%s", model, size, ASPECT_RATIO)
                            return part.inline_data.data
            except Exception as exc:  # noqa: BLE001 - report and fall through to next option
                log.warning("    %s @ %s failed: %s", model, size, str(exc)[:160])
    return None


def _sharpen(raw: bytes) -> Image.Image:
    """Native render -> 1.5x Lanczos upscale + unsharp mask (crispness, not new detail)."""
    img = Image.open(io.BytesIO(raw)).convert("RGB")
    up = img.resize(
        (round(img.width * UPSCALE_FACTOR), round(img.height * UPSCALE_FACTOR)),
        Image.LANCZOS,
    )
    return up.filter(ImageFilter.UnsharpMask(**UNSHARP))


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate biome battlemap textures.")
    parser.add_argument("--only", nargs="*", default=None, help="only these biome keys")
    parser.add_argument("--force", action="store_true", help="regenerate existing files")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    log = logging.getLogger("battlemaps")

    key = _load_key()
    if not key:
        log.error("No Gemini key (set %s or GEMINI_API_KEY).", GEMINI_KEY_FILE.name)
        return 3
    client = genai.Client(api_key=key)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    keys: list[str] = args.only if args.only else list(BIOMES)
    failures = 0
    for biome in keys:
        if biome not in BIOMES:
            log.warning("unknown biome '%s' (known: %s)", biome, ", ".join(BIOMES))
            continue
        out_path = OUT_DIR / f"{biome}.webp"
        if out_path.exists() and not args.force:
            log.info("skip (exists): %s", out_path.name)
            continue
        log.info("generating %s ...", biome)
        raw = _generate(client, PROMPT_TEMPLATE.format(desc=BIOMES[biome]), log)
        if raw is None:
            log.error("  FAIL %s: no image produced", biome)
            failures += 1
            continue
        _sharpen(raw).save(out_path, "WEBP", quality=WEBP_QUALITY, method=6)
        log.info("  OK -> %s (%d KB)", out_path, out_path.stat().st_size // 1024)

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
