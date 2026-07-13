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
  `_apply_base_recommendation` applies the AF `bases:{round,square}` spec (regiments use
  the square/rectangular base); the Tough-derived fallback (`_apply_tough_base_fallback`)
  is only used when the API gives no usable base.
- `model_library.gd` (`ModelLibrary`) — resolves a unit → model file from the manifest and
  drives on-demand download + cache. Owns the manifest layering (bundled fallback → live
  CDN root → dev/QA override), the loadout→variant slug (`variant_slug`, from
  `assets/label_slug_map.json`), the ctex block resolution, the fuzzy mount matcher
  (`find_faction_model_matching`), and the per-entry manifest overrides `fit_scale` /
  `base_mm` / `long_axis`. See [`MANIFEST_DELIVERY.md`](MANIFEST_DELIVERY.md).
- `opr_army_manager.gd` — spawns imported armies onto a per-player **army tray**; loads
  per-unit GLBs and **scales them to the base** (height-fit vs 125 % footprint cap,
  whichever is smaller; Flying units hover). See [Scaling](#scaling) and
  [the mount/rider system](#miniatures--the-mount--rider-system). The tray's near
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
> `asset_download_manager.gd` + `model_library.gd` from Cloudflare R2 so the repo/build stay lean
> and only an army's needed models are fetched — see [`ASSET_DELIVERY.md`](ASSET_DELIVERY.md) for
> the download/cache mechanics and [`MANIFEST_DELIVERY.md`](MANIFEST_DELIVERY.md) for the
> manifest-layering / staging model. OPR stats/data load only via the Army Forge API (never bundled).

### Miniatures — the mount / rider system

An imported GLB is scaled and oriented onto its base at spawn (`_create_unit_model` →
`_compute_model_fit` → `_align_to_oval_long_axis`, shared by the import and the save/MP
restore path). Beyond the base-driven fit ([Scaling](#scaling)), three behaviours matter:

- **Loadout → variant model.** A model's distributed loadout labels map to a sorted,
  de-duplicated part-slug set (`ModelLibrary.variant_slug`, vocabulary in
  `assets/label_slug_map.json`); if the manifest carries `<baseKey>#<slug>`, that pre-baked
  variant is used, else the base model (`_resolve_model_variant_name`). Model Forge names
  its variant bakes by reproducing exactly this derivation.
- **Mount resolution (two-tier).** A mount upgrade folds a mount slug into the carrier
  model's labels (`_labels_with_mount`), so a mounted hero resolves to a *composed* bake
  `<hero>#<weapon>+<mountslug>` through the same variant path as a weapon. When a faction
  has no composed mount bake, `_resolve_carrier_model` falls back to the **old fuzzy
  faction-mount GLB** (`_find_mount_glb_name` → `ModelLibrary.find_faction_model_matching`),
  which now scores by **whole-token overlap** against the mount's full name — so
  "Skeleton Beast" resolves to the `skeleton beast` model instead of colliding on a bare
  "beast" keyword (`MOUNT_KEYWORDS` gained `snake`/`sphinx` etc. for the go-live).
- **Rider-anatomy fit.** `_compute_model_fit` detects a rider either explicitly (a
  hero-mount upgrade, `is_mount`) or geometrically (a `body` node whose bottom sits
  ≥ `RIDER_ELEVATION_MIN_RATIO` (0.25) of its height above the model's lowest point — so a
  mounted-by-default unit like a chariot rides too). In rider mode the rider body is scaled
  to the **standard trooper height** (`RIDER_ANATOMY_BASE_MM` = 25 mm, no Tough factor, no
  base-size influence, footprint **not** capped), so a mounted rider matches a foot trooper;
  grounding is on the *combined* lowest point (the mount's feet/wheels), so the mount stands
  on its base rather than the rider being buried onto it. A `>2.5×` footprint overflow warns
  (mis-authored comp) rather than silently shipping a table-filling model.
- **Oval alignment is marker-only.** `_align_to_oval_long_axis` turns a model down its oval
  base's long axis **only** from the per-entry `long_axis` manifest marker; without a marker
  the legacy +Z convention holds (no turn on the standard depth-long oval), so every live
  model stays byte-identical. This is deliberate: an XZ footprint cannot distinguish body
  *length* from *wingspan* (a coiled +Z serpent or a winged avatar spreads wider in X), so
  only the producer's authored facing — the marker — can drive the rotation. Walkers are the
  exception: they sit crosswise deterministically from the base geometry (a biped's footprint
  is near-square). `_get_model_aabb` composes each mesh box through **every** ancestor
  transform (via `_relative_transform`), because a re-exported mount can carry its scale on a
  parent node instead of the mesh; `_get_body_aabb` measures the named `body` node.
- **Manifest overrides** (`base_mm` / `fit_scale` / `long_axis`) are applied with precedence
  **manifest > AF API > Tough-derived** (`_apply_manifest_base_overrides`); the override lands
  in the unit's base fields, which save/load and MP sync already carry, so guests and reloads
  stay consistent without re-applying. See [`MANIFEST_DELIVERY.md`](MANIFEST_DELIVERY.md).
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
multiplayer load. Regiment blocks persist via `Regiment.to_dict()` (frontage, tray
transform, `wounds_taken`) and are rebuilt by `OPRArmyManager.restore_regiment`,
which re-applies the pooled-wound counter so model alive/dead states + the boundary
wound token are restored exactly.

**Versioned migration.** The format is versioned by `SaveManager.SAVE_VERSION` (currently
`"1.6"`). `save_manager.load_game` runs `save_migrations.gd` (`SaveMigrations.migrate`)
between JSON-parse and applying the state: the current version passes through, a supported
older version migrates step by step up the chain, and anything **older than the alpha
launch format** (`< 1.4`) or **newer than this build** is refused with a clear message —
the current table is left untouched — instead of the old "warn and load anyway" that risked
silent data damage. The chain today is `1.4 → 1.5` (sandbox terrain added; explicit no-op)
`→ 1.6` (the schema checkpoint that normalises post-1.5 fields which shipped without a bump:
per-model base size, dead-model parking, objective owners, spell lists). **Standing rule
(documented at the constant):** whoever bumps `SAVE_VERSION` ships the matching migration
step **and** a fixture test in the same change.

## Miniature bases (terrain-projected)

Every model sits on a "perfectly based" three-part base (`scripts/base_decor.gd`,
`BaseDecor.build_base`, shared by import and restore via `OPRArmyManager._build_model_base`),
replacing the legacy solid player-coloured disc:

1. a **terrain-projected top** — a flat quad whose fragment shader
   (`shaders/base_terrain_top.gdshader`) reconstructs the table's ground UV from the base's
   **world XZ** position, so the top reads as a live window onto the biome texture directly
   beneath the model (it mirrors `table_ground.gdshader`; a hard `length(shape_uv) > 1`
   discard clips the quad to the round/oval outline, and the top carries a world-aligned
   tangent so it answers the sun identically to the board);
2. a near-black, slightly **beveled rim** (a shallow frustum) like a real tabletop base edge;
3. for **solo models only** (`BaseDecor.should_ring(unit_size)` → units of one), a
   player-coloured **affiliation ring** on the rim — the one-model equivalent of a
   multi-model unit's boundary rubberband (multi-model units keep a clean black rim; their
   affiliation *is* the rubberband).

`table.gd` owns the **one shared** terrain-top `ShaderMaterial` (`get_base_top_material` /
`_update_base_top_material`), pushing the same biome texture + table-size centre-crop + XZ
transform to every base, so a biome or table-size change updates all bases at once. Rim and
ring materials are also shared (one rim; one ring per player colour), and meshes are cached
per (shape, size); nothing here allocates per frame. `BaseDecor.legacy_solid_disc` is a
killswitch back to the flat disc (also the QA render tool's before/after hook). Render QA
harnesses live in `tools/base_render_qa.gd` and `tools/base_luminance_qa.gd`.

## Multiplayer

- `network_manager.gd` — ENet host/join, state sync, RPCs (models, terrain, rotation,
  table size, wounds/markers/activation) with batched updates. Regiment-specific
  sync: `broadcast_regiment_frontage` / `sync_regiment_frontage` (frontage cycle)
  and `broadcast_regiment_wounds` / `sync_regiment_wounds` (pooled-tough counter).
- `relay_multiplayer_peer.gd` — custom `MultiplayerPeer` that tunnels ENet over a
  WebSocket relay for internet play.
- `relay/` — standalone Python WebSocket relay server (Fly.io deployable); see
  [`relay/README.md`](../relay/README.md). It also records **anonymous usage stats** (no PII):
  totals/peaks, join failures by reason, and two close-time histograms (room lifetime,
  peak-peers-per-room). `games_played` is counted live the first time a room reaches ≥2
  peers; the close histograms are recorded at **every** room-end path — including a graceful
  **server shutdown**, which folds any still-open rooms in before exit (on Fly the scale-to-
  zero / redeploy stop, not a clean disconnect, is the dominant way a room ends). Only rooms
  open at a hard kill (SIGKILL/OOM) are lost.
- `internet_lobby.gd`, `player_avatar.gd`, `remote_cursor.gd` — lobby + presence.
- `player_identity.gd` — local display name + per-install client token; static helpers for
  sanitisation and slot-stable identity across reconnects.
- `import_await_guard.gd` (`ImportAwaitGuard`) — a guest receives a remote army as a stream
  of RPCs (header → N unit batches → complete). If the host drops or the relay loses the final
  message mid-stream, the `complete` never arrives and the guest would wait forever (LOADING
  overlay stuck, presence paused). This pure per-player **generation counter** drives an
  *inactivity* timeout: header and every unit RPC bump the player's generation and arm a fresh
  `SceneTreeTimer` (`IMPORT_AWAIT_TIMEOUT_SEC` = 75 s in `main.gd`) capturing that generation;
  a fired timer aborts **only** if its captured generation is still current — so a healthy
  import keeps superseding its own timers, while a genuine stall trips exactly once, releases
  the restore lock, toasts the player, and recovers (the host can re-import).

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
while wide vehicles are footprint-capped. Aircraft sit on a tall flight stand
(`AIRCRAFT_HOVER_M`); Flying units now stand on their base like everything else. A
composed model with a named `body` node fits on the **body** box (parts like a banner pole
or raised weapon may overhang without shrinking the model), and a **rider** gets the
rider-anatomy fit — see [the mount/rider system](#miniatures--the-mount--rider-system). Per-
entry manifest overrides (`base_mm` / `fit_scale` / `long_axis`) can correct any of this;
see [`MANIFEST_DELIVERY.md`](MANIFEST_DELIVERY.md).

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
