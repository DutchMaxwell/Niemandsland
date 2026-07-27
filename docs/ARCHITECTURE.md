# Architecture

A map of how Niemandsland is actually put together. Engine: Godot 4.6, GDScript,
Forward+ renderer. Entry scene: `scenes/startup_menu.tscn`.

## Autoloads (singletons)

| Autoload | Script | Responsibility |
|---|---|---|
| `ThemeManager` | `theme_manager.gd` | Provides the built-in Tactical-HUD UI theme |
| `GraphicsSettings` | `graphics_settings.gd` | Quality presets (shadows, SSAO, glow) |
| `AudioManager` | `audio_manager.gd` | Audio buses / playback |
| `UiFeedback` | `ui_feedback.gd` | Global hover/press motion + UI sound for every button |
| `UpdateChecker` | `update_checker.gd` | Startup release check (GitHub Releases); see [UPDATE_CHECK](UPDATE_CHECK.md) |

`default_bus_layout.tres` (project root) is Godot's implicitly-loaded audio-bus
layout that `AudioManager` builds on — load-bearing, not clutter; do not move it.

## Scenes

- `startup_menu.tscn` — main scene; menu + `cinematic_intro.gd` animation.
- `main.tscn` — the game table; instantiates the subsystems below.
- Dialog/overlay scenes: `map_layout`, `radial_menu`, `opr_stats_tooltip`,
  `unit_card`, and the import/wounds/marker/casts dialogs.

## Subsystems (scripts/)

**Table & interaction**
- `main.gd` — top-level controller; wires subsystems and UI.
- `object_manager.gd` — spawns/selects/drags table objects; selection + box-select;
  emits selection/drag signals consumed by the unit overlays.
- `undo_manager.gd` — local undo/redo history for move/rotate/delete as reversible
  actions (Ctrl+Z / Ctrl+Y; Delete removes the whole selection). Re-broadcasts the
  result of each action so multiplayer peers stay in sync ("delete syncs, undo local").
- `hover_glow.gd` — non-destructive glow on the object under the cursor (via
  `material_overlay`) so it's clear which model a click will select.
- `camera_controller.gd` — orbit/pan/zoom with easing.
- `table.gd` — table dimensions and collision.
- `selectable_object.gd` — per-object selection behaviour.

**Measurement & display aids** (local, display-only)
- `los_rules.gd` — Asgard-standard line-of-sight height helpers (H1–H6); pure/static; powers
  the units-as-LoS-blockers option.
- `pinned_ruler.gd` / `pinned_rulers.gd` — persistent shared rulers (pin with P; replicated to
  all clients, including late-joiners).
- `range_ring_controller.gd` — per-model base-edge range rings (G cycles 3″–24″).
- `movement_range_controller.gd` — per-model Advance + Rush/Charge reach bands (M; OPR Fast/Slow aware).

**Unit model** (system-agnostic, OPR-aware)
- `model_instance.gd` — one physical miniature; generic properties dictionary
  (wounds, caster, etc.).
- `game_unit.gd` — wraps a set of `ModelInstance`s into a unit; serialization; the
  home of activation/hero-attachment state.
- `equipment_distributor.gd` — assigns weapons to models from API counts.
- `unit_utils.gd` — unit-detection helpers.
- `coherency_checker.gd` — OPR coherency: connected 1″ chain (3″ across elevation)
  + 9″ spread, via BFS connected components; edge-to-edge distances.
- `coherency_visualizer.gd` — flat on-table chain/ring/distance lines (matches the
  measure tool).
- `unit_boundary_visualizer.gd` — convex-hull boundary for multi-model units; token rail.
- `unit_marker.gd` / `unit_card.gd` — status tokens (F/S/A, wounds, caster) and the
  docked info card.
- `radial_menu.gd` / `radial_menu_controller.gd` — context pie-menu. The controller
  owns the unit-boundary token engine (Fatigued/Shaken/Activated/WoundMarker tokens
  placed on the `UnitBoundaryVisualizer` contour) and a regiment-specific menu
  (`RadialMenu.create_regiment_menu`) for Tough(1) regiments — pooled-wound counter
  (WoundsDialog via a proxy ModelInstance), frontage cycle, no per-model delete.
- `regiment.gd` / `regiment_tray.gd` / `regiment_formation.gd` /
  `regiment_facing_visualizer.gd` — Age of Fantasy: Regiments — movement-tray
  blocks, square bases, casualty re-rank, frontage/reform, and the facing display:
  - `RegimentFormation` — pure ranks-and-files layout + `default_frontage` /
    `next_frontage` (cycle 5→4→3→2→1).
  - `RegimentTray` — the rigid parent block (facing = local +Z); facing-arrow +
    four 45° arc quadrants (`RegimentFacingVisualizer`); axis-locked drag
    projection (`project_drag_onto_facing`); quarter-turn snap
    (`nearest_quarter_turn`).
  - `Regiment` — the metadata companion: `frontage`, `wounds_taken` (pooled-tough
    counter), and the pure wound-pool logic (`pool_max`, `alive_mask_for_wounds`,
    `wounds_on_model`, `is_pooled_tough1`). Back rank dies first (AoF:R p.9).

**OPR & import**
- `opr_api_client.gd` — Army Forge API client + unit data classes (incl. base sizes).
  `_apply_base_recommendation` uses Army Forge's own `bases: {round, square}` when present;
  `_apply_tough_base_fallback` derives a base from Tough only when the API gives none.
- `model_library.gd` (`ModelLibrary`) — the manifest-layering resolver the game and the
  offline pipeline share. Turns a `(faction, unit_name)` + loadout labels into a delivered
  GLB: `variant_slug` maps labels to the shared slug vocabulary (`assets/label_slug_map.json`),
  `find_faction_model_matching` does the whole-token fuzzy fallback, and per-entry `fit_scale` /
  `base_override_mm` / `long_axis_override` carry the manifest's overrides. Also owns the ctex
  (BC7) texture resolution + the `_ctex_block_usable` forward-compat guard.
- `opr_army_manager.gd` — spawns imported armies onto a per-player **army tray**; loads
  per-unit GLBs and **scales them to the base** (height-fit vs 125 % footprint cap,
  whichever is smaller; Flying units hover). See [Scaling](#scaling). The tray's near
  third is an **Ambush/Scout staging band**: split left/right with a divider + flat
  labels, and units carrying Scout/Ambush auto-place into their half. Owns the
  `regiments` dictionary and the regiment handling: `form_regiment` /
  `restore_regiment` (save/load), `cycle_selected_regiment_frontage` (Shift+F),
  `apply_regiment_wounds` / `regiment_take_casualty` / `regiment_revive_casualty`
  (pooled-tough counter, AoF:R p.9), and `toggle_selected_regiment_arcs` (F key).
- `opr_import_dialog.gd` — import UI.
- `tts_download_manager.gd` — Tabletop Simulator asset download + cache manager
  (Steam CDN + local cache; glTF/STL/OBJ); also the template for the on-demand
  R2 delivery pattern.

> **On-demand delivery (live):** miniature GLBs are downloaded + cached via `asset_cdn.gd` /
> `asset_download_manager.gd` from Cloudflare R2, resolved through `model_library.gd`, so the
> repo/build stay lean and only an army's needed models are fetched — see
> [`ASSET_DELIVERY.md`](ASSET_DELIVERY.md). OPR stats/data load only via the Army Forge API
> (never bundled).

**Solo AI (`scripts/solo/`)**

The solo opponent (**NACHTMAHR**) is a self-contained, rule-based, deterministic engine — no
machine learning, no network, same inputs → same decisions. It runs only in a solo game; a
human-vs-human table never touches it. Written from scratch against OPR's official Solo & Co-Op
ruleset (the old root-level `ai_*.gd` / `battle_simulator.gd` were removed and **not** revived).
- `solo_controller.gd` (`SoloController`) — the orchestrator wired into `main.gd`: the **AI
  Opponent** flow, the click-guided deployment (roll-off → edge → alternating placement → scout
  band → reserves), per-unit activation (`activate_next_ai_unit`), shooting / melee / morale /
  consolidation, casting, and objective scoring.
- `turn_manager.gd` (`TurnManager`) — round + alternating-activation state machine and end-of-round
  objective scoring / victory check.
- `ai_decision.gd` / `ai_round_planner.gd` / `ai_position.gd` / `ai_targeting.gd` /
  `ai_shooting.gd` / `ai_spell.gd` / `ai_combat_math.gd` / `ai_ev.gd` / `ai_archetype.gd` — the
  decision brain: round plan + look-ahead activation ordering, positioning, target and
  expected-value math, per-phase choices, and the per-archetype behaviour weights.
- `movement_planner.gd` (`MovementPlanner`) — deterministic A* movement with wall segments as real
  impassable barriers, dangerous terrain routed around, and individual models steered while the
  unit is held in coherency; `move_intent.gd` (`MoveIntent`) is the planned-move value type.
- `terrain_rules.gd` (`TerrainRules`) — applies Cover / Difficult / Dangerous / Impassable / LoS
  to the AI's moves and rolls (the solo-only mechanical terrain the sandbox only *shows*).
- `rules_registry.gd` (`RulesRegistry`) — per-game-system special-rule values (a rule name means
  different things in GF / GFF / AoF / AoFS / AoFR), driving automatic resolution for both sides.
- `spells_registry.gd` (`SpellsRegistry`) — spell definitions, token costs and the mechanical
  buff/debuff effects that feed the real dice / rings / target checks.
- `sight_fan.gd` (`SightFan`) — per-model, base-edge line-of-sight + weapon-range geometry (also
  the source for the `F`-key sight fan, presented by `sight_fan_controller.gd`).
- `transport_state.gd` (`TransportState`) — embark / capacity / disembark-formation / destruction-
  spill state (see [Save format](#save-format-nml)).
- `solo_difficulty.gd` (`SoloDifficulty`) — the single shipped grade (full strength); every legacy
  grade name resolves to it. `solo_sim.gd` (`SoloSim`) is the headless self-play harness that runs
  the same pure modules for balance/regression proofs.

**Play aids & dialogs (new in `0.3.10.0`)**
- `spell_picker_dialog.gd` (`SpellPickerDialog`) / `interference_dialog.gd` (`InterferenceDialog`)
  — the human cast flow: pick a spell (cost + live effect text), and one modal tableau to spend
  tokens interfering with an enemy cast (live odds before you confirm). Code-built, awaitable.
- `control_hints_controller.gd` (`ControlHintsController`) — hover an object → a curated hint line
  of the hotkeys that apply to it (every listed key is a verified live binding). Display-only, local.
- `pickup_ghost_controller.gd` (`PickupGhostController`) — a translucent origin silhouette while a
  drag is live (what ESC snaps back to). Display-only, local.
- `sight_fan_controller.gd` (`SightFanController`) — draws the summed `SightFan` overlay above the
  table (like `RangeRingController`); local, never synced/saved.
- `dream_spinner.gd` (`DreamSpinner`) — a self-drawn idle "thinking" spinner shown while NACHTMAHR
  computes (no external assets).

**Map & terrain**
- `map_layout.gd` / `map_layout_grid.gd` — top-down editor + 3″ grid.
- `terrain_overlay.gd` — 3D overlay + custom deployment zones.
- `sandbox_terrain_prop.gd` / `sandbox_terrain_shelf.gd` / `terrain_group_base.gd` /
  `terrain_prefabs.gd` / `terrain_hologram.gd` — free-placed 3D sandbox terrain (multi-storey
  ruins, forest pads) + biome-prefab library + hologram placement preview.
- `hazards_library.gd` / `battlefield_stains.gd` — per-biome dangerous-terrain props and
  blood/oil removal decals.

**Presentation**
- `lighting_controller.gd` / `lighting_panel.gd` — light-value presets (Day/Sunset/Night/
  Overcast/Storm), driven by the atmosphere system + the Settings lighting panel.
- `atmosphere_controller.gd` / `rain_effect.gd` / `fire_prop.gd` / `war_ambience.gd` /
  `ambience_synth.gd` / `ambience_library.gd` — one-click weather/mood, rain + lightning,
  war-torn fires and CC0 battlefield ambience (see [`ATMOSPHERE.md`](ATMOSPHERE.md)).
- `glassmorphism_theme.gd` + `hud/` (`hud_frame`, `hud_tokens`, `segmented_meter`,
  `state_panel`, `ui_motion`) — the Tactical-HUD UI language and overlay.
- `grass_field.gd`, `atmospheric_clouds.gd`, `cinematic_intro.gd`, `model_info_popup.gd`,
  `opr_stats_tooltip.gd`, `selection_spill_light.gd`.

## Save format (`.nml`)

`save_manager.gd` serializes the full table: objects, `GameUnit`/`ModelInstance`
state (positions, wounds, markers, activation), terrain layout, table size. Files use
the `.nml` extension with OS file association; the same serialization feeds
multiplayer load. Regiment blocks persist via `Regiment.to_dict()` (frontage, tray
transform, `wounds_taken`) and are rebuilt by `OPRArmyManager.restore_regiment`,
which re-applies the pooled-wound counter so model alive/dead states + the boundary
wound token are restored exactly. Transport embark state (`embarked_in` /
`cargo_unit_ids` / `embark_return_spots`) rides in `unit_properties` (`transport_state.gd`).

**Versioned migration.** `save_manager.gd` stamps a `SAVE_VERSION` (currently **1.7**).
`save_migrations.gd` (`SaveMigrations`) lifts an older file forward step by step —
`1.4 → 1.5 → 1.6 → 1.7` (1.7 = the Transport(X) embark state above). Pre-alpha formats
below `OLDEST_SUPPORTED` (`1.4`) are refused with a message; a newer-than-current file is
refused too. **Standing rule:** whoever bumps `SAVE_VERSION` ships the matching migration
step **and** a fixture test in the same change.

**Autosave.** `autosave_controller.gd` (`AutosaveController`, scene-instantiated) writes a
snapshot every ~5 minutes and at each round change, rotating over `autosave_1.nml` …
`autosave_<SLOTS>.nml` (always overwriting the oldest). In multiplayer only the host writes.
The newest slot is offered by CONTINUE / the load dialog and announced by toast + battle-log line.

## Multiplayer

- `network_manager.gd` — ENet host/join, state sync, RPCs (models, terrain, rotation,
  table size, wounds/markers/activation) with batched updates. Regiment-specific
  sync: `broadcast_regiment_frontage` / `sync_regiment_frontage` (frontage cycle)
  and `broadcast_regiment_wounds` / `sync_regiment_wounds` (pooled-tough counter).
- `relay_multiplayer_peer.gd` — custom `MultiplayerPeer` that tunnels ENet over a
  WebSocket relay for internet play.
- `relay/` — standalone Python WebSocket relay server (Fly.io deployable); see
  [`relay/README.md`](../relay/README.md).
- `internet_lobby.gd`, `player_avatar.gd`, `remote_cursor.gd` — lobby + presence.
- `player_identity.gd` — local display name + per-install client token; static helpers for
  sanitisation and slot-stable identity across reconnects.
- `import_await_guard.gd` (`ImportAwaitGuard`) — a per-player generation counter that lets a
  stalled guest army-import abort cleanly (`IMPORT_AWAIT_TIMEOUT_SEC` = 75), release the restore
  lock and recover instead of wedging the session.

The relay keeps **anonymous, aggregate** usage stats only (`relay/relay_server.py`): totals,
peaks and two coarse close-time histograms (room lifetime, peak peers per room). `games_played`
counts a room that reached ≥ 2 peers; a shutdown flush folds still-open rooms in, guarded against
double counting. No room codes, player names or IPs are ever recorded.

## Dice

Provided by our own `dice_tray.gd` + `dice_d6.gd` (MIT W6 physics), rendered in a
**separate scaled SubViewport** because miniature-scale rigid bodies are unstable in
Godot's default physics. Table dice are display-only.

## Scaling

1 unit = 1 m. API/rules in inches, world in metres, bases in mm
(`INCHES_TO_METERS = 0.0254`, `MM_TO_METERS = 0.001`). Imported GLBs are scaled in
`opr_army_manager._compute_model_fit()`: target height ≈ base size (mildly larger for
Tough), but the horizontal footprint is capped at 125 % of the base's long side
(`FOOTPRINT_MAX_RATIO`); the smaller factor wins, so slim infantry stay height-driven
while wide vehicles are footprint-capped. Flying units hover (`AIRCRAFT_HOVER_M`), and an
aircraft stands on its flight stand rather than floating.

## Miniatures — mounts & riders

A loadout resolves to a variant key `<baseKey>#<slug>`; a mounted model uses a two-tier
resolution — first a composed `<hero>#<weapon>+<mountslug>`, then a whole-token fuzzy fallback
over the manifest (so a `snake` / `sphinx` mount still matches). A **rider** is height-fit to a
foot-trooper reference (`RIDER_ANATOMY_BASE_MM` = 25) instead of the mount's base, and is only
treated as a rider when its body sits at least `RIDER_ELEVATION_MIN_RATIO` (0.25) of its height
above the model's lowest point (a mounted-by silhouette). Oval/rectangular base alignment is a
**marker-only** long-axis hint (`long_axis`); the manifest override wins over the Army Forge
recommendation, which wins over the Tough fallback. All constants live in `opr_army_manager.gd`.

## Miniature bases (terrain-projected)

`base_decor.gd` (`BaseDecor.build_base`) builds the base a model stands on and projects the
tabletop's own surface onto its top via `shaders/base_terrain_top.gdshader` (world-XZ sampling),
inside a shared near-black rim. `should_ring` adds an affiliation ring for lone solo models
(units of one); members of a multi-model unit are shown by the boundary rubberband instead. One shared base
material is owned by `table.gd`; `legacy_solid_disc` is the killswitch back to the flat
player-coloured disc (QA "before" look). Base-render QA harnesses live in `tools/`.

## Asset pipeline (offline, separate repo)

The offline content pipeline (Python; image-gen → TRELLIS → GLB) is **not part of
this repo or the running game** — it lives in a separate private repository and
produces the GLBs the game imports. This repo consumes only its R2-delivered
outputs (see [`ASSET_DELIVERY.md`](ASSET_DELIVERY.md)).

## Diagnostics

`diagnostics_reporter.gd` builds the anonymised "Report a problem" bundle (version, platform,
GPU, recent log files) and scrubs room codes, file paths and player names before export.

## Tests

gdUnit4 suites in `test/`; Python tests in `relay/`.
Runner commands in [`DEVELOPMENT.md`](DEVELOPMENT.md).
