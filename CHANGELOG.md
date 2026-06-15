# Changelog

All notable changes to Niemandsland. Versions follow the project's alpha line
(`config/version` in `project.godot`). Game-state save format (`.nml`) is versioned
separately (`SAVE_VERSION` in `save_manager.gd`).

## [Unreleased]

### Added
- **Alien-jungle dangerous terrain: carnivorous plants.** The `alien_jungle` biome's
  dangerous terrain now spawns a TRELLIS 3D **carnivorous-plant clump** (bioluminescent
  alien flytrap maws) with a soft teal glow light — mirroring the volcanic lava crater.
  The per-biome dangerous-terrain prop is generalized (`BIOME_HAZARD_MODELS`:
  volcanic → lava_crater, jungle → carnivore_plant), thinned to a non-overlapping ~3-5 per
  field, no warning signs. GLB delivered on demand from R2 (hazards manifest `models`).

### Changed
- **Cleaner army import loading (issue #56).** The loading overlay now names each phase
  with a counter — **LOADING ARMY → LOADING 3D MODELS n/x → PLACING ARMY n/x** — instead
  of one static label that looked like it reset. The army no longer assembles piecemeal in
  view: the tray and all models stay hidden through the build and are revealed all at once
  for the drop-in deployment, which now starts only after every model is built.

### Added
- **Models rest on terrain surfaces when placed.** Dragging a model now raycasts down
  onto the ground beneath its base and rests it on the highest surface there — the table
  top, or a terrain prop such as a container — instead of always snapping to `y=0`. Each
  model in a multi-model unit resolves its own height, so part of a unit can stand on a
  container while the rest stay on the table; the resting height saves and syncs to peers
  (both already carried the full position). Miniatures moved to physics layer 2 so the
  placement raycast (ground = layer 1) rests them on terrain, never on each other; there
  is no model-vs-model collision (bases may still touch for melee/tight ranks). Lays the
  groundwork for future multi-level terrain.
- **Three new biomes get themed terrain props: volcanic (dwarven), alien jungle and
  urban ruins.** Each biome's ruin walls, "trees"/flora and containers now have their own
  R2-delivered texture set instead of falling back to grassland. **volcanic_ash** is
  styled as a **dwarven hold** — dark basalt ruin walls with restrained gold/copper rune
  inlay, slender upright standing-stone (menhir) "forests" in place of trees, open dwarven
  storage crates full of green glowing crystals (open-crate top + plain metal sides), and
  — as the **dangerous-terrain** prop — a volumetric **3D lava crater** (TRELLIS GLB: rocky
  bowl with molten lava overflowing the rim) with a tier-capped targeted OmniLight for the
  glow, instead of mines, and no warning signs. The crater falls back to a flat lava-texture
  quad, then a procedural crust+core pool, until the GLB downloads. **alien_jungle** =
  overgrown stone with bioluminescent flora; **urban_ruins** = cracked concrete with exposed
  rebar. Wired via `BIOME_PROP_THEMES` / `BIOME_CONTAINER_THEMES`; the
  ruins/trees/containers/hazards manifests gain the `volcanic_`/`jungle_`/`urban_` panel
  sets + the `lava_pool` texture + the `lava_crater` GLB, plus 9 volumetric GLB flora models
  (3 per biome, TRELLIS-generated, depth-verified) so MODELS mode is 3D, not just billboards.
  `HazardsLibrary` gains GLB-model support (mirrors TreesLibrary). Lava pool unit-tested.
- **Denser forests.** Decoration density (`TREES_PER_CELL`) raised ~20 % (0.6 → 0.72) so
  woods — especially the slim volcanic menhir "forests" — read as proper stands, not
  sparse. Placement stays seeded/deterministic; existing saves keep their baked positions.
- **Regiments — facing & front-arc display (AoF:R, display-only).** Every regiment
  movement-tray block now shows a flat cyan facing arrow ahead of its front rank, and
  an amber front-arc wedge (the forward 180° half-plane) toggled with the **F** key.
  The measure tool labels the other endpoint as **▲ Front** or **◣ Flank/Rear** when
  one endpoint is a regiment. Pure facing geometry in `RegimentFacingVisualizer`
  (`front_arc_contains`), unit-tested; the arrow/arc follow the tray rigidly. No rule
  is enforced — players still adjudicate facing themselves.

## [0.3.2-alpha] — 2026-06-13

### Changed
- **Go-public preparation.** The offline asset pipeline (`tools/model_forge/`,
  `assets/3d_pipeline/`) moved to a separate private repository; the game now
  consumes only its R2-delivered outputs. The asset-CDN host is centralized behind
  a `{cdn}` token (`scripts/asset_cdn.gd`), so moving to a new domain is a one-line
  change. Added issue templates, `SECURITY.md` and `CONTRIBUTING.md` for the public
  alpha; pruned internal planning/handoff docs.

### Added
- **Units block line of sight (Asgard tournament standard, display-only).** The
  measure tool's LOS check now treats every on-table OPR model as a blocker: a model
  stops the line at its Asgard Height when that Height is ≥ both endpoints', gaps under
  1″ between models of the same unit count as closed (the line can't thread through an
  almost-closed formation), and the units at the line's own endpoints never block their
  own sight line. Pure 2D geometry in `LosRules` (`units_block_line`, base-radius +
  segment/circle helpers), unit-tested; the measure line turns red + shows 🚫 exactly as
  with terrain. Players still apply the rule themselves.
- **UI audio completed: hover + keyboard-focus ticks and a settings slider.** The
  `UiFeedback` autoload (procedural tones on the dedicated "UI" bus, auto-wired to
  every `BaseButton`) now also plays a quiet micro-tick on hover and on keyboard/
  controller focus — not just on click — and the Settings window gains a "UI Volume"
  slider; the UI bus volume persists like the other buses. Closes the playbook's
  "UI audio" item.
- **Multiplayer lobby, in-game chat and player names.** Players now enter a **name**
  in the Host/Join dialog (persisted to `user://`, synced host-authoritatively); it
  shows in the dice log, on 3D avatars and in a new connected-player roster. An
  **in-game chat** panel (docked bottom-left, Tactical-HUD chrome) carries messages
  over the existing reliable RPC path — Enter focuses the input, Esc returns to the
  game, and all three keyboard-input paths (the polled WASD camera, object shortcuts,
  Delete/Backspace) are frozen while typing so nothing fires mid-message. A **room
  browser** ("BROWSE ONLINE GAMES") lists joinable public rooms (a new opt-in "list
  publicly" toggle on hosting) and joins by click; private rooms stay code-only. The
  relay gains an additive `list_rooms` command (public, non-full, non-paused rooms
  only). Menu number-key shortcuts are now bound to the live on-screen index. New
  pure `PlayerIdentity` helper (unit-tested). **Protocol bump → `0.3.2-alpha`**. The
  relay was redeployed to Fly.io on 2026-06-12 (bundling `list_rooms` + the previously
  pending host-drop reconnect); a `list_rooms` smoke test against the live server passed.
- **Extended dice options: success counting, modifiers and rerolls** (display-only
  aids — the tool counts, the players apply the rules). The dice panel gains a
  success target (2+…6+) and a modifier stepper; the per-face readout tints
  successes and shows the success count, honouring the OPR rule that natural 6s
  always succeed and natural 1s always fail regardless of modifiers (GF/AoF Core
  Rules v3.5.1, p.1 "Modifiers" — no artificial modifier cap, OPR has none). After
  a roll, one click re-rolls the fails / natural 1s / natural 6s (forced rerolls à
  la "Bane") / all dice: only those dice are physically re-tossed while the kept
  ones stay frozen in place, and the combined result is logged as a tagged reroll
  ("↻3 fails"). Rolls broadcast faces + evaluation context, so remote players see
  the same successes and reroll tags; rule logic lives in the new pure `DiceRules`
  (`dice_rules.gd`, unit-tested). The dice log's local-player label is now "You"
  (was the stray German "Du"), and the dead bottom-centre `DiceResult` label is
  removed.
- **Loading screens & black scene transitions** (`loading_overlay.gd`): a reusable
  overlay with a label and a cyan bar that fills with continuous exponential smoothing
  (no stepping). Full-screen for the menu build ("PREPARING BATTLEFIELD", gated on
  diorama-ready so the menu fades in fully built) and the menu→game transition (real
  threaded-load progress; replaces the old grey fade); a compact centred-panel variant
  for the in-game army import ("LOADING ARMY"). The table-size chooser no longer flashes
  grey (`transparent = true`), the army loading bar is visible immediately (dialog hides
  before the blocking spawn; spawn yields per unit and reports progress).

### Changed
- **One lighting mood system: atmosphere only.** The standalone lighting "presets"
  (F1–F5 hotkeys + the settings PRESETS section, plus orphaned Bright Studio / Dramatic)
  are removed; moods are chosen via the ATMOSPHERE section only. Sunset is the standard,
  applied from the first rendered frame through the intro fly-in (no mid-intro snap).
- **Quality-switch freeze fixed & transitions sped up.** Switching to/from Performance
  no longer freezes in fullscreen (the FSR↔bilinear scaling-mode toggle that recreated
  the swap chain is gone — scaling mode is now constant; Ultra MSAA 8×→4×). Menu↔game
  transitions are faster: tree/mini GLB PackedScenes cache statically across instances,
  minis load after the first frame, the grass tuft mesh/texture is cached.

### Fixed
- **Graphics switch off Performance — de-burst the render-target resize.** Switching
  from Performance to any higher tier was the only preset change that resizes the 3D
  render target (`scaling_3d_scale` 0.77→1.0); bundled in one frame with the MSAA +
  shadow-atlas reallocation it could freeze the picture in fullscreen — root-caused to
  an NVIDIA driver bug (≤ 580.126 under X11; fixed in 580.142) that the burst triggers.
  The scale change is now staggered onto its own later frames (no-op when unchanged, so
  Low↔Ultra stay instant). The definitive fix is updating the NVIDIA driver to ≥ 580.142.
- **Pink/magenta/rainbow table — two distinct bugs, both fixed.** (1) The ground
  micro-detail `NoiseTexture2D`s were regenerated per material rebuild and raced the
  renderer → rainbow speckle; cached once now. (2) The scene was lit by the procedural
  space-skybox (ambient=Sky + IBL + SDFGI sky light), whose GGX radiance bake was
  intermittently GPU-garbage → flat magenta/green/white; scene lighting is decoupled
  from the sky (ambient=Color, reflections disabled, no SDFGI sky read), in the game and
  the menu diorama. Battlemaps are also capped at 4096 px + uploaded as RGBA8.

### Added
- **AAA main menu: command console over a live burning battlefield.** The startup
  menu is rebuilt around a real-time night diorama (`menu_diorama.gd`) that runs the
  PRODUCTION battlefield stack in a SubViewport: textured ruin shells with war-torn
  fires + rubble, volumetric trees, a shipping container, grass, ground mist, the
  Night lighting preset and a slow long-lens orbit camera with depth of field and
  mouse parallax — plus a miniatures vignette (curated GLBs, loaded from the local
  model cache only). The UI is a left command column in the HudTokens language:
  Orbitron wordmark, frameless list buttons with amber mono indices + cyan accent
  bars (keyboard focus gets the same affordance; focus chain loops), a typewriter
  "intel ticker" rotating the anti-war quotes (`menu_ticker.gd`), version/build
  footer bound to the project config, and the social buttons finally wired. New:
  **CONTINUE** (loads the newest save, amber, only when a save exists — via
  `SaveManager.latest_save_info()`) and **SETTINGS** (the in-game settings window,
  bound against the diorama's lighting controller). Entrance is choreographed on the
  motion tokens (wordmark power-on, staggered button cascade, ticker beat), hovering
  key entries nudges the lens, and after 60 s idle the UI sleeps while the camera
  tours the battlefield (any input wakes it; Reduce Motion skips all of it). A quiet
  battlefield soundscape plays on the menu (war one-shots at −10 dB + fire crackle)
  under a somber CC0 dark-ambient drone on the Music bus ("Dark Ambient Loop" by
  goulven, freesound; synth-pad fallback until cached). Host/Join dialogs restyled to
  the HudTokens glass + HudFrame chrome. PERFORMANCE tier (and tests/headless) keep
  the classic space-skybox backdrop; the menu deliberately never instantiates
  AtmosphereController, so `user://atmosphere.cfg` stays untouched (test-pinned).
- **Startup update check.** On launch, the desktop game checks the project's GitHub
  Releases for a newer build and, on a hit, offers a non-blocking "Download / Later /
  Skip this version" prompt before the menu — never blocking startup. Compares the
  running `config/version` with SemVer precedence (prerelease-aware), skips on web/itch
  (always the latest deploy), and fails safe when offline. Inert until releases are
  published; see [`docs/UPDATE_CHECK.md`](docs/UPDATE_CHECK.md).
- `tools/model_forge/generate_battlemaps.py` rewritten for the new process, and
  `tools/model_forge/publish_biomes.py` to upload battlemaps + write the manifest. Runbook:
  `docs/runbooks/biome-r2-publish.md`.
- `BiomeLibrary` (+ tests). `AssetDownloadManager` generalized (configurable cache dir +
  file extension) so it serves both GLBs and WebP battlemaps.
- **Battlefield atmosphere: one-click moods, war-torn fires and a procedural
  soundscape** (see [`docs/ATMOSPHERE.md`](docs/ATMOSPHERE.md)). The Settings window
  gains an ATMOSPHERE section: Day / Sunset / Night / Overcast / Rain presets that
  blend lighting (new "Night" and "Storm" lighting presets), sky mood and ground-mist
  tint/density over 2 s; Rain adds table-sized rain particles and random lightning
  (dedicated flash light) with delayed, distance-volume thunder. A "war-torn" toggle
  dresses ~22% of ruin wall cells with small fires (additive flames, rising smoke,
  flickering OmniLight — deterministic per cell from the synced wall data, so all
  clients see the same burning walls; light/smoke counts gate by quality tier). A
  "distant war sounds" toggle plays occasional artillery/MG rumbles from random
  directions (first one 2–6 s after enabling). Audio uses real **CC0 recordings**
  (freesound.org; sources in `tools/model_forge/fetch_ambience_audio.py`) delivered
  from R2 (`assets/ambience_manifest.json` + `ambience_library.gd`) and hot-swapped in
  once cached, with procedural synthesis (`scripts/ambience_synth.gd`) as the
  immediate/offline fallback — all on the existing Ambience bus. Preset + toggles
  persist per player (`user://atmosphere.cfg`).

### Changed
- **Scatter decor: rubble at ruin walls + grassland grass.** Every ruin wall segment
  grows a deterministic debris pile of angular brick fragments along both sides —
  densest directly at the wall, tapering out to 1" (quadratic falloff). The fragments
  wear the wall's own themed masonry panel in world-triplanar projection, so each
  brick samples a different patch and the biome theme (grey / adobe / snowed) carries
  over automatically. The grassland biome additionally grows area-wide grass tufts
  (slender anti-aliased curved blades on crossed quads, 5-10 mm, colour-jittered,
  mipmapped against distance shimmer; `grass_field.gd`, cleared on other biomes).
  Both render as ONE MultiMesh each (a single draw call — no measurable cost) and
  scale with the graphics quality tier (PERFORMANCE: none; LOW..ULTRA: 40-180
  stones/segment, 1200-6500 tufts/m²), rebuilt only on layout/biome/quality changes.
- **Biome-themed terrain prop sets: desert and tundra maps get their own looks.** The
  prop manifests carry per-biome panel sets selected by a name prefix
  (`BIOME_PROP_THEMES` in `terrain_overlay.gd`; `table.set_biome` re-themes the overlay
  in place). On `arid_desert`, ruin shell walls render fine sun-dried mud-brick masonry
  with an arched two-light adobe window (`generate_ruin_walls.py --theme desert`), and
  forests grow saguaro / organ-pipe / joshua-tree variants (billboards + TRELLIS GLBs).
  On `frozen_tundra`, the approved castle stone comes snowed in (snow on every ledge,
  frosted Gothic window), forests grow snow-laden conifers (spruce / fir / mountain
  pine), and even the containers wear snow caps + frost via their own theme map
  (`BIOME_CONTAINER_THEMES` — the desert keeps the plain containers). The minefield is
  biome-agnostic; remaining biomes keep the default set for now.
- **Dangerous terrain is a textured minefield (grassland), delivered from R2.** The
  3×2-cell piece scatters **15 anti-tank mines** (flat olive discs wearing a keyed
  TM-62-style pressure-plate texture, ≥0.9″ apart via best-candidate sampling) and
  plants **2 weathered skull-and-MINES warning signs** at opposite corners of the
  field. Facings are seeded from the synced layout data (multiplayer-deterministic);
  everything stays passable (OPR: Dangerous). Textures ship via
  `assets/hazards_manifest.json` + `hazards_library.gd` (cache `user://hazards_cache`);
  recipe: `tools/model_forge/generate_hazards.py`. Holographic mine/sign fallbacks
  upgrade in place; the old mine/puddle mix is no longer generated (puddles still
  render for legacy saves).
- **Blockers render as textured shipping containers, delivered from R2.** The 6×3×2.5″
  box wears weathered container faces (corrugated long sides, cargo-door ends, rusty
  roof) in two colourways — rust-red and steel-blue — picked deterministically per
  blocker from the synced layout data. Faces ship via `assets/containers_manifest.json`
  + `containers_library.gd` (cache `user://containers_cache`); recipe:
  `tools/model_forge/generate_containers.py`. The holographic box stays as the offline
  fallback; collision is unchanged (Impassable full box).
- **Forest trees are textured volumetric 3D models, delivered from R2.** Each of the
  three deciduous variants (oak / ash / linden — keyed Gemini renders, no cones, no
  green spheres) is converted to a real textured mesh via TRELLIS (100k tris, 2k
  texture — the model-railroad-tree look that fits the tabletop aesthetic; recipe:
  `tools/model_forge/generate_trees.py` + `generate_tree_models.py`). Delivery is
  progressive: lightweight billboard panels (two crossed alpha quads + a bird's-eye
  crown cap) pop in first, then the GLBs upgrade the forest in place; offline keeps the
  holographic trunk+cone fallback (`assets/trees_manifest.json` + `trees_library.gd`,
  cache `user://trees_cache`). Variant, size (75–125%) and facing are seeded per tree
  from the synced layout data (multiplayer-deterministic). Trees keep ~1.5″ clear of
  the forest-area boundary and ≥2″ from each other (best-candidate sampling), so crowns
  no longer interpenetrate.
- **Ruin walls render as textured shells (the approved mossy look), delivered from R2.**
  The in-game renderer now ports `tools/render_ruin_walls.gd`: per-segment masonry panels
  picked from the wall `role` (solid / top-damaged / see-through doorway / inset Gothic
  window on "full" cells; the stepped crumble textures toward the open ends, mirrored via
  a new `taper_dir` emitted by `TerrainPrefabs` so the wall always steps DOWN to the free
  end), built as front+back quads with a plain-stone top cap (alpha-scissor holes, normal
  map). Collision stays a full-height Impassable box (OPR: ruin walls are Impassable).
  The 9 runtime panels are fetched on demand from R2 (`assets/ruins_manifest.json` +
  `ruins_library.gd`, cached in `user://ruins_cache`); until cached, walls keep the
  previous triplanar stone material and upgrade in place. The per-cell "full" panel pick
  is seeded from the segment's cell identity, so all multiplayer clients see the same
  windows/doorways; `role`/`taper_dir` now survive saves and the network layout sync.
  The shells are **fully closed**: top caps follow the panel's alpha silhouette strip by
  strip (stepped crumble tops are capped stone-by-stone, knocked-out top courses never
  get a floating lid), step risers and free wall ends get stone faces, interior openings
  (gothic window lights, doorways) are lined with pixel-flush stone reveals, and corner
  posts are masonry prisms sitting slightly proud of — and rising slightly past — the
  wall shells (no coplanar z-fighting, neither on the faces nor above the post).
- **Biome battlemaps reworked + moved to R2 delivery.** Each biome is now a single,
  non-tiling, scale-locked 6×4-ft ground texture (Gemini 3 Pro Image, ~5056×3392,
  sharpened to WebP) instead of a 1024² image tiled 3× across the table. This removes the
  visible repetition and keeps ground features at a realistic scale next to 28–32 mm
  miniatures. The table renders one image across a fixed 6×4-ft extent and centre-crops it
  for smaller tables (`table_ground.gdshader` `uv_scale`). Delivered on demand from
  Cloudflare R2 (content-addressed WebP, `assets/biome_manifest.json` + `biome_library.gd`,
  cached in `user://biome_cache`); the bundled 1024² PNGs were removed; offline fallback is
  `assets/terrain/table_surface_default.png`.
- **Ruin auto-walls** in the OPR map generator now form **two point-symmetric L-corners**
  (each leg `size−1` cells, mirrored) to match the standard OPR ruin layout, instead of a
  single full L. Each wall segment carries a crumble `role` so the wall steps down toward
  its open ends.
- **Ruin walls are textured**, not holographic: wall segments + corner posts render with a
  lit world-triplanar stone material (`ruins_wall.webp`) and shadows.

### Fixed
- **Flat overlays stack in fixed 1 mm layers instead of sharing planes.** Terrain
  tiles sit 1 mm above the table, deployment zones (rect, circular and custom
  polygons) at 2 mm, mission objectives at 3 mm (seize ring on the layer, token on
  top of the ring) — explicit layer constants in `terrain_overlay.gd`, so overlapping
  translucent overlays can no longer z-fight or produce shader artifacts.
- **Box selection starts reliably regardless of view angle.** The rubber band only
  appeared when the click ray hit the TABLE collider — at shallow camera angles, past
  the table edge, or with the cursor over a terrain prop (wall/container/tree) nothing
  happened. Any click that doesn't hit a selectable object now starts the box. Also,
  objects behind the camera no longer get caught by the box (unproject mirrors them
  onto the screen at shallow angles).
- **Unit hover tooltip stays compact**: it lists special rules / equipment by name only
  (comma-separated) instead of printing every rule's full explanation — units with many
  rules grew a screen-filling tooltip. The explanations remain in the unit card opened
  by clicking the unit.
- **Biome battlemaps never loaded when chosen in the table-size dialog.** Two stacked
  bugs: `table.setup_table()`'s border cleanup freed the `BiomeLibrary` child (killing
  the battlemap download mid-flight, with no retry — the dialog applies the size before
  the biome, so this hit every fresh start), and `AssetDownloadManager`'s single shared
  `HTTPRequest` failed follow-up requests with `ERR_BUSY` while another download was
  running (e.g. picking a biome while the default biome was still downloading).
  `setup_table()` now preserves the delivery service and downloads queue up instead of
  failing silently.
- **GPU texture-wrap slivers on ruin crumble walls**: the 0..1-UV masonry panels are
  never tiled, but texture REPEAT wrap-bled the opposite edge at u=1.0 under anisotropic
  filtering — full-height stone slivers at the free end of mirrored crumble panels.
  Panel materials now clamp (`texture_repeat = false`); same fix in the reference tool.

### Maintenance
- The mossy-stone **ruin source-art set** (solid / top-damage / opening / crumble / Gothic
  window + normal map + the 2 MB masonry source) is archived on **R2**
  (`<legacy-cdn-host>/terrain-source/ruins/`), not bundled — only the runtime
  `ruins_wall.webp` ships. Reproducible recipe (`tools/model_forge/generate_ruin_walls.py`),
  a software-GL reference renderer (`tools/render_ruin_walls.gd`), and a GPU-machine handoff
  (`docs/HANDOFF_RUIN_WALLS.md`) for the shell-wall finishing pass.

## [0.3.1-alpha] — Alpha Release Candidate

Goal of this release: a playable, internet-multiplayer Alpha RC with all miniature
3D models delivered on demand from R2.

### Added
- **Multiplayer version handshake.** On join, the client announces its game version
  and the host gates state sync on a match — a 0.3.0 and a 0.3.1 player can no longer
  share a table. Mismatches are rejected host-side (kick) and refused client-side,
  with a clear message; a silent/old client is dropped after a grace timeout.
- **On-demand 3D model delivery (Cloudflare R2).** Miniature GLBs are content-addressed
  (`sha256.glb`) and fetched at runtime from `<legacy-cdn-host>`, mapped by
  `assets/model_manifest.json`. Builds no longer bundle them.
- **IP-safe faction generation overhaul** in Model Forge: positive-only prompts,
  per-faction `ip_strict` / `bio_weapons` flags, per-unit `type:` (vehicle / walker /
  aircraft / titan), humanoid-only design cues — plus a **3-versions-per-unit "pick the
  best" review tool**.
- **Factions shipped to R2:** Alien Hives (41), Battle Brothers (23) and Robot Legions
  (29), joining the earlier Dao Union (19) and a Dark Brothers hero — `model_manifest.json`
  now resolves **113 models across 5 factions**, all verified live on `<legacy-cdn-host>`.
- **OPR special-rule descriptions.** Rule explanations are fetched from the army-forge
  API on import (army-book + common rules per game system, cached) and shown per rule in
  the stats tooltip, so players can read what each rule does.
- **Multiplayer reconnect.** Relay drops are detected (heartbeat-ack timeout / socket
  close), the player is told, and a guest auto-rejoins the same room — the host re-syncs
  full game state, so nothing is lost. Failed rejoins / host drops end the session with a
  clear message.
- **Confirm dialogs** for the destructive Sort Table / Clear Table / Next Round actions
  (Next Round also clears all activation tokens).
- **Terrain reference aids (Asgard tournament standard, display only).** Every
  contiguous terrain zone carries an always-visible effect label (Cover / Difficult /
  Dangerous / Impassable / Height), and the measure tool is height-aware: a terrain
  zone on the line blocks line of sight only when its Height ≥ both endpoints' Asgard
  Height category (derived from Tough + Hero/Fear in `los_rules.gd`) and neither
  endpoint stands inside that zone — a 🚫 marker flags the blocked line. Players apply
  all effects themselves.

### Changed
- Builds stay slim: miniature GLBs and their textures are gitignored **and** excluded
  from every export preset (delivered from R2 instead).
- `Shift + Click: Measure` added to the in-game shortcut list.
- TRELLIS export no longer re-decimates meshes (keeps the approved 1536 / 300k / 4096
  quality).
- Map editor Deployment tab reduced to a show/hide toggle; the manual unit-placement
  compliance checks (Scout/Ambush/in-zone) were removed (players verify placement).

### Fixed
- Weapon-team `Tough(X)` is applied only to the carrier model, not the whole squad
  (general fix across all armies).
- Removed the oversized terrain-crossing warning symbols (skull / exclamation) while
  keeping the line-tint + dangerous/difficult detection.
- Multiplayer: enemy **weapon special rules** now show for networked units; a loaded
  map's **mission objectives** now sync to all players.
- `Ctrl+Z` undo only reverts the local player's **own** actions in multiplayer.
- Ground mist no longer wafts past the table edge (seen in the Windows build).
- Menu hover-scale no longer clips at the column edge.

### Maintenance
- Disk cleanup: purged 734 MB of redundant R2 upload-staging GLBs (all verified
  present on R2 before deletion).
- Repo hygiene: Model Forge scratch (TRELLIS temp, engine-comparison render sweeps,
  one-off experiment scripts) is gitignored; the reusable faction batch pipeline
  (`faction_finalize` / `faction_publish`) and TRELLIS research notes are versioned.
- gdUnit4: 255 tests green.

### Known follow-ups
- Host-side reconnect (preserving a room when the HOST drops) needs relay-server room
  preservation + a Fly.io redeploy.
- OPR rule descriptions resolve for freshly imported armies; loaded saves / remote-only
  armies show rule names without descriptions (persist/sync is a future step).

## [0.3.0-alpha]

- First Alpha 0.3 line: Windows + Linux desktop builds via CI; internet multiplayer
  through the Fly.io WebSocket relay (6-char room codes); Model Forge image→TRELLIS→GLB
  pipeline with base-less, IP-safe, positive-only generation and an engine comparison
  that selected TRELLIS for CC-BY-SA safety.
