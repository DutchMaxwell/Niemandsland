# Niemandsland — Instructions for Claude

## Language

- **Reply to the user in German** — the user is a German speaker.
- **Keep everything in the codebase in English** — identifiers, code comments,
  commit messages, PR text, and docs — so the project stays usable
  internationally.

## Project

Niemandsland is a desktop **tabletop wargaming simulator** (v0.3.6.0-alpha) for
OnePageRules and similar miniature games.

- **Engine**: Godot **4.6** (Forward+ renderer), `config_version=5`
- **Language**: GDScript
- **Physics**: Godot's **default** physics (Jolt is *not* configured). Dice run in
  a scaled SubViewport via our own MIT `dice_tray.gd` / `dice_d6.gd` (procedural W6,
  replaced the former AGPL addon) — see [Scaling](#scaling-critical).
- **Platforms**: Linux (dev machine), Windows, macOS
- **Tests**: gdUnit4 (`test/`), pytest (`relay/`)
- **Main scene**: `scenes/startup_menu.tscn`
- **Autoloads**: `ThemeManager`, `GraphicsSettings`, `AudioManager`, `UiFeedback`,
  `UpdateChecker`

Full system/code map: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
Build/run/test: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

> There is **no AI / battle-simulation system**. It was removed; any `ai_*.gd` /
> `battle_simulator.gd` references in old notes are obsolete. Don't recreate it
> unless asked (it's a roadmap item).

## Key scripts (by domain)

| Domain | Scripts |
|---|---|
| Core | `main.gd`, `object_manager.gd`, `camera_controller.gd`, `table.gd`, `selectable_object.gd` |
| Save/Load | `save_manager.gd` (`.nml` format) |
| Units | `game_unit.gd`, `model_instance.gd`, `unit_utils.gd`, `equipment_distributor.gd`, `coherency_checker.gd`, `coherency_visualizer.gd`, `unit_card.gd`, `unit_marker.gd`, `unit_boundary_visualizer.gd`, `radial_menu*.gd` |
| OPR / import | `opr_api_client.gd`, `opr_army_manager.gd`, `opr_import_dialog.gd`, `tts_importer.gd`, `tts_download_manager.gd`, `wgs_*.gd` |
| Multiplayer | `network_manager.gd`, `relay_multiplayer_peer.gd`, `internet_lobby.gd`, `player_avatar.gd`, `remote_cursor.gd` |
| Map / terrain | `map_layout.gd`, `map_layout_grid.gd`, `terrain_library.gd`, `terrain_overlay.gd` |
| Presentation | `lighting_controller.gd`, `theme_manager.gd`, `graphics_settings.gd`, `audio_manager.gd`, `cinematic_intro.gd` |

## Scaling (CRITICAL)

1 Godot unit = 1 metre.

| Context | Unit | Example |
|---|---|---|
| API / rules | inches | `movement: 6.0` = 6″ |
| Godot world | metres | `position.x = 0.1524` = 6″ |
| Bases | millimetres | `base_size: 25` = 25 mm |

`INCHES_TO_METERS = 0.0254`, `MM_TO_METERS = 0.001`. Table 4×4 ft = 1.22 m.

Miniatures (16–60 mm) are far below Godot physics' stable range (~0.1–10 m), so
**dice physics runs in a separate scaled SubViewport** (our own MIT `dice_tray.gd` /
`dice_d6.gd`); table dice are display-only. GLB minis are scaled to their base at spawn in
`opr_army_manager.gd` (oval / Tough-derived vehicle bases fit the base exactly; round infantry
capped at 125 %; see ARCHITECTURE).

## Coding standards

Full standards: [`docs/CODING_STANDARDS.md`](docs/CODING_STANDARDS.md).
Essentials: no warnings, no magic numbers, no TODO/dead code; explicit types;
defensive null-checks/early-returns; enums over strings for states; no allocations in
`_process`; every game rule cites its OPR reference. GDScript file order:
Constants → Signals → `@export` → private vars → `_ready`/`_process` → public →
private, separated by `# ===` blocks.

## Git conventions

Conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`, `perf:`). **Never commit
without being asked.** This repo is sometimes worked on by more than one agent — check
for in-flight changes and coordinate before committing shared files.

## Workflow

1. **Research first** — look for documented Godot/OPR solutions before inventing.
2. **Validate before committing** — compile-check + gdUnit4 tests
   (see [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)).
3. The offline 3D asset pipeline lives in a **separate private repository**; this
   repo consumes only its R2-delivered outputs (see `docs/ASSET_DELIVERY.md`).
4. **Track the work** — [`docs/ROADMAP.md`](docs/ROADMAP.md) is the curated backlog
   and single forward-looking source. Read it at the start of a session, work the top
   **Now / Next** item, and move it to **Shipped** (with a PR link) on merge. New
   requests go to **Next** (accepted) or **Ideas** (icebox).
