# Architecture

A map of how OpenTTS is actually put together. Engine: Godot 4.6, GDScript,
Forward+ renderer. Entry scene: `scenes/startup_menu.tscn`.

## Autoloads (singletons)

| Autoload | Script | Responsibility |
|---|---|---|
| `ThemeManager` | `theme_manager.gd` | Active Kenney UI theme, persisted |
| `GraphicsSettings` | `graphics_settings.gd` | Quality presets (shadows, SSAO, glow) |
| `AudioManager` | `audio_manager.gd` | Audio buses / playback |

## Scenes

- `startup_menu.tscn` — main scene; menu + `tron_intro.gd` animation.
- `main.tscn` — the game table; instantiates the subsystems below.
- Dialog/overlay scenes: `map_layout`, `radial_menu`, `opr_stats_tooltip`,
  `unit_card`, and the import/wounds/marker/casts dialogs.

## Subsystems (scripts/)

**Table & interaction**
- `main.gd` — top-level controller; wires subsystems and UI.
- `object_manager.gd` — spawns/selects/drags table objects; selection + box-select;
  emits selection/drag signals consumed by the unit overlays.
- `camera_controller.gd` — orbit/pan/zoom with easing.
- `table.gd` — table dimensions and collision.
- `selectable_object.gd` — per-object selection behaviour.

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
- `radial_menu.gd` / `radial_menu_controller.gd` — context pie-menu.

**OPR & import**
- `opr_api_client.gd` — Army Forge API client + unit data classes (incl. base sizes).
- `opr_army_manager.gd` — spawns imported armies; loads per-unit GLBs and **scales
  them to the base** (height-fit vs 125 % footprint cap, whichever is smaller; Flying
  units hover). See [Scaling](#scaling).
- `opr_import_dialog.gd` — import UI.
- `tts_importer.gd` / `tts_download_manager.gd` — Tabletop Simulator import (Steam
  CDN + local cache; glTF/STL/OBJ).
- `wgs_client.gd` / `wgs_game_manager.gd` / `wgs_import_dialog.gd` — Wargaming
  Simulator format ([`WGS_INTEGRATION.md`](WGS_INTEGRATION.md)).

**Map & terrain**
- `map_layout.gd` / `map_layout_grid.gd` — top-down editor + 3″ grid.
- `terrain_library.gd` — terrain piece definitions.
- `terrain_overlay.gd` — 3D overlay + custom deployment zones.

**Presentation**
- `lighting_controller.gd` / `lighting_panel.gd` — F1–F4 presets.
- `atmospheric_clouds.gd`, `glassmorphism_theme.gd`, `tron_intro.gd`,
  `model_info_popup.gd`, `opr_stats_tooltip.gd`.

## Save format (`.otts`)

`save_manager.gd` serializes the full table: objects, `GameUnit`/`ModelInstance`
state (positions, wounds, markers, activation), terrain layout, table size. Files use
the `.otts` extension with OS file association; the same serialization feeds
multiplayer load.

## Multiplayer

- `network_manager.gd` — ENet host/join, state sync, RPCs (models, terrain, rotation,
  table size, wounds/markers/activation) with batched updates.
- `relay_multiplayer_peer.gd` — custom `MultiplayerPeer` that tunnels ENet over a
  WebSocket relay for internet play.
- `relay/` — standalone Python WebSocket relay server (Fly.io deployable); see
  [`relay/README.md`](../relay/README.md).
- `internet_lobby.gd`, `player_avatar.gd`, `remote_cursor.gd` — lobby + presence.

## Dice

Provided by the `dice_roller` addon, rendered in a **separate scaled SubViewport**
because miniature-scale rigid bodies are unstable in Godot's default physics. Table
dice are display-only.

## Scaling

1 unit = 1 m. API/rules in inches, world in metres, bases in mm
(`INCHES_TO_METERS = 0.0254`, `MM_TO_METERS = 0.001`). Imported GLBs are scaled in
`opr_army_manager._compute_model_fit()`: target height ≈ base size (mildly larger for
Tough), but the horizontal footprint is capped at 125 % of the base's long side
(`FOOTPRINT_MAX_RATIO`); the smaller factor wins, so slim infantry stay height-driven
while wide vehicles are footprint-capped. Flying units hover (`FLYING_HOVER_RATIO`).

## Model Forge (offline tool)

`tools/model_forge/` (Python) is a separate content pipeline, not part of the running
game — it produces the GLBs + `units.json` the game imports. The TRELLIS client lives
in `assets/3d_pipeline/trellis_core.py`. See
[`tools/model_forge/README.md`](../tools/model_forge/README.md).

## Tests

gdUnit4 suites in `test/`; Python tests in `relay/` and `tools/model_forge/tests/`.
Runner commands in [`DEVELOPMENT.md`](DEVELOPMENT.md).
