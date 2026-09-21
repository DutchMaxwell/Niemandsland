# Urban ruins reference

The opt-in reference now accepts `--biome urban_ruins` after the Godot argument
separator. The native urban trees, minefields, containers and ruin geometry are
retained. A quieter asphalt/concrete surface replaces the oversized painted
debris, with chipped pavement edges, masonry dust and small geometric fragments.
Sparse pioneer weeds grow near walls. Existing miniatures and their materials
remain intact; base caps share the world-aligned ground projection.

```sh
godot --path . res://scenes/visual/grassland_reference.tscn -- --biome urban_ruins
```

`reference_biomes.gd` supplies the urban profile. `reference_urban.gd` places
non-colliding chipped fragments and weeds, using finite wall segments for a
shared R8 contact mask. Full decorative footprints avoid miniature clearings,
native prop bounds, walls and table edges. Placement is deterministic and uses
the same reduced visual relief as the ground shader (15% of grassland relief).
Pavement-edge noise agrees between the shader and scatter placement.

The ground shader reuses three original NanoBanana mineral albedos:

- `assets/terrain/reference/volcanic/porous-basalt.webp`: asphalt aggregate.
- `assets/terrain/reference/volcanic/fine-ash.webp`: fine cement grain.
- `assets/terrain/reference/desert/scree.webp`: crushed masonry/dust grain.

The original bitmaps are unchanged. Shader luminance remapping, slab joints,
weathering and material response make the urban surface. These are artistic
approximations, not calibrated physical material scans. Original prompts,
model/provider and hashes remain in the adjacent `provenance.json` files.
Art: CC BY-SA 4.0, Niemandsland Contributors; procedural geometry/shaders: MIT.
No new generated bitmap or GLB is included in this milestone.

## Review and validation

[Matched comparison](https://forge.niemandsland.xyz/static/urban-biome-2026-09-21/index.html)
includes original unretouched PNGs, four camera pairs, source records and timings.
Capture with `test/manual/biome_reference_capture.gd`, `quick studio surface`, and
`--biome urban_ruins`, once in `before` and once in `after` mode. `orbit` adds
240 offline frames. Both sides load the native biome before the miniature and
rule-geometry snapshots; guards therefore compare against the relevant biome.

Focused tests cover decoration bounds/normals, contact-mask coordinates and
finite-wall falloff, plus prior terrain/base/forest/volcanic/jungle regressions.
Real renderer captures check all 54 miniature transforms, LOS volumes and wall
segments. Lighting, atmosphere and the table frame are part of the reference
look; this is not an isolated material benchmark.

The reference is separate from production startup. Scatter/contact masks are
built at load and require reload after moving terrain or units. Existing urban
tree geometry, flat ruin panels and painted source detail remain visible limits.
Broad performance, LODs, Compatibility/web calibration and game integration are
separate work. No new cover, collision, damage or movement rule is introduced.
