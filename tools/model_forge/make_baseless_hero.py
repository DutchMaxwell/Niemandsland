#!/usr/bin/env python3
"""Edit the approved Battle Brothers hero to remove its base — keep everything else (v5 style).

Image-edit (Nano Banana) on 01_hero_FINAL.png: preserve the exact figure/colours/pose/render, change
ONLY that the model sits on a base → isolated cut-out with empty space beneath the feet. Writes a NEW
file; never overwrites the approved hero.
"""

from __future__ import annotations

from pathlib import Path

from image_generator import ImageGenerator, ImageModel

THIS = Path(__file__).resolve().parent
SRC = THIS / "references" / "battle_brothers" / "01_hero_FINAL.png"
OUT = THIS / "engine_comparison" / "baseless" / "hero_noshadow.png"
KEY = (THIS / ".gemini_key").read_text(encoding="utf-8").strip()

# Edit mode: "erase the shadow" is a valid direct edit instruction (unlike a generation negation,
# which would anchor a shadow). The soft grey contact shadow is what TRELLIS reconstructs as a disc.
INSTRUCTION = (
    "Keep this exact character completely unchanged: identical heavy power-armour design, the same "
    "dark slate-grey armour with copper-bronze trim, the smooth teal-visor helmet, the trapezoidal "
    "angular shoulder plates, the sleek bullpup rifle, the deep maroon tabard, the same pose, the same "
    "heroic proportions, and the same clean semi-realistic miniature render style. "
    "Two changes only: "
    "(1) Re-light the figure with bright, even, flat, diffuse studio lighting (soft product-shot light). "
    "(2) Make the entire background a seamless pure white (#FFFFFF) that continues cleanly right up to "
    "and directly underneath the boot soles — fully erase the soft grey contact/drop shadow under and "
    "around the feet so the boots meet clean pure white with nothing at all beneath them. "
    "Present the figure as a floating isolated cut-out, full body, both boots fully visible."
)


def main() -> int:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    gen = ImageGenerator(model=ImageModel.NANO_BANANA, gemini_api_key=KEY)
    print(f"editing {SRC.name} -> {OUT}")
    res = gen.generate(prompt=INSTRUCTION, output_path=OUT, edit_image_path=SRC)
    print("success:", res.success, "| path:", res.image_path, "| err:", res.error or "-")
    return 0 if res.success else 1


if __name__ == "__main__":
    raise SystemExit(main())
