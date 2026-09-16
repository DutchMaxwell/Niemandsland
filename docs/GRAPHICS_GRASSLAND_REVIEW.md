# Grassland material review

Grassland uses connected moss/earth patches and clustered foliage. A shared,
synchronous 256x256 coverage mask places tufts on the same patches the board and
miniature bases shade as meadow. Tufts are 4-12 mm tall with nine curved blades
per card, dark roots and lighter tips. A two-sided foliage shader uses an upward
lighting normal, avoiding black backfaces on crossed cards. Ground detail normals
retain 85% of their original strength; meadow/earth roughness varies from 0.97 to 0.84.

Only `temperate_grassland` enables the new surface. Other biome shader paths,
lighting, table geometry, collisions, footprints and game rules stay unchanged.

[Interactive three-version comparison](https://forge.niemandsland.xyz/static/grafikvergleich-grasland-v2-2026-09-16/index.html)

The page can compare the current revision against either main `3f780924` or the
first material draft `a8556e2b`. The earlier published comparison is preserved at
[its original address](https://forge.niemandsland.xyz/static/grafikvergleich-grasland-2026-09-16/index.html).
This PR remains independent of the lighting PR.

All versions have six unedited 1920x1080 captures of the bundled tutorial board
(54 miniature objects, 10 game units), Medium quality, Forward+, NVIDIA GeForce
RTX 3070 Ti Laptop GPU, fixed seed and exactly matching camera transforms. Both
sides hide HUD, terrain overlays, deployment zones, atmospheric clouds and fires.
Unit outlines remain visible; stars have time-dependent animation.

## Performance

Frame intervals in milliseconds, 90 warm-up frames then 180 samples per view,
VSync off. First-draft and current measurements are consecutive control runs,
without a parallel Godot test process. Original-game timings are from the earlier
baseline capture, so these remain laptop spot checks, not a controlled benchmark.
The current medians are within 0.2 ms of the first draft. Isolated P95 spikes occur
in both control runs; these samples cannot establish a tail-latency improvement.
An earlier capture overlapping local tests was repeated, and a subsequent isolated
capture still had a sunset-overview spike. Earlier measurements are retained as
[earlier before](https://forge.niemandsland.xyz/static/grafikvergleich-grasland-v2-2026-09-16/earlier-before-metrics.json)
and [earlier after](https://forge.niemandsland.xyz/static/grafikvergleich-grasland-v2-2026-09-16/earlier-after-metrics.json).

| View | Original median / P95 | First draft median / P95 | Current median / P95 |
| --- | ---: | ---: | ---: |
| sunset_overview | 12.583 / 13.439 | 12.199 / 12.763 | 12.188 / 12.759 |
| sunset_miniatures | 8.848 / 9.330 | 8.469 / 8.792 | 8.590 / 9.115 |
| sunset_terrain | 9.846 / 10.607 | 9.435 / 19.240 | 9.628 / 10.304 |
| day_overview | 11.857 / 12.726 | 11.189 / 11.833 | 11.250 / 12.077 |
| day_miniatures | 9.844 / 10.444 | 9.329 / 9.823 | 9.412 / 20.845 |
| day_terrain | 11.808 / 12.417 | 11.098 / 11.731 | 11.264 / 12.633 |

Raw measurements: [original](https://forge.niemandsland.xyz/static/grafikvergleich-grasland-v2-2026-09-16/original/metrics.json),
[first draft](https://forge.niemandsland.xyz/static/grafikvergleich-grasland-v2-2026-09-16/before/metrics.json), [current](https://forge.niemandsland.xyz/static/grafikvergleich-grasland-v2-2026-09-16/after/metrics.json).

The albedo adds 598,386 source bytes (584 KiB), with mipmaps and high-quality VRAM
compression. The grassland branch adds five texture samples versus main. The
coverage mask is generated and cached once, R8 with mipmaps (about 85 KiB each for
CPU and GPU copies). Grass retains one MultiMesh draw call, four triangles per
tuft, and the existing quality-tier instance budgets with fewer visible instances.

## Reproduction and validation

Use isolated user data with populated model and biome caches. For the original
baseline, copy the capture harness into an otherwise unchanged checkout of
`3f780924`. Use the same harness on each revision on a real display:

```sh
godot --headless --editor --quit --path .
godot --path . --audio-driver Dummy --resolution 1920x1080 \
  -s res://test/manual/grassland_capture.gd -- <output_directory>
```

- Editor import succeeded without script errors.
- 36 targeted gdUnit tests passed: base terrain projection, base decor, atmosphere
  presets and scatter decor (biome gating, table-area scaling and grass heights).
- The biome-switch regression checks existing base instances update when switching
  grassland to desert and back, including the shared foliage-coverage texture.
- Six real-display captures completed in Forward+ and `gl_compatibility` without
  shader errors or pink surfaces. Compatibility is a desktop shader smoke check,
  not a browser export or a visual parity claim.
- The harness reports an existing ObjectDB/two-resources-in-use warning at shutdown
  on all versions. Compatibility also reports unsupported screen-space AA.
- A fresh browser verified all twelve comparison combinations, controls, original
  image dimensions, no script errors and a 390px mobile layout without overflow.

## Asset provenance

The [grassland texture](../assets/terrain/materials/grassland_surface.webp) is
original Niemandsland art generated with the built-in OpenAI image tool, without
third-party references, released under CC-BY-SA 4.0. It was resized from 1254x1254
to 1024x1024 and encoded as WebP quality 90. The exact prompt and method are in the
[asset README](../assets/terrain/materials/README.md). Coverage and blade images
are procedural, generated by the project's own `GrassField` code. This is an
albedo source plus procedural relief, not a scanned PBR asset set.
