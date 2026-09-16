# Grassland reference scene

An opt-in, playable art-direction study using the existing tutorial board and
its original 54 miniatures. It adds three NanoBanana-generated ground textures,
world-aligned meadow/earth/woodland blending shared with miniature base tops,
three procedural tree variants, short grass, a subdued table frame and player
trays, and a coordinated day/evening light treatment.

Production startup, the miniature library, source GLBs, manifests, original
terrain geometry, collision layers, footprints and LOS are unchanged. The
scene is deliberately separate from the production game until visual review.

## Run

Import once with `godot --headless --editor --quit --path .`, then launch on a
real display:

```
godot --path . res://scenes/visual/grassland_reference.tscn
```

The existing asset caches must be populated for the reference miniatures and
terrain; otherwise the game's normal download/fallback behavior applies. Use
isolated XDG data/config directories for review so user saves and graphics
preferences are not affected by the capture harness.

## Before/after

```
godot --path . --resolution 1920x1080 --audio-driver Dummy \
  -s res://test/manual/biome_reference_capture.gd -- <before-directory> before
godot --path . --resolution 1920x1080 --audio-driver Dummy \
  -s res://test/manual/biome_reference_capture.gd -- <after-directory> after
```

The harness uses the same board, seed, four cameras and two moods on both sides.
It verifies that applying the presentation leaves LOS volumes and wall segments
unchanged. Each image has 90 warm-up frames and 180 frame-time samples. The
quality preset is Medium at 1920x1080 with VSync disabled. `game_ui.png` retains
the existing actual game HUD; the separate web menu/HUD study is a prototype.

Public comparison and clickable menu study:
https://forge.niemandsland.xyz/static/biome-reference-2026-09-16/index.html

## Scope and limitations

- This is an integrated reference composition, not a replacement of all biome
  rendering. Initial grid forests are dressed from the loaded board. Editing
  the terrain layout or switching biomes after application is not yet supported
  by the presentation layer. Reload the reference scene to reset it.
- Three procedural tree variants explore visible branches and open foliage.
  They are not a finished botanical asset library; finer branch anatomy,
  vegetation variation, distant LODs and ruin contact dressing remain work.
- Ground textures use mirrored dual sampling to avoid seams in generated
  tiles. Fine relief is cosmetic. No terrain displacement changes rules.
- Existing miniature materials and models are retained. Base tops sample the
  new ground material; no miniature regeneration or global import changes.
- HTML menu flow is a design study, with explicit demo states for joining,
  importing, measuring, activation and results. It is not the game's real UI.
- Frame-time results are laptop spot checks, not a stress test or a web FPS
  guarantee. Compatibility capture is only a desktop renderer check; foliage and
  environment brightness differ and still need renderer-specific calibration.
- Baseline ObjectDB/resource warnings at exit also occur without this study.

## Asset provenance

New bitmap assets and their per-file source prompts/hashes are in
`assets/terrain/reference/provenance.json`, with CC-BY-SA-4.0 attribution in
`assets/terrain/reference/LICENSE.md`. They were generated through the existing
NanoBanana/Gemini image generator from original text, with no reference images.
They are 1024-square WebP files. Tree/grass geometry and all shaders are original
MIT project code. No third-party game content or new miniature GLBs are included.

## Validation of this reference

The editor import passes without script errors. All 39 cases across
`base_terrain_projection_test`, `terrain_overlay_test` and
`sandbox_terrain_test` pass. The separate entry scene loads the tutorial board
with the original UI, and the capture harness verifies unchanged LOS volumes
and wall segments. Forward+ and desktop Compatibility produce actual images.

Eight pairs use identical recorded camera transforms. At 1080p Medium on an
RTX 3070 Ti Laptop, the daytime miniature view measured 9.24 ms median before
and 7.18 ms after (180 samples each); these are local spot measurements.
The public report includes every median and P95 result, the original PNGs,
and a separate browser-tested, explicitly simulated menu/HUD design study.
