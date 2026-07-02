# Return handoff: openTTS (game) → ModelForge — .ctex faction verification findings

**From:** the openTTS game-maintainer side. **To:** the ModelForge (asset pipeline) side.
**Date:** 2026-07-01. **Godot pinned:** 4.6. Answers your battle_brothers (26-unit) verification ask.

---

## TL;DR

The `.ctex` texture pipeline is validated and delivers the VRAM win. Two rounds of faction testing
led to a **strategy change: compress TEXTURES only, leave GEOMETRY untouched.**

**Final strategy (do this for the 1014 rollout):**
1. **Albedo at NATIVE resolution** (4096² for bodies/vehicles) — do NOT downscale (`process/size_limit=0`).
   The earlier 2048² bakes were visibly washed; 4096² BC7 = full RAW quality (proven on a render).
2. **NO geometry reduction — no decimate, no voxel-remesh. Keep each model's original geometry.**
   Decimate shatters vehicles (faceting); voxel-remesh rounds sharp edges. And geometry is NOT the VRAM
   wall — textures are (~102 MB/unit saved by .ctex vs ~8 MB by a remesh). Quality-first: keep the geo.
3. The `ctex.mesh` GLB = the **original geometry with embedded textures stripped** + separate `.ctex`.

Game loader needs **no change** (`CtexLoader.apply_to_mesh` handles any geometry + both class shapes).

---

## What's CONFIRMED GOOD — no action

- **BC7 at native resolution is near-lossless** — 4096² BC7 render is identical to 4096² RAW.
- **VRAM win real:** per unit raw 128 MB (2× 4096² RGBA) → .ctex 10.67 MB (2× 2048² BC7). BC7 = ¼.
- **Game loader** (`CtexLoader`) loads `.ctex` from `user://cache/<sha>.ctex` as `CompressedTexture2D`,
  stays GPU-compressed, handles any resolution. Version guard (`godot_version` vs engine) falls back
  to the legacy raw-GLB `url` on mismatch. A game-side metallic-material bug was found + fixed here
  (not your concern — it's why earlier ctex renders looked matte; ignore).
- **Manifest shape** confirmed: a `ctex` block beside the legacy `url` fallback.
- **Never ASTC** (unavailable on desktop RDNA2 / Steam Deck).

---

## Producer TODOs (actionable)

### 1. STOP downscaling body/vehicle albedo — keep native 4096²
The current bakes carry `process/size_limit` that downscales to 2048². For detail-critical classes,
set **`process/size_limit=0`** (keep native res). Verified-working albedo bake settings:
```
compress/mode=2            # VRAM Compressed (BC7)
compress/high_quality=true
mipmaps/generate=true
process/size_limit=0       # <-- KEEP native 4096² (this was the bug: it was downscaling to 2048)
```
4096² BC7 ≈ 22 MB vs 4096² RGBA 64 MB → still ~65–75 % VRAM saving, at FULL detail.

### 2. DROP geometry reduction — texture-only compression (maintainer decision 2026-07-01)
**Textures are the VRAM wall, not geometry — so compress textures, keep the original geometry.**
Measured on this faction:
- Texture compression is the whole win: **raw 128 MB → .ctex 26 MB textures = −102 MB/unit.**
- Geometry reduction saves almost nothing by comparison: a full-res vehicle mesh is **only ~10 MB**
  mesh VRAM (measured: apc = 206k tris ≈ 10.2 MB); a remesh drops that to ~2 MB — an ~8 MB/unit gain.
- That ~8 MB is NOT worth the quality cost: **voxel-remesh rounds sharp mechanical edges**, and
  **decimate shatters vehicles into faceting**. Both were rejected on the quality bar.

**New rule: NO decimate, NO voxel-remesh. Keep each model's ORIGINAL full-resolution geometry** (it's
exactly what the game ships today — crisp, no faceting). The **`ctex.mesh` GLB = the original geometry
with its embedded textures STRIPPED** (geometry-only, small) + the textures as separate `.ctex`. This
also simplifies your pipeline (the remesh/decimate stage is gone).

| Class | Geometry | Albedo | ORM / Normal | VRAM/unit (vs ~138 MB raw) |
|---|---|---|---|---|
| **Props** (e.g. heavy_sword) | **original** | 2048² BC7 | 2048² BC7 | ~12 MB |
| **Infantry / bodies** | **original (no decimate)** | **4096² BC7** | ORM 2048² BC7 | ~36 MB (~74 %) |
| **Vehicles / walkers** | **original (no remesh)** | **4096² BC7** | Normal 2048² BC5 (no ORM → procedural metallic) | ~36 MB (~74 %) |

### 3. (removed) — no geometry pass at all
The earlier "voxel-remesh vehicles" recommendation is **withdrawn**. Keep original geometry for every
class. (If a real VRAM ceiling ever bites on huge armies, selectively decimate ONLY classes where it's
invisible — infantry 40k decimate looked fine — but default to untouched geometry / quality-first.)

### 4. Texture roles / packing (as used by the loader)
- **Albedo → BC7 (sRGB).**
- **ORM = glTF metallicRoughness → BC7 (linear): G=Roughness, B=Metallic.** This batch had **no AO**
  (R unused) — good. If a class packs real **AO in R**, say so in the manifest so the loader enables
  it (`orm_has_ao`); otherwise the loader leaves AO off (correct default).
- **Normals:** this batch has none (TRELLIS bakes detail into albedo). If a class gets normals, bake
  **BC5** (Normal Map role, reconstruct Z) — **never BC1** for normals.

### 5. Manifest: wrap in `ctex`, carry `godot_version`
The heavy_sword/battle_brothers test assets are flat; for the catalogue wrap per entry:
```json
"faction/unit": {
  "url": "<legacy>.glb", "sha256": "...", "size": ...,        // legacy raw GLB = version-guard fallback
  "ctex": {
    "godot_version": "4.6",
    "mesh":     { "url": "<sha>.glb",  "sha256": "...", "size": ... },
    "textures": {
      "albedo": { "url": "<sha>.ctex", "sha256": "...", "size": ... },
      "orm":    { "url": "<sha>.ctex", "sha256": "...", "size": ... }
      // "normal": {...}  // only if the class has one
    }
  }
}
```
Keep the **pinned Godot 4.6 tools build** for baking; the `godot_version` drives the guard.

### 6. Re-verify per class before scaling to 1014
After re-baking bodies at 4096² (size_limit=0) and voxel-remeshing vehicles, ping the game side to
re-run the throwaway test scenes (`ctex_faction_test` / `ctex_infantry_detail` / `ctex_res_compare`,
F6 on a real GPU) and confirm each class passes, then roll the bake stage across the catalogue.

---

## Already shipped (game side, deploy-safe)
- `biome_manifest.json` → 4096² biome grounds (committed).
- `model_manifest.json` → 196 re-optimized unit GLBs (committed).
Both verified: structure unchanged, only sha/size/url, shas resolve on R2.
