# Niemandsland — Status & Roadmap

**Version:** 0.3.5.7-alpha *(Road to Alpha — the `0.3.6` release plan is in [`docs/ROAD_TO_ALPHA.md`](docs/ROAD_TO_ALPHA.md))* · **Engine:** Godot 4.6 · **Branch:** `main`

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
host-reconnect) is deployed to Fly.io (`niemandsland-relay`, fra). The reconnect /
rate-limit / army-sync cascade was live-validated across two real clients.

**Import/export** — Army Forge (OPR) + Wargaming Simulator (WGS) list import, `.nml`
save format with OS file association
([`docs/WGS_INTEGRATION.md`](docs/WGS_INTEGRATION.md)).

**Presentation** — a built-in Tactical-HUD UI theme (sleek; cyan/amber), atmosphere
presets (Day/Sunset/Night/Overcast/Rain), graphics quality presets, SSAO + glow, cinematic intro. **Battlefield atmosphere**
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

**3D model pipeline** — the offline pipeline (OPR data → image → TRELLIS mesh → GLB)
lives in a **separate private repository**; this repo and the shipped game consume only
its R2-delivered outputs, mapped by [`assets/model_manifest.json`](assets/model_manifest.json).

**3D model delivery (R2)** — miniature GLBs are **not bundled**; they are delivered
on demand from Cloudflare R2 (content-addressed `sha256.glb`, served from the asset CDN),
mapped by [`assets/model_manifest.json`](assets/model_manifest.json). Builds stay slim
(GLBs are gitignored + excluded from every export preset); the editor/game fetches
models at runtime. The publish tooling lives in the private pipeline repository. See
[`docs/ASSET_DELIVERY.md`](docs/ASSET_DELIVERY.md). **Live today: 417 models across
19 factions** (verified retrievable on R2) — from Alien Hives (41) and Robot Legions /
Orc Marauders (29 each) down to Elven Jesters (8) and a Dark Brothers hero (1).
Remaining factions are 2D generated and pick-ready.

## In progress

The forward-looking work now lives in [`docs/ROADMAP.md`](docs/ROADMAP.md); see the
**Now / Next** sections there for what is actively being worked.

## Planned

The forward-looking plan and the feature-request pipeline now live in
[`docs/ROADMAP.md`](docs/ROADMAP.md) (single source). Near-term: merge the casual
sandbox terrain branch + extend forests to the other biomes, Regiments handling
polish (frontage cycle / wheel), and the two-client multiplayer live test.

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
  dice approach; see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md#scaling)).
- Some TTS texture-loading errors (non-fatal).
- OPR rule descriptions resolve for freshly imported armies; loaded saves /
  remote-only armies show rule names without descriptions (persist/sync is a
  future step).
- The 3D dice tray is shared between local and remote rolls: a remote roll that
  arrives while a local physics roll/reroll is still tumbling (same ~2 s window)
  preempts and drops the local roll (not logged/broadcast). Remote wins by design
  (it is already shared state); rare in practice.

## Tests

gdUnit4: **~558 tests green** in `test/` (incl. `coherency_checker`,
`save_manager`, `startup_menu`, `internet_lobby`, `relay_multiplayer_peer`,
`network_version_handshake`, `dice_rules`, `player_identity`). Python:
`relay/test_relay_server.py` (38 green). How to run:
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).
Coverage is still thin — most gameplay scripts are untested.
