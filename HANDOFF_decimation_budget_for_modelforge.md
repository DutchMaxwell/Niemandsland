# Handoff: openTTS (game) → ModelForge — per-category geometry-decimation budget

**From:** the openTTS game-maintainer side.
**To:** the ModelForge (asset-pipeline) agent — private repo `~/model-forge` (DutchMaxwell/model-forge).
**Date:** 2026-07-01. **Godot pinned:** 4.6. **Scope:** geometry only (textures/`.ctex` are a separate track — see `HANDOFF_ctex_findings_for_modelforge.md`).

This asks you to enable a **base-size / unit-class → target-triangle decimation budget** in the mini pipeline. The budget below was decided by the maintainer and validated visually + with an army-scale FPS test on the game side. All the code references are into **your** repo (from a read-only audit).

---

## TL;DR — the decision

Decimate each mini to a triangle target that depends on its **on-table size class** (which correlates with both apparent size and sculpt complexity). Three tiers:

| Class (`_classify_unit`) | Target triangles | Rationale |
|---|---|---|
| **infantry** (25–40 mm) | **86 000** | small on the table + numerous → biggest total win |
| **vehicle** (incl. **walker**) | **185 000** | flat panels/sharp edges + large on screen → conservative |
| **large** (titan / monster / great beast / giant / dragon) | **NO decimation — keep full/native** | biggest on the table, single-piece, quality-first |

- **Method: Blender absolute-triangle decimation** (`game_optimize.py`), **NOT `gltfpack -si`** — gltfpack barely touches these TRELLIS meshes (your own note, `game_optimize.py:3-4`).
- **Do not touch textures here** — this is purely the geometry stage. Texture VRAM is unaffected by decimation (measured: identical before/after).

---

## Why these numbers (evidence, game side)

Validation was done on the openTTS branch `fix/playtest-followups-2` with throwaway render harnesses (`scenes/ctex_decimate_basesize.tscn`, `scripts/ctex_army_fps_budget.gd`), rendering Blender-COLLAPSE decimation ladders at the true on-table apparent size on a real GPU.

1. **Infantry @86k is visually indistinguishable** from full (~286k) — confirmed across **9 minis / 6 factions** (power-armour, organic, thin-rifle, winged, banner, thin blade, staff, spear, orc), at closest realistic zoom on white. The true break point is far lower (~5–15k); 86k is a comfortable quality-first floor, not the edge.
2. **Walkers/vehicles** were judged at closeup: panels hold, but turret mantlets / leg joints / thin barrels start faceting below ~185k → **185k** keeps them crisp. **Larger monsters/titans → keep full** (maintainer decision "everything bigger stays full").
3. **FPS payoff (200-instance army, RTX 3070 Ti, vsync off):** full ~286k → **33 FPS**; 86k → **78 FPS** (+136 %), triangles/frame 179 M → 53 M. **Texture VRAM identical (1598 MB)** → decimation buys frame-rate (vertex throughput), `.ctex` buys VRAM. On a Steam Deck (≈⅛ raster) this is roughly the unplayable→playable line for big armies.

---

## Where to implement (file:line, your repo)

### 1. The budget table — `suite_app.py:1067` `SIZE_CLASSES`
Currently `infantry (40000, 2048)`, `large (80000, 2048)`, `vehicle (120000, 4096)`. Change the **triangle targets** to:
- `infantry` → **86000**
- `vehicle` → **185000**
- `large` → **skip decimation** (keep full geometry; only run the geometry-repair / texture-cap steps, no DECIMATE modifier).

Keep the texture caps as they are (separate concern). The class → budget lookup and `_classify_unit` (`gf_quality_inventory.py:103-109`) already produce exactly these three buckets; **"walker" is already in `VEHICLE_WORDS`** (`gf_quality_inventory.py:~60`), so walker → vehicle → 185k with no classifier change.

### 2. The decimation call — use the Blender absolute path
`game_optimize.py` already converts an absolute triangle budget to a DECIMATE ratio (`m.ratio = TRI / len(o.data.polygons)`, `game_optimize.py:37-39`) — feed it the class budget as `TRI`. This is the reliable path for TRELLIS meshes. **Do not** route minis through `optimize_glb`/`_gltfpack65` for real decimation (`glb_optimizer.py:221`, `-si` = fraction-to-keep, under-decimates non-indexed TRELLIS geometry).

### 3. Turn it on in the publish flow
Decimation currently defaults to **off** — the publish endpoint (`suite_app.py:1229`) uses `size_class="none"` by default (`suite_app.py:1221`), and the comment (`suite_app.py:1063-1066`) says the optimize path "was tested and rejected for now because it changed approved models too aggressively." **Our budgets are conservative and visually validated, which addresses exactly that concern.** Wire the class-derived budget into the publish / `gate_opt` path so it runs per-model by class instead of "none".

### 4. Manifest
The shipped `model_manifest.json` entry carries only `url/sha256/size` (`publish_manifest.py:58-72`) — no class/tris. The budget must be computed at optimize time from the unit-name key via `_classify_unit`. **Optional but recommended:** also write a `class` (and/or `tris`) field into the entry (`publish_manifest.build_manifest` + `_publish_staged_glb` at `suite_app.py:1572`) so future consumers don't re-derive it.

---

## VERIFY before scaling to the catalogue

The visual validation used Blender **COLLAPSE**; `game_optimize.py` uses the Blender **DECIMATE modifier** (collapse mode) — technically the same operator, but **re-bake 1–2 models per class at the budget and eyeball them** before a catalogue-wide run:
- Ping the game side to re-run `scenes/ctex_decimate_basesize.tscn` on the re-baked GLBs (or send the GLBs over) and confirm 86k infantry / 185k vehicle still look identical to full at table zoom.
- Only then run the full re-optimize + re-publish.

## Rollout notes / caveats
- **Catalogue-wide re-bake + re-publish.** Decimating changes each GLB → new sha → manifest update → R2 upload. This touches most of the 1014 models. The game **live-fetches the R2 manifest** (`assets.niemandsland.xyz`), so re-published decimated meshes reach all clients **with no game release** — but so does a bad publish. **Verify after publishing.**
- **Classifier edge case:** a large ORGANIC monster whose name lacks a `BIG_WORD`/`VEHICLE_WORD` would misclassify as infantry → 86k. Audit `BIG_WORDS`/`VEHICLE_WORDS` coverage (`gf_quality_inventory.py:~30-77`) against the real unit list before the full run; add missing terms.
- **Absolute-tris reader if needed:** `glb_inspect.inspect()['triangles']` (`glb_inspect.py:80-90,140`) gives a Blender-free triangle count (JSON only) if you want to convert budgets to ratios or log before/after.
- **Registry** already has `unit_class` (`registry.py:35,128`) and a `triangles` column (`registry.py:69,163-169`) — populate them during the pass for auditability.
- Geometry decimation is **not** Godot-version-coupled (unlike `.ctex`), so no version guard needed.

## Game-side references
- Decision + full context: openTTS memory `decimation-per-base-budget.md`.
- Harnesses (branch `fix/playtest-followups-2`, throwaway — will be removed before merge): `scripts/ctex_decimate_basesize.gd` (per-base apparent-size render), `scripts/ctex_army_fps_budget.gd` (army FPS), `tools/decimate_analysis.py` (SSIM). Render needs a real GPU (headless = dummy renderer).
