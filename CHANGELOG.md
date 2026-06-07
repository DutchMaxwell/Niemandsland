# Changelog

All notable changes to Niemandsland. Versions follow the project's alpha line
(`config/version` in `project.godot`). Game-state save format (`.nml`) is versioned
separately (`SAVE_VERSION` in `save_manager.gd`).

## [0.3.1-alpha] — Alpha Release Candidate

Goal of this release: a playable, internet-multiplayer Alpha RC with all miniature
3D models delivered on demand from R2.

### Added
- **Multiplayer version handshake.** On join, the client announces its game version
  and the host gates state sync on a match — a 0.3.0 and a 0.3.1 player can no longer
  share a table. Mismatches are rejected host-side (kick) and refused client-side,
  with a clear message; a silent/old client is dropped after a grace timeout.
- **On-demand 3D model delivery (Cloudflare R2).** Miniature GLBs are content-addressed
  (`sha256.glb`) and fetched at runtime from `assets.akesberg.de`, mapped by
  `assets/model_manifest.json`. Builds no longer bundle them.
- **Alien Hives faction** (41 models) shipped to R2.
- **IP-safe faction generation overhaul** in Model Forge: positive-only prompts,
  per-faction `ip_strict` / `bio_weapons` flags, per-unit `type:` (vehicle / walker /
  aircraft / titan), humanoid-only design cues — plus a **3-versions-per-unit "pick the
  best" review tool**.

### Changed
- Builds stay slim: miniature GLBs and their textures are gitignored **and** excluded
  from every export preset (delivered from R2 instead).
- `Shift + Click: Measure` added to the in-game shortcut list.
- TRELLIS export no longer re-decimates meshes (keeps the approved 1536 / 300k / 4096
  quality).

### Fixed
- Weapon-team `Tough(X)` is applied only to the carrier model, not the whole squad
  (general fix across all armies).
- Removed the oversized terrain-crossing warning symbols (skull / exclamation) while
  keeping the line-tint + dangerous/difficult detection.

### Maintenance
- Disk cleanup: purged 734 MB of redundant R2 upload-staging GLBs (all 62 verified
  present on R2 before deletion).
- gdUnit4: 33 suites / 238 tests green.

### In progress for this RC
- Battle Brothers faction → 3D → R2.
- UI polish: confirm dialogs for Sort / Clear Table / Next Round (with activation
  reset), deployment-zone menu reduced to show/hide, hover-effect column-width fix.

## [0.3.0-alpha]

- First Alpha 0.3 line: Windows + Linux desktop builds via CI; internet multiplayer
  through the Fly.io WebSocket relay (6-char room codes); Model Forge image→TRELLIS→GLB
  pipeline with base-less, IP-safe, positive-only generation and an engine comparison
  that selected TRELLIS for CC-BY-SA safety.
