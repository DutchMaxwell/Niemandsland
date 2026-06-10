# Asset Delivery — on-demand 3D models (R2)

**Status: LIVE.** Miniature GLBs are delivered on demand from **Cloudflare R2**
(`<legacy-cdn-host>`, content-addressed `<sha256>.glb`), mapped by
`assets/model_manifest.json` — **113 models across 5 factions** today (Alien Hives,
Robot Legions, Battle Brothers, Dao Union, a Dark Brothers hero). The GLBs are
git-ignored and excluded from every export preset, so the repo and shipped builds
stay lean; the editor/game fetches each needed model at runtime and caches it. A
model with no manifest entry falls back to a primitive/placeholder (no crash).
Publish more via [`runbooks/asset-release.md`](runbooks/asset-release.md). The
client + tooling are `asset_download_manager.gd`, `model_library.gd`,
`opr_army_manager` integration, and `tools/model_forge/publish_manifest.py`.

## Goal

Keep the repository *and* the shipped build lean by **not bundling** the 3D
miniature models. Instead, deliver them like Tabletop Simulator does: download an
asset over the internet on first use, cache it locally, and only ever fetch the
models an imported army actually needs. Today's ~0.5 GB of GLBs would grow to
several GB at the full 855-unit scale — untenable to bundle.

**Important consequence:** because size is no longer a repo/build constraint, we
**no longer compromise model quality for size.** The `model_forge` optimizer
defaults were raised accordingly (light decimation + 2048² textures instead of
10 %/1024²; see `tools/model_forge/glb_optimizer.py`). Source quality stays full.

## What we already have (reuse, don't rebuild)

- **`scripts/tts_download_manager.gd`** — a working HTTP download + cache manager
  (`user://tts_cache/…`, `is_cached`/`find_cached_file`, progress signals, chunked
  HTTPRequest). This is exactly the on-demand pattern, already built for TTS imports.
- **Runtime GLB loading** via `GLTFDocument.append_from_file()` is already used
  (`object_manager.gd`, `terrain_library.gd`) — so downloaded GLBs load at runtime
  with **no build-time import** needed. (This is usually the hard part.)
- `opr_army_manager` currently loads *bundled* GLBs via `ResourceLoader.load()`;
  the on-demand path switches those units to the `GLTFDocument` runtime path.

## Architecture

```
Army import (OPR API)  →  unit list
        │
        ▼
   Manifest (small JSON, our data)     unit → { url, sha256, size }
        │  "which models does this army need?"
        ▼
 AssetDownloadManager  →  user://model_cache/<sha256>.glb   (fetch only missing, parallel, progress)
        │  (verify sha256)
        ▼
 GLTFDocument.append_from_file()  →  spawn (existing scaling + _brighten_trellis_materials)
        │
        └─ no model in manifest? → existing primitive/placeholder fallback
```

- **Content-addressed** storage (`<sha256>.glb`): immutable, dedupes across
  factions/armies, cache-forever, integrity-checkable.
- The **manifest** maps our model identity → URL/hash/size. It is *our* data
  (model↔unit mapping), **not OPR data** — OPR stats/base sizes still come from the
  API (see `docs/PRE_RELEASE_LICENSING.md`).

## Hosting

- **Chosen: Cloudflare R2** (public bucket behind a custom domain). Egress is always
  free, storage is cheap ($0.015/GB-mo, 10 GB free), and it serves anonymous direct
  **HTTP 200** GETs (no redirect chain) at stable, content-addressed URLs
  (`https://assets.<domain>/<sha256>.glb`) — so the client fetches with a one-line
  `base_url` change and zero new code. The default `r2.dev` URL is dev-only/rate-limited;
  production needs a custom domain on Cloudflare DNS. Upload via
  `publish_manifest.py --upload-r2` (boto3 / S3 API; build-machine-only credentials in
  `.r2_credentials`, git-ignored — the public bucket needs no key in the client).
- **Quick/free alternative: GitHub Releases** on a dedicated PUBLIC assets repo
  (`--upload`). Zero-config, but only fair-use tolerance (history of account-wide
  "503 egress over limit", 2025 anon rate-limits, 1000-assets/tag cap) — fine for a
  prototype, fragile as a player-facing CDN.
- **Licensing gate (host-independent):** anonymous public URLs = public redistribution.
  Only publish models you are cleared to redistribute. See `PRE_RELEASE_LICENSING.md`.

## Migration path (incremental, low-risk)

1. ✅ `asset_download_manager.gd` (content-addressed download + cache) +
   `model_library.gd` (resolve unit→entry via manifest, cache, runtime GLTF load).
   The **bundled-GLB path remains as a fallback** so nothing breaks.
2. ✅ `tools/model_forge/publish_manifest.py`: builds `assets/model_manifest.json`
   (content-addressed) and can upload the GLBs to a GitHub release via `gh`.
3. ✅ `opr_army_manager` resolution order: **cached on-demand model → bundled
   fallback → placeholder**; `spawn_army` downloads the army's models up front.
4. ✅ R2 is live + the manifest is populated; GLBs are removed from the working tree
   and excluded from builds → lean repo and build (the web build no longer needs the
   ~1.3 GB `.pck`). Remaining: a git-history scrub of the old in-repo GLBs to shrink
   `.git` itself (see [`runbooks/history-scrub.md`](runbooks/history-scrub.md) and
   the licensing doc).

## Publishing (go live)

Step-by-step runbook: [`runbooks/asset-release.md`](runbooks/asset-release.md).

**Cloudflare R2 (chosen).** One-time: create an R2 bucket, attach a custom domain, make
a build-only API token; put the creds in `tools/model_forge/.r2_credentials` (see
`.r2_credentials.example`). Then:

```bash
cd tools/model_forge
python publish_manifest.py ../../assets/miniatures ../../assets/model_manifest.json \
  --base-url https://assets.<domain>/ \
  --upload-r2 --bucket <bucket> --endpoint https://<account-id>.r2.cloudflarestorage.com
```

**GitHub Releases (quick alternative):**

```bash
python publish_manifest.py ../../assets/miniatures ../../assets/model_manifest.json \
  --base-url https://github.com/<owner>/<repo>/releases/download/<tag>/ \
  --upload --tag <tag> --repo <owner>/<repo>      # needs `gh` + an existing release tag
```

Commit the regenerated `assets/model_manifest.json` only when going live. The game then
downloads each needed GLB on first use and caches it in `user://model_cache/`.

## Web / HTML5 notes

- `HTTPRequest` works in-browser; the asset host must send **CORS** headers (GitHub
  Releases do; R2 is configurable).
- `user://` in the web export is IndexedDB-backed, so the cache persists
  per-origin (subject to the browser's storage limits).

## Biome battlemaps (same pattern, separate manifest)

The table **biome battlemaps** (play-surface ground textures) use the identical
on-demand mechanism, with their own small manifest `assets/biome_manifest.json`
(`{ version, base_url, biomes: { <key>: { url: "<sha>.webp", sha256, size } } }`) and
client `biome_library.gd` (mirrors `model_library.gd`) on top of the shared
`asset_download_manager.gd` (cache `user://biome_cache/<sha>.webp`). Each of the 6 biomes
is a single, **non-tiling, scale-locked** 6×4-ft image generated via Gemini 3 Pro Image
and sharpened to WebP (`tools/model_forge/generate_battlemaps.py`), then uploaded with
`tools/model_forge/publish_biomes.py --upload-r2`. The WebPs are git-ignored and never
bundled; `table.gd` fetches the selected biome at runtime, renders it across a fixed 6×4-ft
extent (centre-cropping smaller tables — `table_ground.gdshader` `uv_scale`), and falls
back to the bundled `assets/terrain/table_surface_default.png` until a biome is cached.

Step-by-step (run on the build machine, with `.gemini_key` + `.r2_credentials`):
[`runbooks/biome-r2-publish.md`](runbooks/biome-r2-publish.md).

## Ruin shell-wall panels (same pattern, separate manifest)

The textured **ruin shell walls** fetch their 9 runtime masonry panels (solid/top-damage/
doorway/window/crumble variants + normal map, 800×720 WebP) the same way:
`assets/ruins_manifest.json` (`{ version, base_url, panels: { <name>: { url, sha256,
size } } }`) + client `ruins_library.gd` on the shared `asset_download_manager.gd`
(cache `user://ruins_cache/<sha>.webp`). The panels live under the R2 source-art prefix
`terrain-source/ruins/` (named files; the manifest's sha256 still guarantees integrity
and content-addresses the cache). `terrain_overlay.gd` keeps its triplanar stone material
as the offline fallback and upgrades walls in place when the download lands. Panels are
decoded at runtime via `load_webp_from_buffer`, preserving the authored hard alpha edges
that the alpha-scissor holes need. Art recipe + design record:
[`HANDOFF_RUIN_WALLS.md`](HANDOFF_RUIN_WALLS.md).

## Trees: billboards + volumetric GLBs (same pattern, separate manifest)

The **deciduous forest trees** are delivered in two tiers from one manifest
(`assets/trees_manifest.json`, client `trees_library.gd` on the shared
`asset_download_manager.gd`, cache `user://trees_cache/<sha>.{webp,glb}`):
`panels` — 6 keyed-alpha WebPs (3 side silhouettes oak/ash/linden + 3 bird's-eye crown
caps) for the lightweight billboard tier; `models` — 3 textured TRELLIS GLBs (100k
tris, 2k texture) for the volumetric tier. Files live under the R2 prefix
`terrain-source/trees/` (named; the manifest's sha256 content-addresses the cache).
`terrain_overlay.gd` upgrades progressively: holographic trunk+cone fallback ->
billboards as soon as the small panels land -> volumetric models once the GLBs are
cached. Art recipes: `tools/model_forge/generate_trees.py` (Gemini renders, magenta
chroma key -> hard alpha) and `generate_tree_models.py` (TRELLIS image-to-3D + R2).

## Container faces (same pattern, separate manifest)

The **blocker containers** fetch their 6 face textures (2 colourways × corrugated
side / cargo-door end / roof, full-bleed RGB WebP) the same way:
`assets/containers_manifest.json` + client `containers_library.gd` on the shared
`asset_download_manager.gd` (cache `user://containers_cache/<sha>.webp`). Files live
under the R2 prefix `terrain-source/containers/`. `terrain_overlay.gd` keeps the
holographic box as the offline fallback and upgrades blockers in place when the
download lands. Art recipe: `tools/model_forge/generate_containers.py`.

## Minefield hazards (same pattern, separate manifest)

The **dangerous-terrain minefield** fetches its 2 textures (keyed-alpha anti-tank-mine
top + full-bleed warning sign) the same way: `assets/hazards_manifest.json` + client
`hazards_library.gd` on the shared `asset_download_manager.gd` (cache
`user://hazards_cache/<sha>.webp`). Files live under the R2 prefix
`terrain-source/hazards/`. `terrain_overlay.gd` keeps holographic mine/sign props as
the offline fallback and upgrades in place. Art recipe:
`tools/model_forge/generate_hazards.py`.

## Biome themes

The ruins, trees and containers manifests carry **per-biome panel sets** under a name
prefix (default unprefixed set = grassland; `desert_*` = adobe walls + cacti for
`arid_desert`; `tundra_*` = snowed castle stone + snow-laden conifers + snowed
containers for `frozen_tundra`). The libraries take the prefix in `all_panels_cached`
/ `ensure_all_panels` (+ model equivalents); `terrain_overlay.gd` maps biome -> prefix
via `BIOME_PROP_THEMES` (ruins/trees) and `BIOME_CONTAINER_THEMES` (containers — only
the tundra themes them) and re-themes walls/props in place when `table.set_biome`
runs. Minefield hazards are biome-agnostic.

**Still future:** modular terrain GLBs (walls) and larger map sheets — extend the same
pattern when we get there.
