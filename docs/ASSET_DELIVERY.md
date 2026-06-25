# Asset Delivery — on-demand 3D models (R2)

> **CDN host = one source of truth.** Manifests never hardcode the host; they
> store the `{cdn}` token in `base_url` (e.g. `"{cdn}/terrain-source/trees"`).
> The game expands it via `scripts/asset_cdn.gd` (`AssetCDN.HOST`). To move asset
> delivery to a new domain, change that `HOST` constant — no manifest edits.

**Status: LIVE.** Miniature GLBs are delivered on demand from **Cloudflare R2**
(content-addressed `<sha256>.glb`, host in `scripts/asset_cdn.gd`), mapped by
`assets/model_manifest.json`. The GLBs are git-ignored and excluded from every
export preset, so the repo and shipped builds stay lean; the editor/game fetches
each needed model at runtime and caches it. A model with no manifest entry falls
back to a primitive/placeholder (no crash). The client is `asset_download_manager.gd`
+ `model_library.gd`, wired into `opr_army_manager`.

> The offline pipeline that *produces* these assets (image-gen → TRELLIS → GLB,
> terrain + ambience generators, the R2 publish tools) lives in a **separate
> private repository**. This repo and the shipped game consume only its R2
> outputs; nothing from the pipeline ships in the game.

## Goal

Keep the repository *and* the shipped build lean by **not bundling** the 3D
miniature models. Instead, deliver them like Tabletop Simulator does: download an
asset over the internet on first use, cache it locally, and only ever fetch the
models an imported army actually needs. At the full unit scale the GLBs would
grow to several GB — untenable to bundle.

Because size is no longer a repo/build constraint, model quality is **not**
compromised for size: light decimation + 2048² textures, source quality intact.

## What we already have (reuse, don't rebuild)

- **`scripts/tts_download_manager.gd`** — a working HTTP download + cache manager
  (`user://tts_cache/…`, `is_cached`/`find_cached_file`, progress signals, chunked
  HTTPRequest). This is exactly the on-demand pattern, already built for TTS imports.
- **Runtime GLB loading** via `GLTFDocument.append_from_file()` is already used
  (`object_manager.gd`, `terrain_overlay.gd`) — so downloaded GLBs load at runtime
  with **no build-time import** needed. (This is usually the hard part.)
- `opr_army_manager` resolution order: **cached on-demand model → bundled
  fallback → placeholder**; `spawn_army` downloads the army's models up front.

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
  Army Forge API at runtime, never bundled.

## Hosting

- **Chosen: Cloudflare R2** (public bucket behind a custom domain). Egress is always
  free, storage is cheap, and it serves anonymous direct **HTTP 200** GETs (no
  redirect chain) at stable, content-addressed URLs (`https://assets.<domain>/<sha256>.glb`).
  The default `r2.dev` URL is dev-only/rate-limited; production needs a custom domain
  on Cloudflare DNS. The public bucket needs no key in the client; upload happens from
  the asset-pipeline repo with build-machine-only credentials.
- **Licensing gate (host-independent):** anonymous public URLs = public
  redistribution. Only publish models you are cleared to redistribute.

## Publishing

The manifests committed here are produced and uploaded from the separate
asset-pipeline repository (R2 bucket + custom domain, content-addressed upload).
A regenerated manifest (`assets/*_manifest.json`) is committed to this repo only
when going live; the game then downloads each needed asset on first use and caches
it under `user://`.

## Live manifest updates (no re-export)

The bundled `assets/model_manifest.json` is now only the **offline / first-run
fallback**. On startup `model_library.gd` *also* fetches the live manifest from
the CDN (`{cdn}/model_manifest.json`, `_refresh_remote_manifest()`) and overlays
it — so asset fixes re-published after a build shipped appear on the player's
**next launch, with no re-export**. Offline-safe: any fetch failure (offline, 404,
malformed) keeps the bundled fallback. A unique `?t=` query busts CDN caches; GLBs
stay sha-verified + content-addressed.

**Pipeline contract** (the separate asset-pipeline repo, enforced by its publish
step): on every publish it must

1. upload the new `<sha256>.glb`,
2. **not delete** the old object — already-running builds still reference it until
   they re-fetch, so deleting would 404 them mid-rollout, and
3. deploy the updated manifest to the stable key **`model_manifest.json`** with
   `Cache-Control: no-cache`.

Re-export the game only to refresh the offline fallback (and, one-time, to ship the
`_refresh_remote_manifest()` capability itself to already-installed builds).

## Terrain assets (same pattern, separate manifests)

The table **biome battlemaps**, **ruin shell-wall panels**, **forest trees**,
**blocker containers** and **minefield hazards** all use the identical on-demand
mechanism, each with its own small manifest and client library on top of the
shared `asset_download_manager.gd`:

| Asset | Manifest | Client | Cache |
|---|---|---|---|
| Biome battlemaps | `biome_manifest.json` | `biome_library.gd` | `user://biome_cache/` |
| Ruin shell walls | `ruins_manifest.json` | `ruins_library.gd` | `user://ruins_cache/` |
| Trees (billboards + GLBs) | `trees_manifest.json` | `trees_library.gd` | `user://trees_cache/` |
| Container faces | `containers_manifest.json` | `containers_library.gd` | `user://containers_cache/` |
| Minefield hazards | `hazards_manifest.json` | `hazards_library.gd` | `user://hazards_cache/` |

Terrain source art lives under the R2 prefix `terrain-source/<kind>/` (named
files; the manifest's sha256 still content-addresses the cache).
`terrain_overlay.gd` keeps an offline holographic/triplanar fallback for each and
upgrades the prop in place when the download lands.

### Biome themes

The ruins, trees and containers manifests carry **per-biome panel sets** under a
name prefix (default unprefixed = grassland; `desert_*` = adobe walls + cacti for
`arid_desert`; `tundra_*` = snowed stone + conifers + containers for
`frozen_tundra`). The libraries take the prefix in `all_panels_cached` /
`ensure_all_panels` (+ model equivalents); `terrain_overlay.gd` maps biome →
prefix via `BIOME_PROP_THEMES` / `BIOME_CONTAINER_THEMES` and re-themes
walls/props in place when `table.set_biome` runs. Minefield hazards are
biome-agnostic.

**Still future:** modular terrain GLBs (walls) and larger map sheets — extend the
same pattern when we get there.
