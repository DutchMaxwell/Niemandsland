# Urban ruins reference

The opt-in city reference uses original NanoBanana textures for fractured asphalt,
battered concrete and masonry fines. Irregular wear replaces the former clean
slab grid. Low angular fragments, restrained brick accents, wall soot and localized
dust/rust/damp marks connect the native ruins to the ground. Miniatures, native
terrain meshes, source materials, collision and LOS geometry remain intact.

```sh
godot --path . res://scenes/visual/grassland_reference.tscn -- --biome urban_ruins
```

## Freely placed terrain

`reference_urban.gd` derives dressing from current finite wall segments, including
individually placed sandbox ruins. Each owner has an external visual rig that
follows translation, rotation and scale through a geometry-free transform
observer. Keeping visual meshes outside native owners preserves recursive bounds,
save serialization and rule geometry. Clipboard copies receive fresh observers.

After 120 ms without edits, the controller rebuilds decorative placements and a
shared RGBA contact texture: dust, soot, rust and dampness. During movement old
contact marks are disabled; rubble follows its owner immediately. Removed owners
lose their rigs and contact marks. Save loading, table resizing, native layout
edits and asynchronous biome material replacement restore the reference surface.
Stable owner identity seeds decoration. Shader seating keeps fragments on the
world-aligned ground after owner transforms. Full fragment footprints avoid
walls, unit bases, native props and table edges. Unit/hazard movement refreshes
clearings; a shader clearance texture also clips dressing against those areas.

This is presentation-only derived state: no new serialized terrain, multiplayer
message, movement blocker, cover or collision object. Each client can derive the
same treatment from its synchronized native terrain state.

## Sources

Three dedicated 1024-square albedos are in `assets/terrain/reference/urban/`:
`fractured-asphalt.webp`, `battered-concrete.webp`, `masonry-fines.webp`.
Generated with Google Gemini `gemini-2.5-flash-image` (NanoBanana), without source
images, on 2026-09-22. Original prompts and source/runtime hashes are recorded in
`provenance.json`. PNG originals were converted to WebP quality 90. Art: CC BY-SA
4.0, Niemandsland Contributors. Procedural geometry and shaders: MIT. These are
authored game materials, not calibrated surface scans. No new GLB is included.

## Review and validation

[Matched comparison](https://forge.niemandsland.xyz/static/urban-biome-2026-09-22/index.html)
compares the previous city candidate with this surface at unchanged camera/light
settings. It also includes the original native city, original PNGs, source records,
placement screenshots and capture timings.

`test/manual/biome_reference_capture.gd` accepts `after quick studio surface
--biome urban_ruins orbit placement`. The placement probe uses native spawn,
clipboard duplication, transforms, deletion, save/load and table resize paths.
Focused tests cover decorative bounds, contact masks, moving owners, deletion,
miniature clearings, base projection and previous biome regressions. GPU capture
guards compare all 54 original miniature transforms, native LOS and wall segments.

The reference remains separate from production startup. Existing urban tree
geometry and flat ruin panels still limit close views. Contact masks update after
movement settles rather than every drag frame. Large-layout performance, LODs,
Compatibility/web calibration and production integration remain separate work.
