# 0003. Generated-board dressing: the grid is the truth, modules are the look

- Status: Accepted
- Date: 2026-11-23

## Context

A generated board starts as a layout from the seeded generator in the rules core
(`core/nml-core/src/boardgen/`, reached as `NmlCore.boardgen_layout`): a lattice of cells, each
with one level, lot kind, ladders between levels and landmarks. Rules, movement and line of sight
read that layout. The plain 3D view of it (`scripts/boardgen_greybox.gd` and the town builders)
is honest but looks like a greybox.

The ruin-town look needs authored detail: house panels, ruined faces, chimneys, rubble, ladders,
vegetation. Authored detail can lie to a player - a wall drawn where a model can stand, a ledge
drawn where there is no surface, clutter hiding a ladder. On a wargame table that is a rules
defect, not a cosmetic one.

## Decision

The layout grid stays the **gameplay truth**; authored modules only **dress** it.

- `scripts/boardgen_dress.gd` (`BoardgenDress`) is the orchestrator. It asks one planner per class
  of the board (`PLANNERS`: houses, tiers, ladders, walls, towers, ground, props, clutter; each
  `scripts/boardgen_dress_<class>.gd` with `const MODULES` and `static func plan(layout, ctx)`)
  for placements `{module, xf, cls}`, merges them into one mesh with one surface per shared
  material (`scripts/boardgen_dress_mesh.gd`) plus a low-poly shadow proxy, and lets a planner add
  extras.
- A class switches from the old look to modules only when its planner exists **and** its modules
  are usable (`BoardgenDressKit.usable`: all known to the manifest, none a stub, the kit cached,
  Medium quality and up). Without a kit nothing is dressed and the board draws as before.
- Every placement is checked against the **honesty rules** in
  `scripts/boardgen_dress_rules.gd` (`BoardgenDressRules.violations`), plain arithmetic in board
  inches over the layout and the numbers each module declares in the manifest:
  - **R1** - a walkable cell at ground level keeps its column free: nothing between `FLAT`
    (0.08 in) and `CLEAR` (2.0 in) above it.
  - **R2** - above `CLEAR` only an overhang of at most `OVERHANG` (0.35 in) from a taller
    footprint.
  - **R3** - a drawn face sits 0 to `REACH` (0.2 in) inside its collider face and leans at most
    `LEAN_MAX` (1.5 degrees).
  - **R4** - over a walkable raised tier cell, below `CLEAR`, only the `EDGE` strip (0.4 in) along
    an edge that drops to a lower neighbour, and no higher than `PARAPET` (0.7 in); a module tagged
    `R4_gable` (a ruin gable) may stand there at most 0.3 in thick and 2.6 in high.
  - **R5** - the ladder zones carry only ladders and plain faces.
  - An unknown module is reported as `R0`. The only other exceptions are tags a module declares
    in the manifest (`R1_exception`, and `bulky_ok` / `terrain_or_solid_only` over terrain cells).
- **The soft-vegetation exception** (`SOFT_VEG`, 0.4 in): a module tagged `soft_veg` has no
  collider and gives no cover, so on the ground it is no obstacle up to 0.4 in (R1 does not
  apply below that). On a tier top R4 still applies, and soft vegetation never enters a
  kept-clear cell (both cells of a ladder, every landmark footprint; `kept_clear`).

## Consequences

- A debug build runs `violations` on every dressed board and prints each break as a warning;
  the dressing tests (`test/boardgen_dress_rules_test.gd`, the planner tests such as
  `test/boardgen_dress_houses_test.gd`) assert that the planners place honestly.
- The rules core never reads the dressing. A dressing change can never change a rules result,
  and no epoch ([ADR 0002](0002-rules-epochs.md)) is involved.
- A new planner or module must declare its numbers in the manifest
  ([ADR 0004](0004-dressing-materials-and-kit-manifest.md)) so the rules can check it; a module
  the rules cannot judge is not drawn.
- Changing a limit above changes what players can trust about the board; it is a decision that
  updates this ADR, not a tuning value.
