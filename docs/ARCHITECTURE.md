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
- `radial_menu.gd` / `radial_menu_controller.gd` — context pie-menu.
- `regiment.gd` / `regiment_tray.gd` / `regiment_formation.gd` / `regiment_facing_visualizer.gd` —
  Age of Fantasy: Regiments — movement-tray blocks, square bases, casualty re-rank,
  frontage/reform, and the facing / front-arc display.

**OPR & import**
- `opr_api_client.gd` — Army Forge API client + unit data classes (incl. base sizes).
- `opr_army_manager.gd` — spawns imported armies onto a per-player **army tray**; loads
  per-unit GLBs and **scales them to the base** (height-fit vs 125 % footprint cap,
  whichever is smaller; Flying units hover). See [Scaling](#scaling). The tray's near
  third is an **Ambush/Scout staging band** (`feat/ambush-scout-deploy`): split left/right
  with a divider + flat labels, and units carrying Scout/Ambush auto-place into their half.
- `opr_import_dialog.gd` — import UI.
- `tts_download_manager.gd` — Tabletop Simulator asset download + cache manager
  (Steam CDN + local cache; glTF/STL/OBJ); also the template for the on-demand
  R2 delivery pattern.

> **On-demand delivery (live):** miniature GLBs are downloaded + cached via `asset_cdn.gd` /
> `asset_download_manager.gd` from Cloudflare R2 so the repo/build stay lean and only an army's
> needed models are fetched — see [`ASSET_DELIVERY.md`](ASSET_DELIVERY.md). OPR stats/data load
> only via the Army Forge API (never bundled).
- `wgs_client.gd` / `wgs_game_manager.gd` / `wgs_import_dialog.gd` — Wargaming
  Simulator format ([`WGS_INTEGRATION.md`](WGS_INTEGRATION.md)).

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
multiplayer load.

## Multiplayer

- `network_manager.gd` — ENet host/join, state sync, RPCs (models, terrain, rotation,
  table size, wounds/markers/activation) with batched updates.
- `relay_multiplayer_peer.gd` — custom `MultiplayerPeer` that tunnels ENet over a
  WebSocket relay for internet play.
- `relay/` — standalone Python WebSocket relay server (Fly.io deployable); see
  [`relay/README.md`](../relay/README.md).
- `internet_lobby.gd`, `player_avatar.gd`, `remote_cursor.gd` — lobby + presence.
- `player_identity.gd` — local display name + per-install client token; static helpers for
  sanitisation and slot-stable identity across reconnects.

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
while wide vehicles are footprint-capped. Flying units hover (`FLYING_HOVER_RATIO`).

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
