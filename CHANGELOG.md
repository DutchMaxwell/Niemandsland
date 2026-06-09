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

### Changed
- **Ruin auto-walls** in the OPR map generator now form **two point-symmetric L-corners**
  (each leg `size−1` cells, mirrored) to match the standard OPR ruin layout, instead of a
  single full L. Each wall segment carries a crumble `role` so the wall steps down toward
  its open ends.
- **Ruin walls are textured**, not holographic: wall segments + corner posts render with a
  lit world-triplanar stone material (`ruins_wall.webp`) and shadows.

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
