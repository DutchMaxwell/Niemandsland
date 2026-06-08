# How to get the best out of TRELLIS

A plain-language guide. No jargon, no code. TRELLIS turns a single image into a 3D model. Here's how to make it good.

Each tip is tagged **[consensus]** (almost every source said it), **[common]** (several sources said it), or **[single-source]** (one credible source).

---

## The 5 biggest levers (ranked by impact)

1. **Remove the background first. [consensus]**
   Cut the object out so it sits alone on a plain white, grey, or transparent background. This is the single most repeated piece of advice — clutter gets fused into your model as junk geometry.
   → https://github.com/microsoft/TRELLIS.2/issues/65

2. **Kill harsh shadows before generating. [consensus]**
   Use soft, even lighting with no dark shadow under or beside the object. TRELLIS reads dark areas as real shape, so a contact shadow becomes a fake disc or base baked into the mesh. Lighting is also permanent — whatever shading is in your photo is painted into the texture forever.
   → https://github.com/microsoft/TRELLIS/issues/199

3. **Feed it one sharp, high-res object. [consensus]**
   Use a single, centered, fully-visible object in an image that's at least 1024×1024 pixels and in sharp focus. More clean pixels = more real detail; blurry or tiny inputs come out mushy. Going much above 1024 rarely helps.
   → https://fal.ai/learn/devs/trellis-2-image-to-3d-prompt-guide

4. **Try a new seed before touching any setting. [common]**
   Every run uses a random "seed" (the number that decides the exact result). If a model comes out malformed, just generate again for a different shape — it's faster and cheaper than fiddling with sliders. Note the seed of a result you like so you can reproduce it.
   → https://github.com/microsoft/TRELLIS

5. **More sampling steps = the main quality dial. [consensus]**
   "Sampling steps" controls how much work TRELLIS puts into refining the result. Use ~12 (the default) for quick previews, bump to ~20–25 for your final keeper. Above that, you mostly just wait longer for no visible gain.
   → https://deepwiki.com/microsoft/TRELLIS/2.2-quick-start-examples

---

## The input image

- **One object, centered, nothing cropped off. [consensus]** Don't feed a whole scene or cut off the feet/head/sides — TRELLIS can't rebuild what it can't see, so it guesses or leaves holes.
  → https://www.sloyd.ai/blog/common-mistakes-when-creating-3d-models-from-images
- **Use a three-quarter angle, not dead-front. [common]** Turn the object ~30–45° so you see the front and a bit of one side. A flat front-on shot hides all the depth and comes out flat. Avoid fish-eye / extreme perspective (it warps proportions).
  → https://fal.ai/learn/devs/trellis-2-image-to-3d-prompt-guide
- **Avoid glass, mirrors, chrome, and shiny surfaces. [common]** Reflective and see-through materials show TRELLIS the background instead of the object, producing holes and spikes. Matte, solid objects reconstruct cleanly.
  → https://www.sloyd.ai/blog/common-mistakes-when-creating-3d-models-from-images
- **Keep characters in a calm, neutral pose. [common]** Arms and legs near the body, like a clean product photo. Dramatic action poses hide limbs behind other limbs and confuse the model.
  → https://www.3daistudio.com/blog/how-to-use-trellis-2-online-image-to-3d-tutorial
- **Give 2–4 angles for the back/sides if you can. [common]** TRELLIS has a multi-image mode. Extra views fix the dark, smeared backside that single photos produce — especially for asymmetric objects. (Caveat: the official repo says multi-image is a "tuning-free" trick, so test it per object.)
  → https://github.com/microsoft/TRELLIS/issues/308

---

## The settings

Two stages run under the hood: **Stage 1** builds the rough shape, **Stage 2** adds detail and texture. The defaults are deliberately balanced — change them only with a reason.

- **Sampling steps — how hard it refines. [consensus]** ~12 for previews, ~20–25 for finals. (Same as lever 5 above.)
  → https://deepwiki.com/microsoft/TRELLIS/2.2-quick-start-examples
- **Structure guidance — how closely Stage 1 follows your image. [common]** Default ~7.5. Raise to **8–9 for hard-surface things** (vehicles, weapons, furniture, armour) to get crisp clean edges. Leave at default or slightly lower (5–7) for **organic/soft shapes** so they don't look stiff.
  → https://fal.ai/learn/devs/trellis-2-image-to-3d-prompt-guide
- **Detail/texture guidance — how hard Stage 2 pushes. [common]** Keep it LOW (~2.5–3, the default). Cranking it adds noisy artifacts instead of detail. Sharpness comes from texture size, not from this dial.
  → https://github.com/microsoft/TRELLIS.2/issues/92
- **Texture size — sharpness of the surface paint. [consensus]** 1024 for game/web models; 2048 for hero or close-up/print models; 4096 only if textures still look blurry. Bigger = sharper but heavier files.
  → https://fal.ai/learn/devs/trellis-2-image-to-3d-prompt-guide
- **Mesh simplify — how many triangles get thrown away on export. [consensus]** Default ~0.95 keeps it looking right while cutting polygon count. Lower toward 0.9 to keep more detail. **Do not go below 0.8** — it collapses fingers, faces, and thin parts.
  → https://github.com/microsoft/TRELLIS
- **Skip the "max everything" presets. [common]** 50 steps, guidance 8+, 4K textures, resolution 1536 — these are user experiments, NOT a Microsoft preset. For everyday work the defaults plus ~20–25 steps look nearly identical for a fraction of the time. Save the heavy settings for one showcase model.
  → https://github.com/microsoft/TRELLIS.2/issues/92

**Fast workflow:** explore cheap (512 texture, 12 steps, re-roll seeds) → pick a keeper → regenerate that one at 1024–2048 texture and ~20 steps.

---

## After generation

- **Expect to polish the texture yourself. [common]** TRELLIS nails geometry but its textures are the weak part. Pull the texture out, run it through an AI upscaler (start at 2×) or clean it in a paint tool, then put it back. Sharpen the important areas, not the whole map.
  → https://www.tripo3d.ai/blog/upscale-textures-on-ai-3d-models
- **Fix washed-out colors with the color space. [single-source]** If exported colors look faded or dark versus your input, the texture is being read in the wrong color space — re-tag the base-color image as sRGB and the model snaps back to matching the original.
  → https://github.com/microsoft/TRELLIS/issues/171
- **Clean the raw mesh before using it. [common]** Raw AI meshes are dense "triangle soup" with flipped normals and small holes. In Blender: recalculate normals outward, make it watertight (manifold), delete stray bits, then retopologize to lower-poly if you need it to animate or render.
  → https://arxiv.org/html/2509.12815v1
- **For 3D printing: repair, thicken, then decimate. [common]** Check for non-manifold edges and flipped normals, ensure ~1.5–2 mm minimum wall thickness, then decimate to roughly 100k–250k faces (don't go below ~50k). Export and slice as usual.
  → https://trellis2.app/blog/image-to-3d-model-3d-printing
- **Turn flat-looking detail into real relief. [single-source]** If the texture looks detailed but the surface reads as flat, drive a displacement from the model's own texture in Blender at low strength (~0.01–0.1) so it catches light properly.
  → https://www.tripo3d.ai/blog/upscale-textures-on-ai-3d-models

---

## Common mistakes that ruin results

- **Busy or cluttered background** → junk geometry and holes. Always cut it out first.
- **Harsh shadow under the object** → a fake base/disc fused onto the model.
- **Tiny or blurry input image** → soft, mushy result no slider can rescue.
- **Multiple objects or a full scene** → the model merges them or picks the wrong one.
- **Cropping off feet, head, or sides** → holes and invented geometry where it couldn't see.
- **Shiny / glass / mirror surfaces** → spikes and holes; use matte objects.
- **Dramatic action poses** → hidden limbs fuse together; use a neutral pose.
- **Cranking the detail/texture guidance for "sharper" results** → adds artifacts; raise texture size instead.
- **Over-simplifying on export (below 0.8)** → fingers, faces, and thin parts collapse.
- **Chasing the 50-step / 4K "max quality" config** → long render times for a result that looks nearly identical to the sensible defaults.
- **Expecting perfect textures straight out** → budget a quick upscale/cleanup pass for hero assets.