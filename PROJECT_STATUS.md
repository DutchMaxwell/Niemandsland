# Niemandsland — Status & Roadmap

**Version:** 0.3.1-alpha *(Alpha Release Candidate)* · **Engine:** Godot 4.6 · **Branch:** `main`

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
save/load. A **version handshake** on join rejects mismatched clients (a 0.3.0 and
a 0.3.1 player can no longer share a table), gating state sync on a match.
**Host-drop reconnect** is implemented + unit-tested (the relay preserves a dropped
host's room for 20 s; the host rehosts and re-syncs full state) but is **deploy-pending**
— it needs a Fly.io relay redeploy before it is live; see
[`relay/HOST_RECONNECT.md`](relay/HOST_RECONNECT.md).

**Import/export** — TTS import (Steam CDN + cache), custom glTF/STL/OBJ, `.nml`
save format with OS file association, WGS import/export
([`docs/WGS_INTEGRATION.md`](docs/WGS_INTEGRATION.md)).

**Presentation** — 9 Kenney UI themes (persisted), lighting presets (F1–F4),
graphics quality presets, SSAO + glow, cinematic intro, glassmorphic startup menu.

**Model Forge** — Python pipeline (OPR data → image → TRELLIS mesh → GLB) with a
Flask review UI; 38 faction design languages / 855 unit overrides with real OPR
v3.5.x stats. IP-safe generation (positive-only prompts, per-faction `ip_strict` /
`bio_weapons` flags, per-unit `type:` for vehicles/walkers/aircraft) and a 3-versions-
per-unit "pick the best" review tool. See [`tools/model_forge/README.md`](tools/model_forge/README.md).

**3D model delivery (R2)** — miniature GLBs are **not bundled**; they are delivered
on demand from Cloudflare R2 (content-addressed `sha256.glb`, `assets.akesberg.de`),
mapped by [`assets/model_manifest.json`](assets/model_manifest.json). Builds stay slim
(GLBs are gitignored + excluded from every export preset); the editor/game fetches
models at runtime. Re-publish via `publish_manifest.py --upload-r2`. See
[`docs/ASSET_DELIVERY.md`](docs/ASSET_DELIVERY.md). **Live today: 113 models across
5 factions** — Alien Hives (41), Robot Legions (29), Battle Brothers (23), Dao Union
(19), a Dark Brothers hero. Remaining factions have 2D generated and pick-ready.

## In progress

- Terrain reference aids per the **Asgard tournament standard** — *display only, no
  auto-resolution*: always-visible effect labels per terrain zone (Cover / Difficult /
  Dangerous / Impassable / Height) and height-aware top-down line-of-sight in the
  measure tool. Players apply the effects themselves.
- Extended dice options (modifiers, rerolls).

## Planned

- Unit-as-LOS-blocker (Asgard: formation height + closed 1" gaps) — terrain LOS first.
- Multiplayer lobby UI / room browser, in-game chat.
- UI audio: a dedicated mutable "UI" bus + a `UiSound` autoload auto-wiring
  `BaseButton` hover/click/focus feedback (full spec archived in
  [`docs/archive/AAA_UI_PLAYBOOK.md`](docs/archive/AAA_UI_PLAYBOOK.md)).

## Out of scope (by design)

Niemandsland is a **tool for human players, not an automated game**. We deliberately
do **not** build turn/phase/activation tracking, combat/save/damage resolution, or an
AI opponent. (An earlier AI system + battle simulator, ~5500 lines, was removed as
legacy and will not be reimplemented.)

## Not built (despite older docs)

The `ai_*.gd` and `battle_simulator.gd` scripts no longer exist. `activation_tracker.gd`
and `hero_attachment_dialog.gd` never existed as separate files — that logic lives in
`game_unit.gd` / `radial_menu*.gd` / `network_manager.gd`.

## Known issues

- Dice can occasionally jitter at miniature scale (mitigated by the scaled-SubViewport
  dice approach; see [`CLAUDE.md`](CLAUDE.md)).
- Some TTS texture-loading errors (non-fatal).
- OPR rule descriptions resolve for freshly imported armies; loaded saves /
  remote-only armies show rule names without descriptions (persist/sync is a
  future step).

## Tests

gdUnit4: **39 suites / 275 tests green** in `test/` (incl. `coherency_checker`,
`save_manager`, `startup_menu`, `internet_lobby`, `relay_multiplayer_peer`,
`network_version_handshake`). Python: `relay/test_relay_server.py`,
`tools/model_forge/tests/`. How to run: [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).
Coverage is still thin — most gameplay scripts are untested.
