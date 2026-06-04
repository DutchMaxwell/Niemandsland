# Multi-view TRELLIS patch (prepared, NOT yet deployed)

**What:** adds a `/multiimage_to_3d` API endpoint to your `DutchyMaxwell/TRELLIS.2` HF Space so TRELLIS
can reconstruct from **several views of the same model (front + back, optionally sides)** instead of one
front view. The back is otherwise hallucinated — multi-view gives it real data, which should improve
quality, especially for thin limbs/blades (the weak spot on the current single-view Alien Hives models).

**Why it's not deployed:** patching the live shared Space (the whole pipeline depends on it) was blocked
for an unattended overnight run — correctly. Deploy it yourself when you can watch it.

## Deploy / revert

```bash
cd tools/model_forge
./venv/bin/python3 multiview_patch/deploy_multiview.py            # deploy + restart + verify endpoints
./venv/bin/python3 multiview_patch/deploy_multiview.py --revert   # roll back to the originals
```

It is **idempotent** and **backward-compatible**: single-image generation is byte-identical behaviour
(a list of one image), so `image_to_3d` and the current Alien Hives pipeline keep working. The script
syntax-checks before upload, restarts the Space, and verifies both `image_to_3d` and `multiimage_to_3d`
endpoints exist. Pristine originals are saved here (`*.orig`) for revert.

## The two changes (small, surgical)
1. `trellis2/pipelines/trellis2_image_to_3d.py` — `run()` now forwards a **list** of images to
   `get_cond()` (which already accepts `list[Image]`) instead of hardcoding `[image]`. Single image →
   `[image]` (unchanged).
2. `app.py` — adds a `multiimage_to_3d(...)` function that **reuses `image_to_3d` unchanged** by passing
   the image list through, wired to a hidden Gallery with `api_name="multiimage_to_3d"`.

## Using it from the pipeline (after deploy)
Per unit: generate the front image (as today) **and** a consistent back view (Gemini edit:
"show this exact character from directly behind…" — validated to be consistent), preprocess both
(bg-removal), then call `/multiimage_to_3d` with `[front, back]` + the same sampler params, then
`/extract_glb` as usual. Wiring this into `trellis_bridge` is a follow-up once you've confirmed the
quality gain is worth the extra back-view generation per unit.

## Caveat — uncertain payoff
TRELLIS.2's multi-image path is **undocumented** (v1 had a dedicated multi-image algorithm; v2 just
feeds the list to the conditioning model). It is feasible, but whether the quality clearly improves
needs a real A/B test (front+back vs front-only on the same unit) after deploy. Test on 1–2 units
before committing the whole faction to it.
