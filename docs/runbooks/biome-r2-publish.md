# Runbook — publish biome battlemaps to R2

Generate the 6 biome battlemaps and deliver them on demand from Cloudflare R2, exactly
like the miniatures (see [`../ASSET_DELIVERY.md`](../ASSET_DELIVERY.md)). The game ships
**no** battlemap binaries; it fetches the selected biome at runtime and caches it.

Run this on the **build machine** (it needs the secrets, which are git-ignored and never
in the cloud session): `tools/model_forge/.gemini_key` and `tools/model_forge/.r2_credentials`
(see `.r2_credentials.example` for the keys: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
`R2_ENDPOINT`, `R2_BUCKET`).

## Prerequisites

- Python deps: `google-genai`, `Pillow`, `boto3` (`pip install google-genai Pillow boto3`).
- `tools/model_forge/.gemini_key` — a Gemini key with access to `gemini-3-pro-image`
  (image generation is billable; 6 × 4K images cost a few cents to a couple of euros).
- `tools/model_forge/.r2_credentials` — the same R2 bucket the miniatures use.

## Steps

```bash
cd tools/model_forge

# 1. Generate the 6 battlemaps -> assets/terrain/biomes/<biome>.webp (git-ignored).
#    ~5056x3392 native (Gemini 3 Pro Image, scale-locked 6x4 prompt) -> 1.5x + unsharp -> WebP.
python generate_battlemaps.py                 # all 6 (skips any that already exist)
# python generate_battlemaps.py --only frozen_tundra   # one biome
# python generate_battlemaps.py --force               # re-roll all

# 2. Build the manifest + upload the WebPs to R2 (content-addressed <sha>.webp).
python publish_biomes.py --upload-r2 \
  --bucket <bucket> --endpoint https://<account-id>.r2.cloudflarestorage.com
#   (omit --upload-r2 to only (re)build assets/biome_manifest.json locally)

# 3. Commit the regenerated manifest (the only thing that goes into git).
cd ../..
git add assets/biome_manifest.json
git commit -m "feat(terrain): publish biome battlemaps to R2"
```

## Verify

- `assets/biome_manifest.json` lists all 6 biomes with `url`/`sha256`/`size`.
- Launch the game, open a table, switch biomes: each loads (first time downloads from R2,
  then is cached in `user://biome_cache/`). Before the first publish — or offline — the
  table shows `table_surface_default.png` and logs no error.
- 6×4 ft shows the whole image; 4×4 ft shows a centred crop at the same real-world scale.

## Notes

- **Idempotent / immutable.** `generate_battlemaps.py` skips existing WebPs unless
  `--force`; R2 objects are named by sha256, so re-uploads skip unchanged files.
- **Regenerate vs reuse.** Re-running `generate_battlemaps.py` produces *new* images
  (Gemini is non-deterministic) with the same look/scale. To ship specific approved
  images instead, drop them into `assets/terrain/biomes/<biome>.webp` and run step 2 only.
- **Builds stay lean.** The WebPs are git-ignored; a fresh clone / CI build has none and
  bundles none. If you do a local export *after* generating, exclude
  `assets/terrain/biomes/*.webp` from the export preset (matching the miniature GLBs).
- **Prompts / scale.** The per-biome prompts and the scale-lock live in
  `generate_battlemaps.py` (`BIOMES` + `PROMPT_TEMPLATE`); adjust there if a biome needs
  tuning, then `--force --only <biome>`.
