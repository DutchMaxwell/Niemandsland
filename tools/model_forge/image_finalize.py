#!/usr/bin/env python3
"""Make a generated miniature image base-less + clean before review / 3D conversion.

The image model bakes a base under the figure as part of its product-shot style — a grey contact
shadow (humanoids) or a full scenic diorama base with rocks/rubble (creatures). TRELLIS reconstructs
either as a base, but Niemandsland always generates the base from the unit's base_size at spawn, so a
modelled base is wrong. Neither a generation negation (it anchors the base) nor a geometry cut (the
scenic base is thick and fused to the legs) reliably removes it — but a Gemini image EDIT does
("remove the base" is a valid edit instruction, unlike a negation). So we:

  1. edit the image to remove any base / ground / scenic diorama / cast shadow, and
  2. deshadow to flatten the background to pure white (deterministic backstop).

Used by batch_generate (after each image is generated) and the review re-roll, so the image the user
reviews IS the final base-less image that gets converted.
"""

from __future__ import annotations

from pathlib import Path
from typing import Callable

from deshadow import deshadow

BASE_REMOVAL_INSTRUCTION = (
    "Keep the miniature exactly as it is — identical figure/creature design, colours, pose, every "
    "detail and the same render style. The ONLY change: completely remove any base, plinth, scenic "
    "diorama, rocks, rubble, terrain, ground slab or cast shadow it stands on. The figure stands free "
    "on its own feet, legs or claws, presented as a clean isolated cut-out on a seamless pure white "
    "(#FFFFFF) background, with empty white space directly beneath it. Do not crop, move or alter the "
    "figure itself in any other way."
)


def finalize_image(image_path: Path, image_gen, *, log: Callable[[str], None] | None = None) -> bool:
    """Edit out any base, then deshadow — in place. Returns True if the base-removal edit succeeded.

    Never raises: on any failure it falls back to deshadow-only so generation is not blocked.
    """
    emit = log or (lambda _m: None)
    image_path = Path(image_path)
    edited = image_path.with_name(image_path.stem + "__nobase.png")
    edited_ok = False
    try:
        res = image_gen.generate(
            prompt=BASE_REMOVAL_INSTRUCTION,
            output_path=edited,
            edit_image_path=image_path,
        )
        edited_ok = bool(getattr(res, "success", False)) and edited.exists()
        if not edited_ok:
            emit(f"base-removal edit did not succeed for {image_path.name} — deshadow only")
    except Exception as exc:  # noqa: BLE001 — never block generation on this step
        emit(f"base-removal edit raised for {image_path.name} ({exc}) — deshadow only")

    src = edited if edited_ok else image_path
    try:
        deshadow(src, image_path)
    except Exception as exc:  # noqa: BLE001
        emit(f"deshadow failed for {image_path.name} ({exc})")
    if edited.exists():
        edited.unlink()
    return edited_ok
