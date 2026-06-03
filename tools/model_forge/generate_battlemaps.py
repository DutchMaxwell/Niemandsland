#!/usr/bin/env python3
"""Generate seamless tileable biome battlemap textures for the Niemandsland play
surface via Nano Banana (Gemini 2.5 Flash Image), reusing model_forge's ImageGenerator.

Output -> assets/terrain/biomes/<biome>.png

Run with the model_forge venv:
    cd tools/model_forge && ./venv/bin/python3 generate_battlemaps.py
    ./venv/bin/python3 generate_battlemaps.py --only temperate_grassland   # one biome
    ./venv/bin/python3 generate_battlemaps.py --force                       # regenerate all
"""
from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

THIS_DIR: Path = Path(__file__).resolve().parent
sys.path.insert(0, str(THIS_DIR))

from image_generator import ImageGenerator, ImageModel  # noqa: E402

GEMINI_KEY_FILE: Path = THIS_DIR / ".gemini_key"
OUT_DIR: Path = THIS_DIR.parent.parent / "assets" / "terrain" / "biomes"

# Standard map first, then five distinct biomes for variety.
BIOMES: dict[str, str] = {
    "temperate_grassland": (
        "lush temperate grassland with green grass, patches of bare brown dirt and "
        "mud, small scattered pebbles and a few tiny wildflowers"
    ),
    "arid_desert": (
        "arid desert of fine golden sand with gentle dune ripples, patches of dry "
        "cracked clay earth and scattered weathered rocks"
    ),
    "frozen_tundra": (
        "frozen tundra of packed snow and pale blue ice with patches of frozen dark "
        "soil, thin cracks and a few frost-covered rocks"
    ),
    "volcanic_ash": (
        "scorched volcanic ground of black and grey ash and cooled lava rock with "
        "thin glowing orange lava cracks and charred debris"
    ),
    "alien_jungle": (
        "dense alien jungle floor with exotic teal and violet vegetation, "
        "bioluminescent moss, twisting roots and strange glowing spores"
    ),
    "urban_ruins": (
        "ruined urban battlefield ground of cracked grey concrete and asphalt with "
        "rubble, broken bricks, dust and scattered debris"
    ),
}

PROMPT_TEMPLATE: str = (
    "Seamless tileable top-down orthographic ground texture for a tabletop wargaming "
    "battlemap: {desc}. Photorealistic, extremely detailed, high resolution, even flat "
    "overhead lighting with no directional or baked shadows and uniform exposure. The "
    "texture must tile seamlessly with no visible seams on any edge. No miniatures, no "
    "figures, no grid lines, no text, no labels, no watermark, no border, no vignette. "
    "Natural, varied colour and fine surface detail filling the entire frame."
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate biome battlemap textures.")
    parser.add_argument("--only", nargs="*", default=None, help="only these biome keys")
    parser.add_argument("--force", action="store_true", help="regenerate existing files")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    log = logging.getLogger("battlemaps")

    if not GEMINI_KEY_FILE.exists():
        log.error("Gemini key missing: %s", GEMINI_KEY_FILE)
        return 3
    gemini_key: str = GEMINI_KEY_FILE.read_text().strip()
    if not gemini_key:
        log.error("Gemini key empty: %s", GEMINI_KEY_FILE)
        return 3

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    generator = ImageGenerator(model=ImageModel.NANO_BANANA, gemini_api_key=gemini_key)

    keys: list[str] = args.only if args.only else list(BIOMES)
    failures: int = 0
    for key in keys:
        if key not in BIOMES:
            log.warning("unknown biome '%s' (known: %s)", key, ", ".join(BIOMES))
            continue
        out_path: Path = OUT_DIR / f"{key}.png"
        if out_path.exists() and not args.force:
            log.info("skip (exists): %s", out_path.name)
            continue
        prompt: str = PROMPT_TEMPLATE.format(desc=BIOMES[key])
        log.info("generating %s ...", key)
        result = generator.generate(prompt, out_path)
        if result.success:
            log.info("  OK -> %s", out_path)
        else:
            log.error("  FAIL %s: %s", key, result.error)
            failures += 1

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
