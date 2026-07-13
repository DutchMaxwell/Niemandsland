# Manifest Delivery — the layering model

How the game decides *which* on-demand assets a client sees. This consolidates the
manifest side of [`ASSET_DELIVERY.md`](ASSET_DELIVERY.md) (which covers the download +
cache mechanics) into one place for contributors. **No private URLs, tokens or bucket
names live here** — the pipeline that produces and publishes assets is a separate
private repository (see [`ASSET_DELIVERY.md`](ASSET_DELIVERY.md)).

## The three layers

A running client resolves a unit → model from a single in-memory index
(`scripts/model_library.gd`, `_models`). That index is built by overlaying, in order:

1. **Bundled fallback** — `assets/model_manifest.json`, shipped in the build.
   Loaded first in `ModelLibrary._ready()` so the game works offline / on first run.
2. **Live CDN root** — `{cdn}/model_manifest.json`, fetched at startup
   (`_refresh_remote_manifest()`) and applied **over** the bundled fallback. This is
   how an asset fix published *after* a build shipped reaches players on their next
   launch, with no re-export. A unique `?t=` query busts CDN caches; any failure
   (offline / 404 / malformed) silently keeps the bundled layer. The client sends an
   honest product User-Agent (`AssetCDN.headers`).
3. **Dev / QA override** (optional, local, loud) — consulted **before** the live root
   so the maintainer can point one client at a *staged* manifest before it goes live:
   - `user://manifest_override.json` holding a full manifest (`{"models": …}`) →
     applied offline; or
   - the `NML_MANIFEST_URL` env var, or that same file holding `{"url": "…"}` →
     fetched **instead of** the root.
   Both paths `print` + `push_warning` a `MANIFEST OVERRIDE` line so an overridden
   client is never mistaken for a normal one.

> **Live root = base + fix-waves.** The live root manifest on the CDN is the shipped
> baseline plus every asset fix-wave re-published since. It is the source of truth for
> what is actually live; the bundled file is only the offline mirror. Never publish to
> the root without maintainer QA — a client fetches it at every launch.

## Staged → pilot → live (how a new faction goes live)

A new / reworked faction (e.g. the Mummified Undead modular-sockets pilot) is not made
live by editing the root directly. The flow is:

```
private pipeline  →  staged manifest (CAS, content-addressed)
        │                 │
        │        maintainer points a QA client at it
        │        (NML_MANIFEST_URL / manifest_override.json)   ← layer 3 above
        │                 │
        │           QA passes on-table
        ▼                 ▼
   root-manifest FLIP  →  live for everyone (bundled fallback re-committed here)
```

- **CAS (content-addressed storage):** every blob is stored under its `sha256`, so a
  staged manifest and the live root can share unchanged blobs; only the manifest JSON
  and the new blobs differ. The review/publish tooling that produces the staged
  manifest lives in the **separate private repository**.
- **Per-entry overrides travel in the manifest**, read by `model_library.gd` and
  applied in `opr_army_manager.gd` (precedence **manifest > Army Forge API > derived**):
  - `base_mm` — `{"round": 80}` / `{"round": "90x52"}` / `{"square": …}`; wins over the
    AF base recommendation where the AF spec reads wrong on the actual model.
  - `fit_scale` — a multiplicative artistic size correction applied after the normal fit.
  - `long_axis` — `"x"` / `"z"`; the **only** driver of a model's lengthwise oval
    rotation (geometry cannot express authored facing — see [`ARCHITECTURE.md`](ARCHITECTURE.md#miniatures--the-mount--rider-system)).
  Unknown fields are ignored by construction, so old clients and old manifests are
  unaffected — the overrides are additive and forward-compatible.

## ctex (compressed-texture) blocks

A manifest entry may carry a `ctex` block (decimated mesh + BC7 `.ctex` textures). It is
used **only** when it is baked for this engine version and carries a downloadable albedo
in a form the loader supports; otherwise the entry degrades to the legacy raw GLB —
never to "no model" (the J0 forward-compat guard, `ModelLibrary._ctex_block_usable`).
`.ctex` assets keep their extension in a separate cache so `ResourceLoader` resolves
them as `CompressedTexture2D`.

## Terrain manifests

The biome battlemaps, ruin walls, trees, containers and hazards each use the identical
layering on their own small manifest + client library — see the table in
[`ASSET_DELIVERY.md`](ASSET_DELIVERY.md#terrain-assets-same-pattern-separate-manifests).
