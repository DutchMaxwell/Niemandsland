# Niemandsland — Status & Roadmap

**Version:** 0.2.0-alpha · **Engine:** Godot 4.6 · **Branch:** `main`

This is the single source of truth for what works, what's in progress, and what's
planned. Architecture details live in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md);
the full change history is in `git log`.

## Works today

**Sandbox & objects** — 3D table (variable sizes), orbit/pan/zoom camera, spawn/
move/rotate/delete, multi- and box-select, copy/paste/duplicate, row/arrow
arrangement with constant base-edge spacing, distance measuring (inches), physics
dice (D4–D100) via the `dice_roller` addon.

**Map layout** — top-down 3″ grid editor: terrain pieces (ruins/forest/container/
dangerous), front-line + custom-polygon deployment zones (1″ grid, symmetric/
asymmetric, snap points, float-precision vertices), objectives, auto-generate, OPR
guideline checker, 3D overlay, save/load layouts. Terrain is **visual only** so far
(LOS-blocking and deployment-compliance checks exist as helpers; no movement/cover/
damage effects).

**Units (OPR)** — Army Forge import via the OPR API; per-model architecture
(`ModelInstance`) wrapped by system-agnostic `GameUnit`; automatic equipment
distribution; coherency check + on-table visualizer; radial context menu; docked
unit info card; per-model wounds and caster points; unit-wide Fatigue/Shaken/
Activated tokens; hero attachment.

**Multiplayer** — ENet over LAN and over the internet via the WebSocket relay
([`relay/`](relay/README.md)); full state sync (models, terrain, rotation, table
size) with batch RPCs; shared dice log; player avatars/cursors; multiplayer
save/load.

**Import/export** — TTS import (Steam CDN + cache), custom glTF/STL/OBJ, `.nml`
save format with OS file association, WGS import/export
([`docs/WGS_INTEGRATION.md`](docs/WGS_INTEGRATION.md)).

**Presentation** — 9 Kenney UI themes (persisted), lighting presets (F1–F4),
graphics quality presets, SSAO + glow, cinematic intro, glassmorphic startup menu.

**Model Forge** — Python pipeline (OPR data → image → TRELLIS mesh → GLB) with a
Flask review UI; 38 faction design languages / 855 unit overrides with real OPR
v3.5.x stats. See [`tools/model_forge/README.md`](tools/model_forge/README.md).

## In progress

- Terrain *gameplay* effects: cover dice modifiers, difficult-terrain movement,
  dangerous-terrain damage, height-based LOS.
- Extended dice options (modifiers, rerolls).

## Planned

- Rules automation: turn/phase tracking, activation, combat/morale resolution.
- AI opponent (OPR Solo & Co-op rules). **Note:** an earlier AI system and battle
  simulator (~5500 lines) were removed as legacy; a clean reimplementation is a
  future milestone.
- Multiplayer lobby UI / room browser, in-game chat.

## Not built (despite older docs)

The `ai_*.gd` and `battle_simulator.gd` scripts no longer exist. `activation_tracker.gd`
and `hero_attachment_dialog.gd` never existed as separate files — that logic lives in
`game_unit.gd` / `radial_menu*.gd` / `network_manager.gd`.

## Known issues

- Dice can occasionally jitter at miniature scale (mitigated by the scaled-SubViewport
  dice approach; see [`CLAUDE.md`](CLAUDE.md)).
- Some TTS texture-loading errors (non-fatal).
- A few GDScript warnings (parameter shadowing) to clean up.

## Tests

gdUnit4 suites in `test/`: `coherency_checker`, `save_manager`, `startup_menu`,
`internet_lobby`, `relay_multiplayer_peer`. Python: `relay/test_relay_server.py`,
`tools/model_forge/tests/`. How to run: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).
Coverage is still thin — most gameplay scripts are untested.
