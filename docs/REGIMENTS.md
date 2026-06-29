# Age of Fantasy: Regiments — Design Notes

A focused reference for the Regiments (AoF:R) subsystem. The full code map lives in
[`ARCHITECTURE.md`](ARCHITECTURE.md); this doc captures the design decisions, the
player-facing controls, and where each rule lives in code. Rule citations refer to
**Age of Fantasy: Regiments v3.5.1** (the `aofr` game system).

Niemandsland is a **sandbox tool, not an automated game** (see
[`CODING_STANDARDS.md`](CODING_STANDARDS.md) §"show, don't decide"). The Regiments
code **measures, visualises and synchronises** — the players apply the rules.

## Files

| File | Role |
|---|---|
| `scripts/regiment.gd` | Metadata companion + **pure wound-pool logic** (`pool_max`, `alive_mask_for_wounds`, `wounds_on_model`, `is_pooled_tough1`). Back rank dies first (p.9). |
| `scripts/regiment_tray.gd` | The rigid parent block (facing = local +Z). Facing-arrow + four 45° arc quadrants. Axis-locked drag projection. Quarter-turn snap. |
| `scripts/regiment_formation.gd` | Pure ranks-and-files layout. `default_frontage` (5/3), `next_frontage` (cycle 5→4→3→2→1). |
| `scripts/regiment_facing_visualizer.gd` | Display-only facing aids: arrow + four coloured arc quadrants (Front/Flank-Left/Rear/Flank-Right, each 90°, p.5). `classify_arc` pure helper. |
| `scripts/opr_army_manager.gd` | Owns `regiments` dict; `form_regiment`/`restore_regiment`, `cycle_selected_regiment_frontage`, `apply_regiment_wounds`/`regiment_take_casualty`/`regiment_revive_casualty`, `toggle_selected_regiment_arcs`. |
| `scripts/radial_menu_controller.gd` | Regiment radial menu routing + the shared unit-boundary wound token (`update_regiment_wound_token`). |
| `scripts/network_manager.gd` | Regiment RPCs: `broadcast_regiment_frontage`/`sync_regiment_frontage`, `broadcast_regiment_wounds`/`sync_regiment_wounds`. |
| `scripts/undo_manager.gd` | `FrontageAction` (frontage cycle undo), `RegimentWoundAction` (pooled-wound undo). |

## Player controls

| Control | Key | Rule |
|---|---|---|
| Toggle 45° arc quadrants (selected unit only) | `F` | p.5 "Unit Facing" |
| Cycle frontage (5→4→3→2→1) | `Shift`+`F` | p.6 "Unit Formations" |
| Axis-locked drag (forward/backward only) | `Shift`+drag | p.8 (Rush/Charge forward-only) |
| Snap to nearest 90° facing | `Ctrl`+`R` | p.8 "Pivoting" |
| Mouse-driven rotation (tray turns to cursor) | `R` (hold) | p.8 "Pivoting" |
| Take/revive casualties (pooled Tough(1)) | Right-click model → `W` | p.9 "Remove Casualties" |

## Pooled-wound counter (Tough(1) regiments)

A Tough(1) regiment is treated as a single Tough(pool) entity for the wound
counter (a 10-model Tough(1) unit = Tough(10)). The **WoundMarker token** (the same
disc + "WOUNDS" arc + number used for per-model wounds) sits on the **unit
boundary** (alongside Fatigued/Shaken/Activated) and counts casualties **UP** from 0.

- **Open the dialog:** right-click a regiment model → `W n/n` → the standard
  `WoundsDialog` opens with a proxy `ModelInstance` (`wounds_max = pool_max`,
  `wounds_current = remaining`). +/- / Heal Full / Kill adjust the pool.
- **On change:** `OPRArmyManager.apply_regiment_wounds(regiment, taken)`
  recomputes each model's alive/wounds state from the pooled counter (back rank
  dies first), re-ranks the block, refreshes the boundary wound token, and
  broadcasts to peers. Undoable via `RegimentWoundAction`.
- **Tough(X>1) regiments keep classic per-model wounds** — each model absorbs its
  Tough value before dying; the standard per-model wounds dialog applies. The
  pooled counter does not engage (`is_pooled_tough1` returns false).

## Facing display (45° arc quadrants)

`RegimentFacingVisualizer` renders four 90° quadrants around the block centre
(±45°, AoF:R p.5): front (cyan), flank-right (amber), rear (red), flank-left
(amber). Toggled with `F` on the **selected regiment only** (not all). The
measure-tool label uses `classify_arc` to read Front / Left Flank / Rear / Right
Flank. Arc radius is 18″ (3× the original 6″) so the quadrants read clearly on a
6×4 ft table; the label font is ~20% of the original size.

## Mouse-driven rotation

Regiment trays rotate by **mouse control**, not a continuous spin: while `R` is
held, the tray turns to face the cursor (`atan2` of the cursor-tray direction).
A floating label shows the **angle between the current cursor direction and the
gesture's start facing** (not a running sum), anchored above the pivot. Plain
models keep the continuous spin (R-hold) and group rotation (Shift+R).

## Save/Load

`Regiment.to_dict()` persists `frontage`, `wounds_taken`, and the tray transform.
`OPRArmyManager.restore_regiment` rebuilds the tray at the saved transform and
calls `apply_regiment_wounds(taken)` — the model alive/dead states, the re-ranked
block, and the boundary wound token are all restored from the counter.

## MP sync

- `broadcast_regiment_frontage(unit_id, new_frontage)` → `sync_regiment_frontage`
  re-ranks the peer's block to the same width.
- `broadcast_regiment_wounds(unit_id, wounds_taken)` → `sync_regiment_wounds`
  recomputes the peer's model states + re-ranks + refreshes the wound token.

Both are `@rpc("any_peer", "call_remote", "reliable")` (discrete state changes,
not high-frequency).

## What is NOT built (out of scope)

Per [`AGENTS.md`](../AGENTS.md), Niemandsland does not automate combat/morale.
The following are **player-applied**, not coded:

- Melee resolution (Quality to-hit, AP, Defense to-wound, wounds).
- Morale tests (Shaken/Routed) and melee resolution (wounds + full rows).
- Consolidation moves, Ambush/Scout deployment automation.
- Flank/rear charge morale modifiers (the arc label shows the facing; the player
  applies the -1/-2).

A future **Solo/Co-Op AI** module (see [`SOLO_AI_PLAN.md`](SOLO_AI_PLAN.md)) would
optionally automate these behind a feature flag — separate from the sandbox.
