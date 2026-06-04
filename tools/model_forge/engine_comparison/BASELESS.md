# Base-less miniatures — root cause & fix

**Guideline:** Niemandsland miniatures must never carry their own base; the game generates the base
from the unit's `base_size` at spawn. But TRELLIS kept reconstructing a flat disc base under the
figure. This documents why, and the validated fix.

## Root cause — a contact shadow in the input image (not TRELLIS, not the pose)

The image model (Nano Banana) renders a soft **grey contact/drop shadow** on the ground under the
figure as part of its "miniature product shot" style. TRELLIS's background removal keeps that grey
shadow (it is not pure white, and it touches the figure), so TRELLIS sees a flat grey blob under the
boots and **reconstructs it as a disc base**.

Evidence (measured, bottom-of-model width vs full width — a disc is as wide as the model, feet are
narrower):

| Input image | under-boot shadow | TRELLIS bottom-bin width | result |
|---|---|---|---|
| with shadow (`hero_baseless.png`) | 13% grey pixels | 0.80 (vs 0.49 above) → **disc** | base ✗ |
| shadow removed (`hero_clean.png`) | 0% (pure white) | 0.51 (vs 0.49 above) → **just feet** | **base-less ✓** |

Prompt-only attempts to suppress the shadow (flat-lighting wording, "erase the shadow" edit
instruction) did **not** work — the model bakes the shadow in regardless. The fix has to be
deterministic.

## The fix — two layers

1. **`deshadow.py` (image stage, primary).** Before TRELLIS, flood-fill the background **and** the
   contact shadow to pure white from the image borders: the shadow is light-grey and connected to the
   white background, while the figure is a separate, much darker island — so the fill whitens bg +
   shadow and stops at the figure. Result: 0% residual shadow, figure 100% intact (the dark slate
   armour is well below the white threshold). Wired into `batch_generate.py` right before
   `convert_image_to_glb`. **This alone makes TRELLIS output base-less** (validated above).
2. **`glb_debase.py` (geometry stage, safety net).** Headless Blender. Detects a base disc as the
   bottom run of height-slices much wider than the slice above, and cuts it off. 4K-PBR WebP textures
   are preserved (`EXT_texture_webp`, baseColor + metallicRoughness intact). Use only if a disc ever
   slips through the image-stage fix:
   `blender -b -P glb_debase.py -- in.glb out.glb`

Also: the per-faction prompt lighting line was changed from "dramatic lighting from upper left" to
bright even flat studio lighting, which weakens the shadow and helps `deshadow` — but `deshadow` is
what guarantees the result.

## Files
- `baseless/hero_clean.png` — the shadow-free, base-less input (v5 design preserved, flat-lit).
- `trellis_clean/preview.png` — the resulting **base-less** model.
- `trellis_baseless/preview.png` — the same hero **with** the shadow → disc base (the before).
