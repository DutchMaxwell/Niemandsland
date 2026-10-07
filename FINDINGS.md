# FINDINGS — why our own CI is most of the model-CDN traffic

Measured by the lead (Cloudflare, zone niemandsland.xyz, last 24 h):
`assets.niemandsland.xyz` served 66,681 requests / 71.9 GB; by user agent the honest
product UA `Niemandsland/0.3.13.1-alpha (Linux; Godot 4.6)` from US datacentres accounted
for 62,637 requests / 64.9 GB — i.e. our GitHub Actions runners (`ubuntu-latest` on Azure
eastus2), not players.

## 1. Where CI fetches from the live CDN

The asset host and the UA live in exactly one place:

- `scripts/asset_cdn.gd:13` — `HOST = "https://assets.niemandsland.xyz"` (the live CDN).
- `scripts/asset_cdn.gd:31` — `user_agent()` builds the honest product UA; `:38` `headers()`.
- `scripts/asset_download_manager.gd:186` and `:232` — every model/ctex/idle blob download
  goes through `AssetCDN.headers()` (the shared cache dir, `:10` `user://model_cache`).

The dominant request in CI is the **live manifest**, not the blobs:

- `scripts/model_library.gd:70` — `_refresh_remote_manifest()` runs from `_ready()` on every
  real scene boot.
- `scripts/model_library.gd:537` — builds `https://assets.niemandsland.xyz/model_manifest.json`
  (the result is always JSON, `:551`).
- `scripts/model_library.gd:542` — the `HTTPRequest` that downloads it.

Evidence, run `37601301091` (Build and Export, main, success, 2026-10-07):

```
gh run view 37601301091 --log | grep -c "live manifest applied"
107
```

107 live fetches for one CI run. The live `model_manifest.json` is ~1,098,701 bytes
(`assets/model_manifest.json` is the same size, the bundled offline fallback), so one run
pulls ~112 MB of manifest alone. The test job boots the real `scenes/main.tscn` in every
`test/e2e/**` suite (`test/e2e/e2e_boot.gd:18` `MAIN_SCENE`), and the export jobs smoke-run
the exported build; each boot re-fetches the manifest. The live manifest currently carries
1,776 models vs 1,014 in the bundled one.

CI jobs that boot the game (and therefore fetch the CDN):

- `.github/workflows/build.yml:109-121` — gdUnit4 test job (the bulk: every e2e boot).
- `.github/workflows/build.yml:102,212,299,371,586` — project import (editor, no scene boot:
  no CDN fetch, listed for completeness).
- `.github/workflows/build.yml:259` — Linux export smoke-run; `:446,463,478` — macOS
  smoke/probe runs (each one manifest fetch).
- `.github/workflows/mp-nightly.yml:60-72` — the OPR full-army soak intentionally imports a
  live Army Forge army and downloads its models (best-effort, once daily).
- `.github/workflows/mp-two-instance.yml` — two headless peers booting the real scene.

A second, separate CDN path exists but under a **different** UA (a fake browser string), so
it is not part of the 64.9 GB attributed to the product UA — noted only so it is not
mistaken for a model fetch:

- `scripts/main.gd:16749-16754` — `_fetch_cdn_text()` fetches `ai_lists/...` from the same
  host with `User-Agent: Mozilla/5.0 (X11; Linux x86_64) Niemandsland`. The repo must not
  ship `assets/ai_lists/` (hygiene), so CI solo-AI tests fall back to this. Out of scope
  for this change; it is the one other place a UA string is built and should later route
  through `AssetCDN.headers()`.

## 2. User-agent marker

`scripts/asset_cdn.gd:user_agent()` now appends `" CI"` when `GITHUB_ACTIONS=true` or
`CI=true`, so CI traffic is countable apart from players without changing the honest product
UA (Cloudflare still sees a real product string). RED test first:
`test/asset_cdn_test.gd:test_user_agent_marks_ci_runs`.

## 3. The change (and why this one)

Two parts, because caching blobs alone does not reach "near zero" — the ~1 MB manifest itself
is fetched on every boot and is not part of `user://model_cache`.

1. **Local fixture instead of the live manifest in CI.** A new offline seam
   (`NML_SKIP_REMOTE_MANIFEST=1`) makes `_refresh_remote_manifest()` keep the bundled
   `assets/model_manifest.json` that `_ready()` already loaded. It only skips the DEFAULT live
   root fetch: an explicit `NML_MANIFEST_URL` (a test's local fixture server, dev staging)
   still wins, so `test/asset_download_throughput_test.gd:128` keeps working. `build.yml` sets
   it for all jobs. This is the smaller change versus adding a manifest disk cache + a new
   cache key, and it reuses the existing offline-fallback contract
   (`model_library.gd:504-507`).
2. **actions/cache for the CDN blob caches** under `user://` in the test job, keyed by the
   bundled manifest hash. Blobs are content-addressed and immutable, so a warm run downloads
   0 blobs. Cached dirs: `model_cache` (the models/ctex/idle cache the brief asks for) plus
   the other asset caches that also use the honest product UA (`biome_cache`,
   `ambience_cache`, `containers_cache`, `hazards_cache`, `ruins_cache`, `trees_cache`,
   `reference_terrain_cache`), so a warm run is near-zero on the whole UA, not just models.

`user://` on the Linux runner is `~/.local/share/godot/app_userdata/Niemandsland/`
(`config/name` in `project.godot`).

Not changed: `mp-nightly.yml`'s OPR soak intentionally imports a live Army Forge army and
downloads its models (once daily, `continue-on-error`), and `mp-two-instance.yml` boots two
peers; both can adopt the same seam later if their runs matter for the traffic budget.

## 4. Proof (after the lead pushes)

Run the PR twice; the second run's `gdunit_output.log` must show no
`[ModelLibrary] live manifest applied` lines and no new blob downloads (the cache step
reports a hit), i.e. (near) zero `assets.niemandsland.xyz` requests from that run.
