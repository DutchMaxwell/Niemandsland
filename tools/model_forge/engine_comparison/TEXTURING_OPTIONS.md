# 3D-Native Texturing — Decision

## (1) Ranked shortlist (passes all hard constraints)

**1. StableGen (Blender addon + ComfyUI, SDXL pipeline) — BEST FIT**
GPL-3.0 addon, output owned by you via SDXL's OpenRAIL++-M → **CC-BY-SA-shippable**. EU-local, no data leaves the box. **8GB is the documented SDXL minimum** (tight/slow but works). Slots straight into our existing Blender + ComfyUI + Gemini stack (Gemini hero ref → IPAdapter). Multi-ControlNet (depth+normal+canny) keeps detail mesh-aligned.

**2. MV-Adapter Img2Texture (`--variant sd21`) — best for headless/batch**
Apache-2.0 code + SD2.1 (OpenRAIL) → owned, CC-BY-SA-clean, EU-OK. SD2.1 variant is the explicit **<10GB path → fits 8GB**. CLI-scriptable (no Blender GUI), and a **free HF Space exists for a zero-setup smoke test**. Softer than SDXL but a clear upgrade over our baseline.

**3. Tripo OR Meshy (paid API) — cheap fallback if self-host seams frustrate**
~$0.12–0.21/texture, EU-usable, paid tier grants output ownership. **Caveat (uncertain):** their TOS grant "you own it" but do **not** clearly authorize *relicensing under CC-BY-SA* (Tripo §3.2 even restricts third-party redistribution). Treat as needs-written-confirmation before shipping copyleft; fine for internal/quality comparison.

### Explicitly REJECTED
- **Hunyuan3D-2 / 2.1 Paint** — highest quality, but license **excludes the EU/UK/South Korea by name** AND is not OSI/CC-BY-SA-compatible. Double-disqualified. (Confirms our prior memory.)
- **TEXGen** — best "native" UV quality, but **needs ~24GB VRAM** (won't run on 3070 Ti) **and has no stated license** → can't ship. Watch-list only.
- **Text2Tex** — **CC-BY-NC-SA** (NonCommercial) → incompatible with CC-BY-SA.
- **MVPaint** — **no LICENSE in repo** → no right to relicense. Watch-list.
- **TRELLIS.2 texturing / Paint-it** — MIT/clean and EU-OK, but **~24GB / 48GB-tested VRAM** → not local on 8GB (only via rented GPU or HF Space).
- **FLUX.1-dev** (as any StableGen/MV-Adapter base) — **non-commercial license**. Hard avoid; stay on SDXL/SD2.1.
- **Sloyd / CSM** — can't retexture an arbitrary uploaded TRELLIS mesh (wrong tool for our step).

## (2) What it takes to test the top pick (StableGen)
- **No signup / no API key** — fully local, GPL addon.
- **Install:** Blender addon + a working local ComfyUI; download canonical **stabilityai SDXL-base-1.0** checkpoint + 3 ControlNets (depth, normal, canny) + IPAdapter. This is the real effort (~an evening of ComfyUI model wrangling).
- **VRAM:** 8GB = documented SDXL minimum → expect **low-VRAM ComfyUI flags + model offloading + slow runs**; verify empirically, mark as *uncertain it stays comfortable*.
- **Cost:** **€0** (electricity only).
- **Inputs ready:** feed a TRELLIS mini GLB + a Gemini per-faction hero style-ref as the IPAdapter image.
- **Budget a Blender touch-up pass** for concave cavities (cloaks/undercuts) cameras can't see — true of all projection methods.

## (3) Honest expected quality gain
You'd move from a flat sRGB albedo + generic chitin-normal to **art-directed, geometry-aligned multi-view detail (real material cues: metal vs cloth vs leather)** — a clear, visible upgrade for hero minis, but expect seams and unlit cavities needing manual cleanup, so it's "noticeably better, not turnkey-perfect."

## (4) Fastest thing to test TODAY, no paid signup
Run a single TRELLIS mini through the **free MV-Adapter-Img2Texture HF Space** (`VAST-AI/MV-Adapter-Img2Texture`) with a Gemini hero reference image. Zero install, zero cost, gives a same-day read on whether image-conditioned 3D-native texturing beats our baseline — *before* committing the evening to the StableGen/ComfyUI setup.

---
*Uncertainty flags: 8GB SDXL comfort is inferred, not benchmarked — verify on the 3070 Ti. Tripo/Meshy CC-BY-SA relicensing rights are unconfirmed in their TOS. SD2.1/SDXL "you own the output" rests on the AI-output-copyrightability question that's genuinely open in the EU/US — relevant because CC-BY-SA's share-alike hook depends on copyright existing.*