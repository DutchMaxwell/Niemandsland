# Niemandsland — Status & Roadmap

**Version:** 0.3.1-alpha *(Alpha Release Candidate)* · **Engine:** Godot 4.6 · **Branch:** `main`

This is the single source of truth for what works, what's in progress, and what's
planned. Architecture details live in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md);
the full change history is in `git log`.

## Works today

**Sandbox & objects** — 3D table (variable sizes), orbit/pan/zoom camera, spawn/
move/rotate/delete, multi- and box-select, copy/paste/duplicate, row/arrow
arrangement with constant base-edge spacing, distance measuring (inches), physics
D6 dice in a scaled SubViewport (our own MIT `dice_tray.gd` / `dice_d6.gd`; replaced
the former AGPL `dice_roller` addon) with a per-face result readout and a shared
multiplayer dice log. **Extended dice options** (display-only, rules in
`dice_rules.gd`): success target (2+…6+) + modifier with OPR's natural-6/1 rule,
success counts in readout and log, and one-click partial rerolls (fails / 1s /
6s / all — only those dice re-toss, the rest stay frozen); faces + evaluation
context sync to remote players.

**Map layout** — top-down 3″ grid editor: terrain pieces (ruins/forest/container/
dangerous), front-line + custom-polygon deployment zones (1″ grid, symmetric/
asymmetric, snap points, float-precision vertices), objectives, auto-generate, OPR
guideline checker, 3D overlay, save/load layouts. **The whole prop set is textured and
R2-delivered** (per-prop manifests + libraries, holographic offline fallbacks that
upgrade in place): ruin walls as fully closed masonry shells (per-role panels, stepped
crumble, alpha-profile caps, window reveals), forests as volumetric TRELLIS tree models
(billboards as the mid tier; deterministic variant/size/facing, spacing + boundary
margins), blockers as shipping containers (2 colourways), dangerous terrain as a
minefield (15 anti-tank mines + 2 warning signs). **Biome themes** re-skin the set in
place via `table.set_biome`: grassland (default), desert (fine adobe + cacti) and
tundra (snowed stone/conifers/containers); volcanic/jungle/urban still use the default
set. **Terrain reference aids (Asgard tournament standard, display only)**:
always-visible effect labels per terrain zone (Cover / Difficult / Dangerous /
Impassable / Height) and height-aware top-down line-of-sight in the measure tool
(`los_rules.gd` Height categories + per-zone flood fill in `terrain_overlay.gd`;
a 🚫 marker on the measure line when LOS is blocked). **Units also block sight
lines** (Asgard: a model blocks at its Height when ≥ both endpoints' Height, and
gaps under 1″ inside a unit count as closed; the endpoint units never block their
own line — `LosRules.units_block_line`). Players apply the effects themselves —
terrain has **no automated movement/cover/damage effects** by design.

**Units (OPR)** — Army Forge import via the OPR API; per-model architecture
(`ModelInstance`) wrapped by system-agnostic `GameUnit`; automatic equipment
distribution; coherency check + on-table visualizer; radial context menu; docked
unit info card; per-model wounds and caster points; unit-wide Fatigue/Shaken/
Activated tokens; hero attachment.

**Multiplayer** — ENet over LAN and over the internet via the WebSocket relay
([`relay/`](relay/README.md)); full state sync (models, terrain, rotation, table
size) with batch RPCs; shared dice log; player avatars/cursors; multiplayer
save/load. **Player names** (entered in Host/Join, persisted, host-authoritative
sync) appear in the dice log, on avatars and in a connected-player **roster**;
an **in-game chat** panel (Enter to type, Esc to return — typing freezes camera
and object shortcuts). A **version handshake** on join rejects mismatched clients
(gating state sync on a match). A **room browser** lists joinable public rooms
(opt-in per host) and joins by click; private rooms stay code-only.
**Host-drop reconnect** (the relay preserves a dropped host's room for 20 s; the
host rehosts and re-syncs full state) is also live; see
[`relay/HOST_RECONNECT.md`](relay/HOST_RECONNECT.md). The relay (`list_rooms` +
host-reconnect) was deployed to Fly.io on 2026-06-12 (`niemandsland-relay`, fra);
a `list_rooms` smoke test against the live server passed. The full two-client
in-game live test is the remaining manual verification.

**Import/export** — TTS import (Steam CDN + cache), custom glTF/STL/OBJ, `.nml`
save format with OS file association, WGS import/export
([`docs/WGS_INTEGRATION.md`](docs/WGS_INTEGRATION.md)).

**Presentation** — 9 Kenney UI themes (persisted), lighting presets (F1–F5),
graphics quality presets, SSAO + glow, cinematic intro. **Battlefield atmosphere**
([`docs/ATMOSPHERE.md`](docs/ATMOSPHERE.md)): one-click Day/Sunset/Night/Overcast/Rain
presets (2 s blends, rain particles, lightning + delayed thunder), a "war-torn" toggle
(deterministic fires at ruin walls with smoke + flicker light) and "distant war sounds"
— audio is real CC0 recordings delivered from R2 with procedural synth fallback
(`ambience_synth.gd`), persisted per player. Scatter decor: brick-rubble piles at ruin
wall bases + grassland grass field (one MultiMesh each, quality-gated). **AAA main
menu**: live night-battlefield diorama (production terrain stack + miniatures vignette
+ orbit camera with DoF), left command column (HudTokens), CONTINUE-newest-save entry,
typewriter quote ticker, menu soundscape + CC0 dark-ambient drone, idle attract mode.
Settings window reachable in-game via left panel button or F7. **UI audio**: every
`BaseButton` gets procedural hover/click/focus ticks via the `UiFeedback` autoload
(one `node_added` hook, zero per-button code; variation-aware confirm/back tones) on
a dedicated, independently mutable "UI" bus with its own persisted settings slider.

**Model Forge** — Python pipeline (OPR data → image → TRELLIS mesh → GLB) with a
Flask review UI; 38 faction design languages / 855 unit overrides with real OPR
v3.5.x stats. IP-safe generation (positive-only prompts, per-faction `ip_strict` /
`bio_weapons` flags, per-unit `type:` for vehicles/walkers/aircraft) and a 3-versions-
per-unit "pick the best" review tool. See [`tools/model_forge/README.md`](tools/model_forge/README.md).

**3D model delivery (R2)** — miniature GLBs are **not bundled**; they are delivered
on demand from Cloudflare R2 (content-addressed `sha256.glb`, `<legacy-cdn-host>`),
mapped by [`assets/model_manifest.json`](assets/model_manifest.json). Builds stay slim
(GLBs are gitignored + excluded from every export preset); the editor/game fetches
models at runtime. Re-publish via `publish_manifest.py --upload-r2`. See
[`docs/ASSET_DELIVERY.md`](docs/ASSET_DELIVERY.md). **Live today: 113 models across
5 factions** — Alien Hives (41), Robot Legions (29), Battle Brothers (23), Dao Union
(19), a Dark Brothers hero. Remaining factions have 2D generated and pick-ready.

## In progress

- **Graphics preset switch FROM Performance hangs** — root cause is an NVIDIA
  driver bug (the dev machine runs 580.126.18; 580.142 fixes "Vulkan swapchains stop
  delivering frames under X11 under load"). Performance is the only sub-native tier,
  so its switch is the only one that resizes the 3D render target — now de-bursted
  (the `scaling_3d_scale` change is staggered onto its own frames in
  `graphics_settings.gd`) as a portable mitigation. **Definitive fix: update the
  NVIDIA driver to ≥ 580.142;** awaiting user retest of the mitigation + driver update.
- **Host-DROP live test**: the two-client lobby/chat/names/browser flow is
  user-confirmed working (2026-06-12); the one untested piece is a host losing
  connection mid-game and rejoining (relay side is deployed + unit-tested).

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
- The 3D dice tray is shared between local and remote rolls: a remote roll that
  arrives while a local physics roll/reroll is still tumbling (same ~2 s window)
  preempts and drops the local roll (not logged/broadcast). Remote wins by design
  (it is already shared state); rare in practice.

## Tests

gdUnit4: **54 suites / 376 tests green** in `test/` (incl. `coherency_checker`,
`save_manager`, `startup_menu`, `internet_lobby`, `relay_multiplayer_peer`,
`network_version_handshake`, `dice_rules`, `player_identity`). Python:
`relay/test_relay_server.py` (38 green), `tools/model_forge/tests/`. How to run:
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).
Coverage is still thin — most gameplay scripts are untested.
