# Changelog

All notable changes to Niemandsland. Versions follow the project's alpha line
(`config/version` in `project.godot`). Game-state save format (`.nml`) is versioned
separately (`SAVE_VERSION` in `save_manager.gd`).

## [Unreleased]

### Added
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

### Changed
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
