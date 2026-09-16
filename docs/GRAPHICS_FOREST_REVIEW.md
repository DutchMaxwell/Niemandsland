# Forest material and ground-contact review

Grassland terrain trees receive a matte foliage material with restrained colour
grading, height-based canopy variation and soft backlighting. The atlas's green
regions drive the grading; bark keeps its source colour outside that mask. The
shader uses the original albedo atlas and leaves all vertex positions unchanged.
It applies only to the unprefixed deciduous variants in `TreesLibrary`. Themed,
cutout, normal-mapped, emissive and vertex-coloured imports keep the existing
standard-material path. Packed-scene cache keys distinguish the two material paths.

Free-standing grassland trees also receive a thin leaf-litter plane with irregular,
feathered edges. It reuses the bundled `assets/sandbox_forest_floor.webp`. The plane
has no collider, casts no shadow and clips at the table boundary. Grouped sandbox
forests already have their own floor pad and do not receive another one.

[Eight before/after comparisons](https://forge.niemandsland.xyz/static/grafikvergleich-wald-2026-09-16/index.html)

The independent baseline is main `7472feee`, with the same original lighting and
board surface on both sides. The separate grassland and lighting drafts are not
included. This is a material pass, not a new tree asset set: silhouette quality,
baked texture detail and the existing mesh density still limit close-up realism.

## Capture and timing

The bundled tutorial board has 54 miniature objects and 10 game units. Captures
use Forward+, Medium, 1920x1080, NVIDIA GeForce RTX 3070 Ti Laptop GPU, fixed seed,
identical camera transforms and VSync off. Four views in both Day and Sunset
include a forest-focused view. HUD, terrain overlays, deployment zones, fires and
atmospheric clouds are hidden equally; unit outlines remain visible. Stars have
time-dependent animation. Screenshots are unedited game renders.

Baseline and changed captures ran consecutively without a parallel Godot test
process, with 90 warm-up frames and 180 frame-interval samples per view.

| View | Before median / P95 (ms) | After median / P95 (ms) |
| --- | ---: | ---: |
| sunset_forest | 7.104 / 7.484 | 6.960 / 7.297 |
| sunset_overview | 12.389 / 12.965 | 12.319 / 12.890 |
| sunset_miniatures | 8.608 / 9.024 | 8.260 / 8.659 |
| sunset_terrain | 9.567 / 10.113 | 9.509 / 9.984 |
| day_forest | 9.545 / 9.919 | 9.340 / 9.941 |
| day_overview | 11.335 / 11.889 | 11.243 / 11.574 |
| day_miniatures | 9.591 / 10.056 | 9.176 / 9.698 |
| day_terrain | 11.292 / 11.869 | 11.216 / 11.745 |

[Raw before measurements](https://forge.niemandsland.xyz/static/grafikvergleich-wald-2026-09-16/before/metrics.json) ·
[Raw after measurements](https://forge.niemandsland.xyz/static/grafikvergleich-wald-2026-09-16/after/metrics.json)

These are laptop spot checks, not a general performance claim. Leaf litter adds
one transparent two-triangle draw per eligible tree with a shared material. It
reuses a shipped texture; no binary assets or model downloads are added. Runtime
foliage grading samples the existing atlas once and preserves mipmaps/anisotropy.

## Validation

- Editor import and 24 targeted gdUnit cases pass (tree library, scatter decor,
  base terrain projection). Tests cover source-material/mesh preservation,
  richer imported materials and cosmetic ground-cover eligibility.
- All three actual cached deciduous GLBs were inspected: each uses the foliage
  shader after loading. Imported geometry and source files are untouched.
- Eight captures completed in Forward+ and Compatibility without shader errors
  or pink surfaces. Compatibility was a desktop renderer smoke check, not a web
  export or a claim of matching colours between renderers.
- Existing ObjectDB/two-resource cleanup diagnostics occur on both baseline and
  changed capture shutdown; Compatibility also reports unsupported screen-space AA.
- The public page passes a fresh-browser check of eight pairs, original 1920x1080
  images, controls, script errors and 390px mobile layout.

To reproduce, use isolated user data with populated model/biome/tree caches. Copy
`test/manual/forest_capture.gd` into an unchanged baseline checkout, then run the
same command on both revisions on a real display:

```sh
godot --headless --editor --quit --path .
godot --path . --audio-driver Dummy --resolution 1920x1080 \
  -s res://test/manual/forest_capture.gd -- <output_directory>
```

## Sources

Existing Niemandsland art: `assets/sandbox_forest_floor.webp` and tree atlases from
`assets/trees_manifest.json`, consumed via the documented asset-delivery cache.
Project art remains CC-BY-SA 4.0; new code follows the repository MIT license.
No new generated or third-party bitmap/model assets are introduced.
The shaders use Godot 4.6's documented
[spatial material outputs](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html).
