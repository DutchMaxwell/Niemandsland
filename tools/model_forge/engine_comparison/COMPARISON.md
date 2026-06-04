# Image→3D engine comparison — TRELLIS vs Hunyuan3D vs Rodin

**Date:** 2026-06-04 · **Input:** the approved Battle Brothers hero render
(`references/battle_brothers/01_hero_FINAL.png`) · **Goal:** pick the image→3D engine for
Niemandsland's miniatures, under the hard constraint that **generated outputs must be publicly
redistributable and relicensable under CC-BY-SA 4.0** (open-source, IP-safe — see
`references/battle_brothers/README.md`).

Method: each engine was researched against its primary-source license/ToS, then the CC-BY-SA
claim was **adversarially verified** (independent skeptics, default-refute, majority-refute = fail).
TRELLIS was additionally run end-to-end; the other two were blocked at runtime (see below) — but the
license analysis is decisive on its own.

---

## TL;DR — Decision: **TRELLIS** ✅

It is the **only** engine of the three whose outputs we can legally release under CC-BY-SA 4.0,
**and** it already produces good, on-design miniatures in our existing pipeline. The other two are
ruled out by their *licenses*, not just by today's runtime blockers — so fixing those blockers would
not change the decision.

| | **TRELLIS** | **Hunyuan3D 2.x** | **Rodin / Hyper3D** |
|---|---|---|---|
| **CC-BY-SA 4.0 fit** | ✅ **Yes** (with one fix) | ❌ No (EU-blocked) | ❌ No (no ownership) |
| Output license basis | MIT weights, **no output claim** | Tencent Community License | Closed-SaaS ToS covenant |
| Self-hostable | ✅ Yes | ✅ Yes (weights) | ❌ No (SaaS only) |
| Watermark | None | None | None |
| Cost | Free (own/rented GPU) | Free (self-host) | Credits, pay-on-download |
| Texture / PBR | 4K PBR (baseColor + metalRough) ✓ | 512² PBR (albedo/metal/rough) | **Best-in-class 4K PBR** |
| Mesh | dense tri-soup, decimatable | strong shape fidelity | **quad-dominant** (cleanest) |
| Speed | ~tens of s (self-host) / ~3.5 min (our HF Space, cold) | minutes (self-host) | **~4 s** |
| Empirical run here | ✅ **succeeded** | ⚠️ local API down | ⚠️ addon image bug |
| **Verdict** | **CHOOSE** | reject (license) | reject (license) |

---

## The hard gate: who can be CC-BY-SA 4.0?

CC-BY-SA 4.0 is a **copyleft** license: to apply it we must hold (or hold a sublicensable license to)
the rights in the work and be able to grant them onward under ShareAlike. That requires the engine to
(a) not restrict redistribution of the output **and** (b) leave us enough ownership/rights to relicense
it. This is where the three diverge sharply.

### 1. Microsoft TRELLIS — ✅ usable, with one concrete fix

- **Code + weights are plain MIT** (`microsoft/TRELLIS-image-large`, and the `TRELLIS.2-4B` successor
  we actually use): Microsoft copyright only, **no AUP/RAIL/responsible-AI rider, no output-ownership
  claim**. Outputs are ungoverned by any TRELLIS term → we own/control the GLB and may relicense it
  CC-BY-SA 4.0 and host it for anonymous download.
- **The one snag — `nvdiffrast`:** TRELLIS's *default* GLB texture-bake (`to_glb(mode='opt')`) calls
  NVIDIA `nvdiffrast`, which is under the **NVIDIA Source Code License (1-Way Commercial) = non-commercial
  /research-only** (§3.3). CC-BY-SA explicitly permits downstream *commercial* reuse, so a bake that ran
  through nvdiffrast is a real ambiguity. Both skeptics refuted **solely** on this — not on any
  fundamental license bar.
  - **Mitigation (concrete):** use **`mode='fast'`** (cv2.inpaint, no nvdiffrast) — still produces a
    textured GLB, the non-commercial library never runs. Weaker fallback: nvdiffrast's license binds the
    *code/derivatives*, not the *generated mesh*. **Action item:** confirm/force the fast bake in our
    TRELLIS Space (we run our own `DutchyMaxwell/TRELLIS.2`, so we control this).
- **Input-image IP:** outputs can't exceed the input's rights — our positive-only, IP-safe hero images
  already satisfy this.

### 2. Tencent Hunyuan3D 2.0 / 2.1 — ❌ ruled out **for us (EU)**

- Technically strong and self-hostable, no watermark, and Tencent claims no rights in outputs as
  *Model Derivatives*. **But** the Tencent Hunyuan Community License **§5(c)** (verbatim, identical in
  2.0/2.1): *"You must not use, reproduce, modify, distribute, or display the … Works, **Output or
  results** … **outside the Territory**. Any such use outside the Territory is unlicensed…"* and **§1.l**
  defines *Territory* as **worldwide EXCLUDING the EU, UK, and South Korea**.
- The project owner is in **Germany (EU)** → both *running* the model and *distributing its output* are
  **unlicensed** for this user. High-confidence refutation, primary-source — a genuine legal bar, not a
  conservative default. (Also: 1M-MAU commercial gate, "Powered by Tencent Hunyuan" marking + Notice file
  if redistributing weights, no-train-other-models clause.)

### 3. Deemos Rodin / Hyper3D — ❌ best quality, but cannot be CC-BY-SA

- Closed SaaS (not self-hostable on free/standard tiers), so only the **Output ToS** is reachable.
  §5: *"…we will not limit your use of such Output, subject to any restrictions…"* — a **covenant-not-to-
  restrict only**: **no ownership transfer, no sublicensable/irrevocable grant**. You may host the GLB,
  but you have **no standing to relicense it to third parties under CC-BY-SA** on Deemos's behalf.
- Deemos additionally **disclaims any warranty that outputs are copyrightable** (purely AI-generated →
  likely uncopyrightable under current US practice → nothing to ShareAlike), ships everything "AS IS" with
  no title/non-infringement warranty, and makes the **user indemnify Deemos**. Both skeptics refuted,
  high confidence. Disqualified for a CC-BY-SA open-source release.

---

## Empirical results

### TRELLIS — ✅ ran successfully
- Pipeline: our `DutchyMaxwell/TRELLIS.2` HF Space (A100), `unit_class=infantry` (100 k decimation
  target), 4096 textures. Cold A100 boot, then convert: **~208 s** total.
- Output `trellis/01_hero_FINAL.glb` — **8.09 MB**, **94 359 triangles / 81 559 verts**, 1 mesh, 1
  material, **PBR baseColor + metallicRoughness, both 4096² WebP** (`EXT_texture_webp` — loads in Godot
  4.6 runtime GLTF). bbox ≈ 0.80 × 0.80 × 1.00 (normalized; scaled to base at spawn).
- Quality: on-design — slate-grey armour, copper-bronze trim, teal helm optic, trapezoidal shoulders,
  carbine. Crisp PBR; only the integral base is a soft blob (TRELLIS-typical). See `trellis/preview.png`.

### Hunyuan3D — ⚠️ blocked at runtime (and license-disqualified anyway)
- BlenderMCP is configured for the **local API at `http://localhost:8081`**, but no server was listening
  → `Connection refused`. Would need the local Hunyuan3D server started. Not pursued: §5(c)/Territory
  rules it out for an EU CC-BY-SA release regardless.

### Rodin / Hyper3D — ⚠️ blocked at runtime (and license-disqualified anyway)
- BlenderMCP free-trial key (MAIN_SITE) is live, but `generate_..._via_images` returns
  `400 "Input buffer contains unsupported image format"` for PNG **and** JPEG (stripped/resized). Root
  cause is in the BlenderMCP addon's `create_rodin_job_main_site`: the image is passed into the multipart
  upload as the (likely still base64-encoded) string rather than decoded bytes, so Deemos's image decoder
  rejects it. Not pursued: the ToS rules Rodin out for CC-BY-SA regardless.

---

## Recommendation & next steps

1. **Standardize on TRELLIS** for Niemandsland's miniatures (it is also already wired into
   `tools/model_forge/`). It satisfies the CC-BY-SA 4.0 + IP-safe goal and produces good output.
2. **Close the nvdiffrast gap:** verify our `DutchyMaxwell/TRELLIS.2` Space bakes GLBs with
   `mode='fast'` (or otherwise without nvdiffrast). This makes the CC-BY-SA chain unambiguous. Until
   confirmed, treat outputs as "MIT-clean mesh, bake-path TBD."
3. **Keep input images IP-safe** (positive-only prompts, our own renders) — already our policy.
4. Hunyuan/Rodin: revisit **only** if the licensing landscape changes (e.g. Tencent drops the EU
   Territory exclusion, or Deemos adds an ownership-granting tier). Not worth the runtime fixes today.

## Reproduce
- TRELLIS: `./venv/bin/python3 engine_compare_trellis.py` (waits for the HF Space to boot, then converts
  + writes `trellis/result.json`).
- GLB metrics: `./venv/bin/python3 glb_inspect.py <file.glb>`.
- Visual: imported into Blender via MCP, material-preview viewport render → `trellis/preview.png`.
