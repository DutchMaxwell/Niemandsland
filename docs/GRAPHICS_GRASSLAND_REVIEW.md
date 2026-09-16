# Grassland material review

The grassland ground replaces oversized bright straw/leaf detail with connected
moss and earth patches. Lower, clustered grass tufts leave the miniature silhouettes
clearer. Board and miniature bases share the same surface sampling. Only
`temperate_grassland` enables the new material; other biome shader paths stay unchanged.
No lighting, table geometry, collisions, footprints or game rules change.

[Interactive before/after review](https://forge.niemandsland.xyz/static/grafikvergleich-grasland-2026-09-16/index.html)

The comparison uses main `3f780924` as the baseline, independently of the lighting
PR. Six unedited 1920x1080 captures use the bundled tutorial board (54 miniature
objects, 10 game units), Medium quality, Forward+, NVIDIA GeForce RTX 3070 Ti Laptop
GPU, fixed seed and exactly matching camera transforms. Both sides hide HUD,
terrain overlays, deployment zones, atmospheric clouds and fires. The unit outline
remains visible. Grass and stars have time-dependent animation.

## Performance

Frame intervals, milliseconds; 90 warm-up frames then 180 samples per view, VSync
off. These sequential laptop runs are a spot check, not a controlled benchmark.

| View | Before median / P95 | After median / P95 |
| --- | ---: | ---: |
| sunset_overview | 12.583 / 13.439 | 12.122 / 12.520 |
| sunset_miniatures | 8.848 / 9.330 | 8.487 / 8.755 |
| sunset_terrain | 9.846 / 10.607 | 9.369 / 9.670 |
| day_overview | 11.857 / 12.726 | 11.192 / 11.593 |
| day_miniatures | 9.844 / 10.444 | 9.325 / 9.632 |
| day_terrain | 11.808 / 12.417 | 11.091 / 11.593 |

[Raw baseline measurements](https://forge.niemandsland.xyz/static/grafikvergleich-grasland-2026-09-16/before/metrics.json) ·
[Raw changed measurements](https://forge.niemandsland.xyz/static/grafikvergleich-grasland-2026-09-16/after/metrics.json)

The new texture adds 598,386 source bytes (584 KiB), with mipmaps and high-quality
VRAM compression. The shared shader adds four texture samples in the grassland
branch. Grass retains one MultiMesh draw call with fewer visible instances.

## Reproduction and validation

Use an isolated user-data directory with the model and biome caches populated.
For the baseline, copy the capture harness into an otherwise unchanged checkout
of `3f780924`. Run the same harness on both checkouts on a real display:

```sh
godot --headless --editor --quit --path .
godot --path . --audio-driver Dummy --resolution 1920x1080 \
  -s res://test/manual/grassland_capture.gd -- <output_directory>
```

- Editor import succeeded without script errors.
- 29 targeted gdUnit tests passed: base terrain projection, base decor and atmosphere presets.
- The new biome-switch regression test fails against unchanged production code,
  then passes with the shared material binding. It also checks existing base
  material instances update when switching grassland to desert and back.
- Six real-display captures completed in both Forward+ and `gl_compatibility`,
  without shader errors or pink surfaces. Compatibility was a desktop shader
  smoke check, not a browser export or a visual parity claim.
- The capture harness emits an existing ObjectDB/two-resources-in-use warning at
  shutdown on both baseline and changed code. This is outside this visual change.
  Compatibility also reports the existing unsupported screen-space AA setting.
- The public comparison was checked in a fresh browser: all six original image
  pairs, comparison controls, 390px mobile layout and no script errors.

## Asset provenance

The new [grassland texture](../assets/terrain/materials/grassland_surface.webp) is
original Niemandsland art generated with the built-in OpenAI image tool, with no
third-party reference, and released under CC-BY-SA 4.0. It was resized from
1254x1254 to 1024x1024 and encoded as WebP quality 90. The exact prompt and method
are in the [asset README](../assets/terrain/materials/README.md). This is an albedo
texture plus procedural relief, not a scanned PBR asset set.
