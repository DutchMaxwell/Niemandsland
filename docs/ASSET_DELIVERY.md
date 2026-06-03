# Asset Delivery — on-demand 3D models (plan)

**Status: client + tooling implemented (behind a bundled fallback); pending = publish
a release and populate the manifest.** Sequence: (1) plan ✅ → (2) prototype ✅
(`asset_download_manager.gd`, `model_library.gd`, `assets/model_manifest.json`,
`opr_army_manager` integration, `tools/model_forge/publish_manifest.py`) →
(3) hosting on **GitHub Releases** (no egress/traffic cost). While the manifest is
empty the game uses bundled models exactly as before (zero regression); once it is
populated the CDN path goes live.

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
4. ⏳ Once a release is published + the manifest populated: remove GLBs from the repo
   (+ history scrub, see licensing doc) → lean repo and build; the web build no
   longer needs the ~1.3 GB `.pck`.

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

## Later: same pattern for terrain & map sheets

The owner wants terrain and **map sheets** (table textures / play mats) delivered
the same way. They are larger, less-frequently-used assets — ideal for on-demand.
`model_forge` already generates battle maps at 1536×1024 (`app.py`); with on-demand
delivery these can also be produced at higher quality without bloating the build.
Extend the manifest with `terrain/` and `maps/` sections when we get there.
