# Grassland reference scene

An opt-in, playable visual reference on the existing tutorial board, retaining
its original 54 miniatures. The September 17 revision concentrates detail in
one woodland/ruin slice: TRELLIS branch anatomy with fine textured leaf cards, short meadow grass, bent dry fescue, low rosettes and fallen straw,
angular embedded grit and folded leaf scatter, reconstructed stone props, wall-foot debris,
world-aligned earth/woodland blending, a procedural reflection sky and
coordinated directional lighting. A winding wear mask connects exposed soil
with vegetation placement. Layered woodland litter and mixed-height grass
replace the earlier evenly distributed small clumps; lower daylight creates
longer, readable plant shadows. The reflection sky is code-generated and
requires no external HDRI asset.

Production startup, miniature GLBs/materials, terrain collision, footprints,
LOS and saved board geometry are unchanged. The reference is separate from
production until visual and performance review.

## Run

Import with `godot --headless --editor --quit --path .`, then use a real display:

```
godot --path . res://scenes/visual/grassland_reference.tscn
```

The normal miniature/terrain caches must be populated. New reference props
use their own manifests in `assets/terrain/reference/hero/`, `{cdn}` expansion
and the existing SHA-256-verified asset downloader. No binary GLBs are committed.
If a prop cannot be fetched, the study retains procedural trees and small stones.
Use isolated XDG data/config directories for review to protect user preferences.

## Reproduce the comparison

```
godot --path . --resolution 1920x1080 --audio-driver Dummy \
  -s res://test/manual/biome_reference_capture.gd -- <before-directory> before quick studio
godot --path . --resolution 1920x1080 --audio-driver Dummy \
  -s res://test/manual/biome_reference_capture.gd -- <after-directory> after quick studio orbit
```

`quick` captures two daytime cameras; omit it for five cameras and two moods.
`studio` applies the same 1.25 internal resolution scale, 8192 directional
shadow atlas, three-metre shadow range and small-scale SSAO/SSIL settings to
both sides. The reference lighting also uses this quality level when launched
interactively. Viewport scaling/TAA and the configured shadow atlas are restored
on exit. Higher quality is confined to this reference, not a production default.

`orbit` writes 240 actual engine frames in `flight_frames/`. Encode at 30 fps
for an eight-second camera flight. Offline frame recording is not an FPS test.
The separate still-image timings use 90 warm-up frames and 180 measured frames
per camera, VSync disabled. Camera transforms and timings are saved in JSON.

The original state, September 16 intermediate at `8bc5e758`, and new reference
use identical cameras and studio settings. Original PNG captures are retained;
WebP copies are format conversions, without compositing or retouching. The
original generated concept is labelled separately from actual engine images.

Latest quality comparison against the previous reference:
https://forge.niemandsland.xyz/static/woodland-quality-2026-09-17/index.html

Earlier original/intermediate/reference comparison:
https://forge.niemandsland.xyz/static/hero-biome-2026-09-17/index.html

Previous comparison and separately simulated menu prototype:
https://forge.niemandsland.xyz/static/biome-reference-2026-09-16/index.html

## Scope and limits

- Detail is concentrated around the example woodland/ruin slice. This is not
  the finished vegetation budget for an entire board or every biome.
- Initial grid forests are dressed from the loaded board. Live terrain editing,
  biome switching and newly moved miniature exclusion zones are not rebuilt;
  reload the reference scene to reset the dressing.
- All new dressing is non-colliding. The capture verifies unchanged LOS volumes
  and wall segments. Sub-millimetre mesh relief and shading affect only the visible table surface;
  collision and the rule surface stay flat.
- Original miniatures and their materials remain intact. Base tops sample the
  same world-aligned ground texture; no miniature regeneration is required.
- Alpha-card grass and generated tree topology still require distance LODs and
  a production performance budget. Forward+ is the reviewed renderer. Do not
  infer web/Compatibility parity from these desktop captures.
- Existing ObjectDB/two-resource warnings on shutdown also occur in baseline.
- The previous HTML menu study remains a simulated prototype, separate from
  this environment work and the actual game HUD.

## Asset provenance and generation

See `assets/terrain/reference/provenance.json`, `hero/provenance.json`, the
per-model JSON manifests, and `assets/terrain/reference/LICENSE.md`.

NanoBanana (Gemini 2.5 Flash Image) generated original ground, bark, leaf, grass
and prop sources. Only the oak used an image reference: the project's own
previously generated battlefield concept. TRELLIS.2 reconstructed the new
terrain props. Visual outputs are attributed to Niemandsland Contributors
under CC BY-SA 4.0; code/procedural geometry is MIT. Tool/service/dependency
licenses remain separate; no blanket license claim is made for those tools.

The direct TRELLIS `image_to_3d` endpoint bypasses the upload callback. Final
inputs use the existing project's deterministic white-key/deshadow routine,
with an asset-specific threshold recorded in provenance. Their explicit alpha
is supplied to the server's `preprocess_image` endpoint, which takes its
`has_alpha` branch, crops and conditions to RGB. This bypasses its optional
BRIA background-removal service. Early trials using automatic background
removal were excluded from the shipped manifests and public renders.

The oak retains TRELLIS branch geometry. `reference_canopy.gd` classifies the
source foliage colour and replaces those surfaces with folded cards using the
original NanoBanana leaf texture, avoiding waxy reconstructed leaf clumps.
This heuristic is specific to this reference oak, not a general asset importer.
Its shared runtime mesh is built once per load. The latest canopy uses fewer,
larger leaves to open the twig structure. Reference shader textures receive
mipmaps at runtime because the default project import disables them. This reference-only preparation requires no project-setting changes. The small rock is reduced to
3000 faces with UVs/textures preserved. All generation seeds, conditioning
hashes and final GLB hashes are recorded; existing miniature pipeline code
and models are unchanged.

## Validation

The capture uses the real main scene, tutorial board, original UI and asset
loading. It checks rule geometry after dressing. Relevant existing regression
suites are `base_terrain_projection_test`, `terrain_overlay_test` and
`sandbox_terrain_test`; CI additionally covers the full suite, launch smoke,
multiplayer and exports. Current capture measurements and validation results
are reported with the PR, not extrapolated to all hardware or renderers.
