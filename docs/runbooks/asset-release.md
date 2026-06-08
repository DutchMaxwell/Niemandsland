# Runbook — publish miniature models to Cloudflare R2 (on-demand go-live)

**Purpose:** upload the miniature GLBs to **Cloudflare R2** and (re)generate
`assets/model_manifest.json` so the game fetches models **on demand** instead of
bundling them. Background: [`../ASSET_DELIVERY.md`](../ASSET_DELIVERY.md).

> Live today: **113 models across 5 factions** on `<legacy-cdn-host>` (Alien
> Hives, Robot Legions, Battle Brothers, Dao Union, a Dark Brothers hero). This
> runbook is how you publish more.
>
> Runs **locally** (needs the GLBs + R2 credentials). Low-risk and repeatable:
> models are content-addressed (`<sha256>.glb`), the manifest is small, and the
> game falls back to a primitive/placeholder for any unmapped model.

## 0. Prerequisites

```bash
python3 --version                          # for publish_manifest.py (boto3 / S3 API)
ls assets/miniatures/*/glb/*.glb | head    # GLBs present locally
test -f tools/model_forge/.r2_credentials && echo "R2 creds present"   # git-ignored
```

R2 one-time setup (already done for `<legacy-cdn-host>`): create a public R2
bucket, attach a custom domain on Cloudflare DNS, mint a build-only API token, and
put the creds in `tools/model_forge/.r2_credentials` (see `.r2_credentials.example`).
The public bucket needs **no** key in the client.

## 1. Generate the manifest + upload to R2 (one step)

```bash
cd tools/model_forge
python publish_manifest.py ../../assets/miniatures ../../assets/model_manifest.json \
  --base-url https://<legacy-cdn-host>/ \
  --upload-r2 --bucket <bucket> --endpoint https://<account-id>.r2.cloudflarestorage.com
```

This writes `assets/model_manifest.json` (keys `faction/unit`, sha256, size) and
uploads each GLB as `<sha256>.glb` to the bucket. Re-runs are idempotent
(content-addressed: identical bytes → identical key, already-present objects are
skipped). The faction batch pipeline wraps this as `faction_publish.py` (R2 upload
+ manifest merge) — prefer it when finalizing a whole faction.

## 2. Commit the regenerated manifest

```bash
git add assets/model_manifest.json
git commit -m "chore(assets): publish <faction> models to R2 (manifest update)"
git push
```

## 3. Verify in-game

- Import an army → its models download from `<legacy-cdn-host>` and cache in
  `user://model_cache/<sha256>.glb` (a second import does not re-download).
- No manifest entry → primitive/placeholder fallback (no crash).
- Spot-check a URL is live: `curl -I https://<legacy-cdn-host>/<sha256>.glb`
  should return `HTTP/2 200`.

## Notes

- **`base_url` must end in `/`** and match the bucket's public domain exactly; the
  client concatenates `base_url + <sha256>.glb`.
- GLBs are **git-ignored** (`assets/miniatures/*/glb/`,
  `assets/terrain/grimdark_industrial/`) **and** excluded from every export preset
  — they are delivered from R2, never bundled. Keep it that way.
- **Licensing gate (host-independent):** anonymous public URLs = public
  redistribution. Only publish models you are cleared to redistribute
  (CC-BY-SA, IP-safe). See [`../PRE_RELEASE_LICENSING.md`](../PRE_RELEASE_LICENSING.md).
- R2 serves anonymous direct `HTTP 200` GETs with configurable CORS, so the same
  URLs work in the desktop **and** web builds.
- Repo size: the GLBs were removed from the working tree once R2 went live; for a
  full repo shrink they also need stripping from git history — see
  [`history-scrub.md`](history-scrub.md).
