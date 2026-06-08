I now have everything I need to map recommendations precisely onto the real pipeline. Key findings from the code:

- `tex_slat_guidance_strength=1.0`, `tex_slat_sampling_steps=12` are hard-coded in `trellis_core.py` (lines 272-275) — these are the weak defaults the research flagged.
- `RESOLUTION="1536"`, `TEXTURE_SIZE=4096` are already maxed.
- Godot already brightens dark textures at runtime (`_brighten_trellis_materials`) — this is a critical double-correction risk.
- `deshadow.py` whitens background but does NOT delight/white-balance the figure.
- `glb_sharpen.py` exists (unsharp), `glb_tex.py` measures sharpness — but no sRGB/white-balance/CLAHE post-step exists yet.

Here is the synthesized plan.

---

# Model Forge — TRELLIS Texture-Quality Action Plan

Prioritized for **our actual pipeline** (`tools/model_forge/`). I cross-checked every recommendation against the code, so the file/param references below are real, not generic.

## Critical pre-flight: we already double-touch the albedo

Before changing anything, resolve one ambiguity the research repeatedly warned about. Two places **already** try to fix dark TRELLIS textures:

1. `scripts/opr_army_manager.gd::_brighten_trellis_materials()` (line 1067) forces `metallic=0`, `roughness=0.7` at **runtime in Godot** to compensate for dark minis.
2. `glb_sharpen.py` re-encodes the baseColor (sharpen only, no brightness).

If we add an sRGB/brightness fix in `model_forge` **and** keep the Godot runtime brightener, we will over-brighten. **Decision needed first:** fix brightness once, at the GLB level (recommended — it also fixes the standalone toolkit / STL-print use-case), then reduce or remove the Godot-side compensation. Do not stack both. This is the single biggest source of uncertainty in the whole plan.

---

## ⭐ Top 3 highest-leverage, lowest-effort wins (do these first)

### 1. Raise the TRELLIS texturing params (they're at the weak defaults) — fixes BLURRY
**Change:** In `assets/3d_pipeline/trellis_core.py`, lines 272-275:
```python
tex_slat_guidance_strength=1.0,   # → 3.5  (1.0 = almost NO guidance to the input image)
tex_slat_guidance_rescale=0.0,    # → 0.5  (suppress oversaturation from higher guidance)
tex_slat_sampling_steps=12,       # → 24
tex_slat_rescale_t=3.0,           # leave
```
- **Why:** Six-of-six agreement that `tex_slat_guidance_strength=1.0` is the worst offender — it means TRELLIS barely looks at the input image, so textures come out generic/soft. We already max `RESOLUTION="1536"` and `TEXTURE_SIZE=4096`, so guidance/steps is the remaining lever.
- **Effort:** Trivial (4-line edit). **Impact:** Medium-high on sharpness/fidelity. **Cost:** a few extra seconds/model.
- **Honesty:** TRELLIS.2 issue #71 got blur even at guidance 9 / 50 steps — so this *helps* but will not fully fix blur alone; pair with the post-process upscale (win #3) and atlas fix (Stage C). Verify our Gradio space actually accepts these `tex_slat_*` arg names (the params are passed by keyword to `client.predict(... api_name="/image_to_3d")` — confirm the space build matches).
- **Source:** https://github.com/microsoft/TRELLIS.2/blob/main/app_texturing.py

### 2. sRGB / white-balance / brightness fix on the baked baseColor — fixes DARK + GREEN
**Change:** New post-process step `glb_albedo_fix.py`, modeled exactly on `glb_sharpen.py`'s GLB round-trip (it already extracts the baseColor, rewrites bufferViews bit-for-bit, handles `EXT_texture_webp`). Apply to the extracted PNG, in this order:
1. **Gray-world / 97.5th-percentile white balance** → kills the green cast.
2. **Brightness lift** — either the principled sRGB transfer (`y=pow(x,1/2.4)`) **or** CLAHE on the LAB L-channel (clipLimit≈2.0). CLAHE is safer because it lifts the dark baked-shadow side more than the lit side without blowing highlights.
- **Why:** Reports converge: TRELLIS bakes lighting into albedo (no delighting) **and** likely emits linear-RGB read as sRGB → the ~66/255 median + green. This is image-space, so our shattered UV atlas is irrelevant here.
- **Effort:** Low-medium (one script, reuses `glb_sharpen.py` plumbing). **Impact:** High — directly targets the headline symptom.
- **Honesty:** The sRGB-curve fix and CLAHE are **different mechanisms** — do **not** stack both blindly (double gamma). And see the pre-flight: this conflicts with the Godot runtime brightener. Start with CLAHE+white-balance (perceptual, low double-correction risk); only add the `pow(1/2.4)` curve if you confirm our GLB import does *not* already tag baseColor sRGB. It cannot remove **directional** shadows — only brightness/cast (that needs Stage A or E).
- **Sources:** https://github.com/microsoft/TRELLIS/issues/103 · https://pyimagesearch.com/2021/02/15/automatic-color-correction-with-opencv-and-python/

### 3. Real-ESRGAN 2× upscale of the baseColor — fixes BLURRY (resolution loss)
**Change:** Add an optional upscale pass to the same `glb_albedo_fix.py` (run **after** color correction): `RealESRGAN_x2plus`, `--face_enhance` OFF (it's tuned for human faces; our minis are alien). Finish with the existing `glb_sharpen.py` unsharp (we already call it at `radius=3 percent=150`).
- **Why:** The shattered atlas spreads few texels per chart; upscaling recovers apparent detail without re-running TRELLIS.
- **Effort:** Low (CLI tool, drop into the chain). **Impact:** Medium. **Cost:** GPU/VRAM; use `-t 400` tiling on the 4096 atlas.
- **Honesty:** This is cosmetic — it sharpens what's there, doesn't add true geometric texture detail. Order matters: **color-correct → upscale → unsharp**, else you amplify the green cast.
- **Source:** https://github.com/xinntao/Real-ESRGAN

> These three are non-destructive, reuse existing plumbing, and need no Blender. Sequence in the pipeline: TRELLIS (win 1) → `glb_albedo_fix.py` (win 2 + 3) → existing `glb_sharpen.py`.

---

## Stage A — Image input (root-cause delighting)

| Action | Fixes | Effort | Impact |
|---|---|---|---|
| **Add a delight + auto-white-balance step to `image_finalize.py`** before `deshadow()` (line 58). `deshadow.py` only whitens the *background*; it does not touch the figure's baked shading. Add gray-world WB + brightness/even-lighting on the masked **figure** so TRELLIS bakes a flatter albedo. | dark, green | Low–Med | **High** (root cause) |
| **Multi-view input** for dark backsides — feed front+back/side via the multi-image path (we have `multiview_patch/`). | dark backside | Med | Low–Med ("slightly improves" per issue #308) |
| **IC-Light FC** (ComfyUI) to relight the masked mini to flat/even studio light before TRELLIS — heavier, only if cheap WB isn't enough. | dark | High | Med |

- **Why this stage matters most:** TRELLIS has no illumination disentanglement (paper limitation; issues #124/#199/#308). Whatever lighting is in the input is permanently baked. Fixing it upstream is strictly better than fighting it in post.
- **Honesty:** We already deshadow for the base-disc problem; extending it to delight the figure is the natural, cheap extension. IC-Light *relights toward a target*, it doesn't solve true albedo — verify it doesn't invent shading.
- **Best source:** https://github.com/microsoft/TRELLIS/issues/199 · (delight rationale) https://arxiv.org/html/2506.15442v1

## Stage B — TRELLIS params

Covered by **win #1** above. Additional note: `RESOLUTION="1536"` (voxel grid) and `TEXTURE_SIZE=4096` are **already maxed** in `trellis_core.py` (lines 45-48) — no gain available there. `DECIMATION` defaults to 100k; see Stage C on lowering it for less fragmentation.

## Stage C — Mesh + UV (the shattered atlas)

| Action | Fixes | Effort | Impact |
|---|---|---|---|
| **Lower decimation for small minis** before unwrap. Root cause of the shattered atlas is collapse-decimation → chaotic triangles → a seam at every edge. Drop `DECIMATION`/`DECIMATION_BY_CLASS` from 100k toward ~50k–150k for standard minis so xatlas makes fewer, larger charts. | uv-frag, blur | Low | Med |
| **Quad-remesh path:** set TRELLIS.2 `remesh=True` / route through `Trellis2ReconstructMeshWithQuad` if our space exposes it (the Gradio space usually does **not** — likely needs the ComfyUI/CuMesh path). | uv-frag | Med–High | Med |
| **Blender QuadriFlow remesh** (`use_preserve_sharp=True` for the spikes) → shrinkwrap detail back → re-unwrap. We have Blender-MCP + `_glb_fraganalyze.py` already measures fragmentation. | uv-frag | High | High |

- **Honesty:** Cranking `texture_size` does **not** fix fragmentation (charts just scale to fit). For our **print/STL** use-case, fragmentation mostly hurts texture sharpness, not geometry — so prioritize this only if the post-process (Stage D) doesn't get the texture crisp enough. Lower-decimation is the cheap first try; full retopo is the expensive last resort.
- **Best source:** https://github.com/jpcy/xatlas · (quad path) https://github.com/microsoft/TRELLIS.2

## Stage D — Post-process (GLB round-trip)

Covered by **wins #2 and #3**. We already have the exact plumbing: `glb_sharpen.py` (round-trip pattern to copy), `glb_tex.py` (Laplacian-variance sharpness metric for A/B measurement), `_hl_texcompare.py` (comparison harness). Build `glb_albedo_fix.py` as: extract → white-balance → CLAHE/gamma → Real-ESRGAN → re-embed; then existing unsharp. Use `glb_tex.py` to verify median brightness rises from ~66 toward ~150-180 and lapvar increases.

## Stage E — Re-texture in Blender (highest quality, highest effort)

| Action | Fixes | Effort | Impact |
|---|---|---|---|
| **Selected-to-Active diffuse-only bake** to a fresh Smart-UV atlas (Angle Limit ~66, Island Margin ~0.02), **Direct AND Indirect UNCHECKED** → fixes the shattered atlas **and** strips baked HDRI lighting in one pass. Use a **Cage** on the spikes to avoid ray misses. | dark, uv-frag | High | **Highest** |
| **Project-From-View** from an orthographic camera aligned to the reference image → maps the *clean* reference 1:1 onto front faces, then bake. Front-facing minis benefit most; backs stretch. | all | High | High (front) |

- **Why:** Multiple reports conclude the TRELLIS bake is "disposable" for production quality — rebuild albedo in Blender. This is the definitive fix but needs the Blender-MCP round-trip we noted previously *washes textures* on naive re-export, so bake carefully and re-encode at high quality (don't let Blender's exporter recompress).
- **Honesty:** This is a real project, not a quick win. Reserve for hero minis where Stages A+D aren't enough.
- **Best source:** https://docs.blender.org/manual/en/latest/render/cycles/baking.html · https://github.com/microsoft/TRELLIS/issues/199

## Stage F — Alternative engine (evaluate only)

**Hunyuan3D 2.1 Paint** does native illumination-invariant albedo (delights by design, outputs PBR). Tempting as a TRELLIS-geometry + Hunyuan-texture hybrid. **Blocked for us:** MEMORY records Hunyuan as **EU-blocked / not CC-BY-SA-safe** for shipped minis. Treat purely as a *technique reference* (it validates the "delight the input" approach in Stage A) unless licensing is re-confirmed. **Source:** https://arxiv.org/html/2506.15442v1

---

## Recommended rollout order

1. **Resolve the double-correction** (Godot brightener vs. GLB-level fix) — decision, not code.
2. **Win #1** (params, 4-line edit) — measure with `glb_tex.py`.
3. **Win #2 + #3** (`glb_albedo_fix.py`) — wire after TRELLIS, before existing `glb_sharpen.py`.
4. **Stage A** (delight the figure in `image_finalize.py`) — the durable root-cause fix.
5. **Stage C** lower-decimation experiment; escalate to Stage E re-bake only for heroes.

## Honest uncertainties
- **Param names** (`tex_slat_*`) must match our deployed Gradio space build — verify before relying on win #1.
- **Color-space double-correction** between the new GLB fix and `_brighten_trellis_materials()` in Godot is the biggest risk; one must yield to the other.
- **Linear-vs-sRGB vs. baked-shadow** are *two distinct* causes of "dark." White-balance+CLAHE addresses cast/brightness; only Stage A/E addresses **directional** baked shadows. Don't expect post-process alone to fully neutralize the dark backside.

**Files to touch:** `assets/3d_pipeline/trellis_core.py` (params + decimation), new `tools/model_forge/glb_albedo_fix.py`, `tools/model_forge/image_finalize.py` (delight step), and a decision on `scripts/opr_army_manager.gd::_brighten_trellis_materials()`.