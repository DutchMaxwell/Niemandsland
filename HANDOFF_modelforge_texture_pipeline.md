# Handoff: ModelForge → Niemandsland (openTTS) — Texture/VRAM pipeline

**From:** the ModelForge (asset pipeline) side.
**To:** the openTTS game-maintainer.
**Date:** 2026-07-01. **Godot pinned:** 4.6 (game runs 4.6 Forward+; bake validated on Flatpak 4.6.2).

This covers two things: (A) **staged manifest changes already in this repo** that need your review + commit, and (B) a **prototype-validated `.ctex` texture-compression pipeline** for you to integrate on the game side. ModelForge will produce the assets; the game-side loader change is yours.

---

## SAFETY FIRST — nothing currently shipped is broken

Verified 2026-07-01:
- **Manifests are bundled** (`biome_library.gd` → `res://assets/biome_manifest.json`; CDN has no `biome_manifest.json`, returns 404). Shipped players use the manifest baked into their build, so local repo edits do **not** reach them until a new build ships.
- **Nothing was deleted from R2** — all changes were additive uploads. Every historical sha still resolves (content-addressed). Old biome webp = HTTP 206, unit GLBs = 206.
- Improvements reach players **only via a new game build**. There is no half-deployed state that can break loading.

---

## PART A — Staged manifest changes in this repo (review + commit)

Two files are modified & uncommitted in `assets/`. Both are **deploy-safe** (every referenced sha verified present on R2) and are **improvements**. They take effect on your next build.

### A1. `assets/biome_manifest.json` — biome grounds downscaled 7584×5088 → 4096²
- **Why:** each biome ground was 7584×5088 = **~196 MB VRAM uncompressed** (≈7% of the Steam Deck budget for one texture, and far beyond screen resolution for a table view). At 4096² it is **visually identical** at any real viewing distance.
- **Result:** ~196 MB → **~57 MB VRAM** per active biome (raw); disk 80 MB → 30 MB total. With `.ctex`/BC7 later → ~14 MB.
- All 6 new biome webps are on R2 (content-addressed). The 6 entries now point at the new shas.
- **Backup of the pre-change manifest:** `/tmp/rg_props/biome_manifest.bak.json` (revert by restoring it if you want to hold).
- Old biome webps remain on R2 (not deleted) → fully reversible.

### A2. `assets/model_manifest.json` — 196 units point at re-optimized shas
- **Origin:** the earlier "size-class game-optimize" pass (decimate + texture cap) — **predates the biome work**, not from me. Surfaced during the safety audit.
- 196 of 1014 units now reference smaller re-optimized GLBs. **All 196 new shas verified present on R2 (196/196).** Model count still 1014.
- Deploy-safe; it's a quality/size improvement over the last commit.

**Action for you:** review both diffs, decide whether to commit + include in the next build. If you want to stage them separately, A1 (biomes) and A2 (units) are independent.

---

## PART B — `.ctex` texture-compression pipeline (prototype-validated)

### B1. Why (the core finding)
Because the game **streams raw GLB from R2 and loads at runtime**, every texture decodes to **uncompressed RGBA in VRAM**. A 2048² PBR set (albedo+normal+ORM) ≈ **64 MB VRAM**; the mesh ≈ 1 MB. **Textures are ~50× the mesh cost** — they are the VRAM wall, not triangles.

Research verdict (all other paths are dead ends in a shipped Godot build):
- ❌ Runtime `Image.compress()` — encoders stripped from export templates (`ERR_UNAVAILABLE`).
- ❌ Runtime KTX2 / Basis / `KHR_texture_basisu` in GLB — all decode to uncompressed RGBA `Image`.
- ❌ Draco/meshopt mesh compression — still unsupported at runtime; keep geometry decimation.
- ✅ **Only viable path: offline-baked Godot `.ctex` (CompressedTexture2D), streamed, loaded at runtime.** It stays GPU-compressed in VRAM.

### B2. Prototype proof (done, on this machine, Godot 4.6.2 headless)
2048² albedo from `heavy_sword`, imported with `compress/mode=2` + `compress/high_quality=true` + mipmaps:
- Output: `albedo.png-<hash>.bptc.ctex`, **5.33 MB** (vs **21.3 MB** raw RGBA) = **¼ VRAM**.
- Loaded at runtime via `load("res://tex/albedo.png")` → `CompressedTexture2D`, `get_image().get_format()` = **22 = `FORMAT_BPTC_RGBA` (BC7)**, mipmaps intact — **stays BC7-compressed in VRAM**, not decoded.
- BC7 is near-lossless → **quality kept**. Full PBR set projection: ~53 MB → **~12 MB VRAM** per material set.

### B3. What ModelForge will PRODUCE (my side — the producer)
For each asset, instead of one GLB with embedded PNG/JPEG textures:
- **Mesh** as a lightweight GLB (geometry only, no embedded textures).
- **Textures** as separate `.ctex` files, VRAM-compressed with the correct role:
  - **Albedo/base color → BC7** (sRGB) — `compress/mode=2`, `high_quality=true`.
  - **Normal → BC5** (2-channel, reconstruct Z) — import as Normal Map role. **Never BC1 for normals.**
  - **ORM / masks → BC7** (linear) — or BC4 for a single-channel mask.
- All content-addressed, uploaded to R2 alongside a new manifest entry.
- Baked with a **pinned Godot tools build (4.6.x)**; the manifest will carry the `godot_version` used.

Manifest addition (proposal): each unit gains a `ctex` representation, e.g.
```json
"faction/unit": {
  "mesh": { "url": "<sha>.glb", "sha256": "...", "size": ... },
  "textures": {
    "albedo": { "url": "<sha>.ctex", "sha256": "...", "size": ... },
    "normal": { "url": "<sha>.ctex", ... },
    "orm":    { "url": "<sha>.ctex", ... }
  },
  "godot_version": "4.6"
}
```
(Exact shape open for discussion — I'll match whatever your loader wants.)

### B4. What the GAME needs to do (your side — the consumer)
This is the integration I can't do blind — it lives in your asset-loading structure (`biome_library.gd`, `asset_cdn.gd`, the unit/model loader):
1. **Load mesh + textures separately** instead of a single GLB-with-embedded-textures.
2. **Runtime-load the downloaded `.ctex`.** The prototype loaded via the import cache (`res://`). For a file downloaded from R2 you need the runtime path — likely download to `user://cache/<sha>.ctex` then `ResourceLoader.load("user://cache/<sha>.ctex")` (returns a `CompressedTexture2D`). **Please confirm the exact API that works for a `.ctex` outside `res://`** — this is the one open technical unknown; `CompressedTexture2D.load()` / `ResourceLoader.load()` on a `user://` path is the expected route.
3. **Assign to `StandardMaterial3D`**: `albedo_texture`, `normal_texture` (+ `normal_enabled=true`), and ORM channels (`ao_texture`/`roughness_texture`/`metallic_texture` per your channel packing).
4. **Version guard:** compare `godot_version` in the manifest to `Engine.get_version_info()`; if mismatched, fall back to the raw-GLB path (see risks) rather than loading a possibly-incompatible `.ctex`.

### B5. Performance (what it buys — never costs frames)
- **VRAM:** ¼ (2048² albedo 21→5.3 MB). Keeps everything resident → no VRAM-exhaustion stutter.
- **Bandwidth:** GPU reads ¼ the bytes per texture fetch — directly helps the bandwidth-limited Steam Deck (shared LPDDR5). Hardware block-decompression is **free** (built into the texture units).
- Net: **smoother, potentially higher FPS on Deck**, at kept quality. Smaller R2 downloads too.

### B6. Formats — Steam Deck (RDNA2) + desktop
- **All BC formats supported** on RDNA2 (Vulkan `textureCompressionBC` mandates BC5/BC6H/BC7). Use BC7 (albedo/ORM), BC5 (normals).
- **ASTC is NOT available on desktop RDNA2 / Steam Deck — do not ship ASTC.** (A future native Android build would need ASTC/ETC2 re-bakes — separate target.)

### B7. Honest risks / caveats
1. **`.ctex` is Godot-version-coupled** (biggest risk). A `.ctex` baked with one version/export config can fail to load on a mismatched runtime (godot#108024). → Pin Godot between bake and game; re-bake on engine upgrade; keep the raw-GLB fallback path.
2. **Normal-map mip artifacts** under compression are a known Godot issue (godot#57981) — validate visually; BC5 + Normal Map role mitigates most.
3. Bake stage needs a **Godot tools build** in the ModelForge CI (encoders present) — my side.
4. Keep geometry decimation (Draco/meshopt remain unusable).

### B8. Suggested integration order (de-risk)
1. I produce **one** unit as `.ctex`+mesh on R2 (e.g. `heavy_sword` / one body).
2. You wire a **minimal loader path** for that one asset, confirm it renders + measure VRAM (`Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)`) raw-GLB vs `.ctex`.
3. If good, I roll out the bake stage across the catalog; you generalize the loader + version guard.

---

## READY TEST ASSET — `heavy_sword`, live on R2 (integrate this first)

Baked end-to-end by `ctex_bake.py` (Godot 4.6.2 headless) and uploaded — all reachable at `https://assets.niemandsland.xyz/<url>` (HTTP 206 verified):

```json
{
  "godot_version": "4.6",
  "mesh":    { "url": "2f594fb35778ca218070f401c9e9eb7b4c42abaa6f1eb8861e3a11aa5847c78c.glb",  "size": 1172232 },
  "textures": {
    "albedo": { "url": "1c1c8709e2c22056a36091ab85bb30f418cba1add2f57bddc33ef23027718dca.ctex", "size": 5592484 },
    "orm":    { "url": "0df4c479343843b9ae12a8fbfe5927848c10f807399ef9ba0e47af6120cc826e.ctex", "size": 5592484 }
  }
}
```
- **mesh.glb** = geometry + UVs + 1 material slot, **no embedded images** (40k tris).
- **albedo.ctex / orm.ctex** = 2048² BC7 (`FORMAT_BPTC_RGBA`), with mipmaps. (This asset has no normal map — TRELLIS bakes detail into albedo; other assets will add a `normal` BC5 `.ctex`.)
- **ORM note:** this is the glTF metallic-roughness texture (G=roughness, B=metallic). Wire to `StandardMaterial3D` roughness/metallic channels accordingly.

### Integration test (the de-risk step)
1. Download the 3 files to `user://cache/` and load:
   - `var mesh = load_glb(mesh_url)` (your existing GLTF path)
   - `var albedo := ResourceLoader.load("user://cache/<albedo_sha>.ctex") as CompressedTexture2D`
   - same for orm
2. Build a `StandardMaterial3D`: `albedo_texture = albedo`; roughness/metallic from `orm` (per your channel mapping); assign to the mesh.
3. Confirm it renders correctly, then read `Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)` and compare loading the **old** `heavy_sword` opt GLB vs this `.ctex` package.
4. **Please report back the one open unknown:** does `ResourceLoader.load` / `CompressedTexture2D.load()` on a `user://` `.ctex` work as expected, and does the texture memory monitor confirm it stays BC7 (not re-expanded)? That result decides the rollout.

### VRAM vs download trade-off (honest)
- **VRAM:** old opt GLB ≈ **43.6 MB** (2×2048² RGBA + mesh) → `.ctex` package ≈ **11.8 MB** (2×5.33 BC7 + 1.12 mesh) = **~73% less VRAM.** This is the Steam Deck win.
- **Download/disk:** the `.ctex` package (**~11.8 MB**) is *larger* than the current webp-in-GLB opt (~2.2 MB), because BC7 is fixed-rate while webp is lossy-variable. Assets cache locally (`user://`) after first fetch, so it's a one-time cost — but total download grows. Trade accepted because **VRAM (shared memory) is the Deck's wall, not download.** If download becomes a concern, we can drop some textures to 1024² (still BC7) per class.

### Producer tooling (my side, reusable)
`tools/model_forge/ctex_bake.py <in.glb> <out_dir>` — extracts textures by material role, bakes albedo→BC7 / MR·ORM→BC7-linear / normal→BC5 in one headless Godot pass, strips a mesh-only GLB, content-addresses, prints the manifest fragment. This becomes the `gate_opt`→publish bake stage.

## Contacts / artifacts
- Prototype project (throwaway): `/tmp/rg_props/ctex_proto/` (bake + measure scripts).
- Budget target marks & research live in ModelForge memory (`asset-budget-target-marks`, `texture-compression-and-terrain-vram`, `normal-baking-niche-only`).
- Bloated vehicles: a **voxel-remesh** pass (ModelForge `remesh_bake.py`) turns a 16 MB / 291k-tri tank into ~2.8 MB / 27k tris with better geometry — orthogonal to texture compression, applied per unit-class.
