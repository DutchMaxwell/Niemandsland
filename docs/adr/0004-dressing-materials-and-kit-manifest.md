# 0004. Dressing materials and the kit manifest

- Status: Accepted
- Date: 2026-11-23

## Context

The dressing of [ADR 0003](0003-generated-board-dressing.md) draws a whole board from about a
hundred authored modules. Drawn one node per module with one material per piece, that is
thousands of draw calls and a look that changes from module to module. The rules that judge a
module need its numbers (bounds, how far it stands proud, tags) without loading its mesh, and the
modules' licences and texture sources must be traceable.

## Decision

**One manifest.** `assets/ruintown_dress.json` describes the kit: `units` (inches in the file,
GLB geometry in metres, glTF +Y up), `axes`, the height `bands` (`flat`, `clear`), and the
blocks `modules`, `materials`, `ground`, `sets` and `licence`. Each module entry carries the
numbers the honesty rules and the merge read: `family`, `role`, `len_in`, `height_in`, `aabb_in`,
`proud_in` per band, `openings`, `shadow` hulls, `tags`, `materials`, `tris`, `stub`. Each texture
set records its source and licence. `scripts/boardgen_dress_kit.gd` (`BoardgenDressKit`) loads
it once; the module GLBs come from the town kit's cache.

**Shared named materials.** A module's surfaces are named by the shared material they are drawn
with (the GLB's material name, for example `ct_stone`, `ct_timber`, `ct_roof`). The merge
(`scripts/boardgen_dress_mesh.gd`) puts every surface of one material across all modules into one
surface, so the whole board is a handful of draw calls. `scripts/boardgen_dress_materials.gd`
(`BoardgenDressMaterials.make`) builds one material per manifest entry:

- a textured entry (`set`) becomes a `ShaderMaterial` of `shaders/ruintown_dress.gdshader` with the
  set's albedo / normal / ORM maps; while the set is not cached it is a flat
  `StandardMaterial3D` in the entry's tone - never null;
- a plain entry (`colour`) is a `StandardMaterial3D` with colour, roughness, metallic and
  optional emission;
- the vegetation entry (`shader: "veg"`, `ct_veg`) uses `shaders/ruintown_dress_veg.gdshader` in
  two variants, `ct_veg` (modelled plants) and `ct_veg_card` (alpha-tested card tufts from the
  `grass_cards` atlas); a card module names its surface `ct_veg_card`
  (`BoardgenDressKit.surface_name`) because the two variants cannot share a surface.

**World vs mesh UV.** Each textured entry chooses its projection with `uv`:

- `world` - the merged mesh is in board space, so the shader projects the set from the vertex
  position in inches along the normal's dominant axis; the pattern runs on across neighbouring
  modules (masonry, plaster, flagstones);
- `mesh` - the authored mesh UV (in inches) is used, for materials whose pattern follows the
  piece (roof tiles, timber).

`tile_in` gives the inches of board one texture tile covers. Masonry uses one continuous lookup
per set, without per-fragment offsets.

## Consequences

- Adding a module means adding its manifest entry with all contract keys, and its surfaces must
  use material names the manifest defines; the kit and materials tests
  (`test/boardgen_dress_kit_test.gd`, `test/boardgen_dress_materials_test.gd`) check the
  manifest shape, the stub boxes, the surface names and that every uniform the script sets is
  declared by the shader.
- Draw calls scale with the number of materials, not of modules; a new material is a deliberate
  cost.
- Without cached textures the board still draws (flat tones, invisible cards); the dressing never
  fails a board for a missing download.
- A material's look is data in the manifest, not code; code changes only for a new kind of
  material.
