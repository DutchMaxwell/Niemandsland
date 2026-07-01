# Changelog

All notable changes to Niemandsland. Versions follow the project's alpha line
(`config/version` in `project.godot`). Game-state save format (`.nml`) is versioned
separately (`SAVE_VERSION` in `save_manager.gd`).

## [0.3.7.2-alpha] — 2026-07-01

### Added
- **Regiments: frontage cycle, axis-locked drag, pivot snap.** Three Age of Fantasy: Regiments
  handling aids for the movement-tray block (v3.5.1, p.6 "Unit Formations" + p.8 "Pivoting"):
  - **Shift+F** cycles the selected regiment's frontage (models per rank) through the common
    widths (5 → 4 → 3 → 2 → 1 → 5, skipping widths wider than the live model count). Re-ranks
    the block in place, undoes as one action, and syncs to multiplayer peers.
  - **Shift+drag** locks a regiment's movement to its facing axis (forward/backward only, no
    sideways drift) — the natural input for Rush/Charge (forward-only) and a quick Advance.
  - **Ctrl+R** snaps the selected regiment tray(s) to the nearest 90° cardinal facing, for fast
    alignment. The player decides whether the snap is a legal pivot (Hold ≤ 180°, Move ≤ 90°).
- **Regiments: pooled-wound counter, radial menu, arc quadrants, rotation readout.** Four more
  AoF:R handling aids:
  - **Pooled-wound counter (Tough(1) units).** A Tough(1) regiment is treated as a single
    Tough(pool) entity for the wound counter (a 10-model Tough(1) unit = Tough(10)). A red
    **WoundMarker token** (the same disc + "WOUNDS" arc + number used for per-model wounds)
    appears on the **unit boundary** (alongside Fatigued/Shaken/Activated) and counts the
    casualties **UP** from 0. Right-click a regiment model → radial menu offers a **W n/n**
    item that opens the **standard WoundsDialog** (the same as for a single Tough(X) model)
    with +/- / Heal Full / Kill — each click adjusts the pool, removing/reviving models from
    the back rank (AoF:R v3.5.1 p.9). Undoable, MP-synced, persisted in `.nml`. Individual
    model wounding/deletion is disabled for Tough(1) regiments. **Tough(X>1) regiments keep
    the classic per-model wound tracking** (each model absorbs its Tough value before dying;
    the standard wounds dialog applies per model).
  - **Regiment radial menu.** Right-clicking a Tough(1) regiment model opens a regiment-specific
    menu (wound counter, frontage, activate, status tokens, delete unit) instead of the per-model
    menu. Tough(X>1) regiments keep the classic model/unit menu.
  - **45° arc quadrants (selected unit only).** The facing display (F key) now shows the four arcs
    — front, left flank, rear, right flank — each a 90° quadrant (±45°), per AoF:R v3.5.1 p.5
    "Unit Facing" (was a single 180° front half-plane). Arcs render only on the SELECTED regiment
    (not all), with a 3× larger radius (18″) and smaller labels (20% font). The measure-tool
    label reads Front / Left Flank / Rear / Right Flank.
  - **Mouse-driven rotation + readout.** Regiment trays rotate by MOUSE control (the tray turns to
    face the cursor while R is held) instead of a continuous spin — the natural input for aligning
    a ranked block. A floating label shows the angle between the current cursor direction and the
    gesture's start facing (not a running sum), anchored above the pivot (20% font).
- **Dice results grouped by colour.** When a roll mixes per-die colour tags, the result readouts
  split into one swatch-headed group per colour, side by side (untagged/free first, then red, blue,
  …), each with its own per-face counts and success total — in both the current-roll column and the
  dice log. Single-colour or all-untagged rolls keep the compact single-column layout. The dice icons
  themselves are tinted in their tag colour, and the log stacks the per-colour groups as horizontal
  strips. (#77)
- **Movement special rules reflected in the Shift+M reach bands.** The Advance/Rush reach indicator
  now parses each unit's imported OPR rule descriptions, so any movement rule — **Swift** and beyond
  — adjusts the bands automatically, not just the hard-coded Fast/Slow (which keep a constant
  fallback when no description text is present). Rating parentheticals are stripped, so "Swift(2)"
  matches its "Swift" description. Rules granted **indirectly** (an ability that grants Swift) are
  picked up too, a rule that **cancels Slow** restores normal movement, and **unit-wide auras**
  (e.g. a Swift Aura) extend every model's bands. (#79)
- **Auto-deploy terrain count scales with table size.** The auto-deploy piece count (and its success
  threshold + the stats/recommendation readouts) now scales by table area relative to the 6×4 ft
  reference, clamped to [0.45, 2.0] — a 4×4 table drops from a fixed ~15-20 pieces to ~10-13, so
  small tables are no longer cluttered. DANGEROUS keeps its floor of 2 pieces. (#83)
- **Type-aware base sizing for vehicles, walkers and artillery.** When Army Forge provides no base,
  a bracketless big single model is classified by name keywords + Tough into walker / vehicle /
  artillery / monster and given an OPR-standard base — round for walkers/monsters/infantry, oval for
  vehicles and artillery — instead of keying the footprint off durability (which gave a Tough(6)
  vehicle a tiny base and a Tough(12) walker a huge one). Tough now only sizes within a type, and an
  existing base is never shrunk.
- **Biome-aware dangerous terrain + ruin polish.** Dangerous terrain now sits on the same oval ground
  pad as forests, biome-cropped (incl. grassland), with the real mine asset (was a procedural disc)
  and, where one exists, the biome's own hazard prop (volcanic lava crater, jungle/alien carnivore
  plant). Ruins gained closed window reveals (jamb/sill/lintel), wall-foot rubble, coarser masonry,
  and fixes for the L-corner / platform z-fighting and per-column triplanar striping.
- **Return destroyed units + revive models.** The army-tray menu can **return a fully destroyed unit**
  to the table, and a unit's **destroyed models can be revived** (rebuilt from the back rank, MP
  kill/revive collision state synced) — groundwork for the OPR special rules that bring units/models
  back.
- **Movement cap (opt-in).** A selected model/unit can be limited to its Advance or Rush/Charge
  allowance, so a drag stops at the legal distance — reuses the Shift+M reach math. Off by default.
- **Avatar + cursor labels smaller; avatars fade on zoom.** The remote-cursor ring text and avatar
  name labels are much smaller and tidier, and a player's avatar fades for everyone else as its owner
  zooms in, so it stops hiding the detail they're inspecting.
- **Deployment-zone colour flip.** A player who takes the *other* table edge can swap the two zone
  colours so their colour matches their side.

### Fixed
- **Self-updater (Linux) swaps the running binary correctly.** The in-place apply copied the new files
  over the still-running executable, which Linux refuses (`ETXTBSY`) — so the one-click update failed
  with a misleading "permissions" message and fell back to the browser download. It now **unlinks each
  existing target before copying** (the running process keeps its open inode), matching the macOS path.
  Takes effect for updates starting *from* the release that carries this fix.
- **Regiments keep their facing after a drag.** Auto-face-on-drop was rotating the movement-tray block
  to the drag direction, silently overriding the player's set facing (front/flank/rear arcs and the
  facing arrow drifted out of sync, and the wrong rotation was broadcast to multiplayer peers). A
  regiment's facing now only changes via an explicit pivot — **Age of Fantasy: Regiments v3.5.1, p.8
  "Pivoting"** — while loose models still auto-face their movement direction as before.
- **macOS build is no longer reported as "damaged".** The macOS app is now **ad-hoc signed** in CI
  (via `rcodesign` on the Linux build runner — no Apple account, certificate or notarization), so it
  launches on Apple Silicon and Gatekeeper shows the milder "unidentified developer" prompt
  (right-click → Open) instead of *"Niemandsland is damaged and can't be opened"*. The app is still
  unnotarized; the README documents the one-time `xattr -dr com.apple.quarantine` fallback. Takes
  effect for the next release.
- **Ambush / Scout deployment field shows on every tray.** The staging band was only built by the
  importer, so every tray-reconstruction path (live MP army-header receive, late-joiner state-sync,
  `.nml` load) rebuilt a bandless tray and the opponent saw empty zones. The band is now intrinsic to
  every tray and survives all rebuild paths. (#76)
- **Blood/oil stains no longer cover measure lines + UI.** Table-UI overlays (measure line, drag
  line, range rings, pinned ruler + their labels/LOS markers) now draw above the ground stains
  instead of being painted over — the selected unit's **boundary outline** draws above the stains
  too. (#82)
- **Selecting a dice count no longer looks like a roll.** Resting dice show a floating "?" until they
  are actually rolled, instead of showing random faces. (#80)
- **Status tokens clear when a unit is wiped.** Activated/Fatigued/Shaken tokens are dropped once a
  unit has 0 alive models (delete, last casualty, delete-models) and re-created on undo/revive. (#78)
- **Double-click selects the whole unit — including attached heroes.** Double-clicking a unit model now
  selects the entire unit (a regiment → its movement tray), and a hero attached to that unit is
  selected along with it, skipping the box-drag / radial "select all". (#81)
- **A dead model's base no longer blocks measuring or selection.** A removed/killed model's hidden base
  kept its collision, so it still intercepted measure/LOS rays and clicks. Its collision is now cleared
  when it dies, so measuring and picking pass through the empty space.
- **Dice log scrolls to the newest roll.** The dice log now reliably pins to the latest entry (the
  scroll is recomputed after the entry's final layout) instead of sometimes leaving it just off-screen.

### Changed
- **Terrain locking is manual + per-piece.** Selecting Terrain Mode no longer auto-locks pieces; lock
  a piece explicitly with **L** (select + L), so a freshly placed piece is immediately draggable.

## [0.3.7.1-alpha] — 2026-06-25

A playtest-feedback patch on top of 0.3.7 (mostly from a 2-player playtest game), plus dice
colours, an in-game self-updater, and a live asset-manifest channel.

### Added
- **Ambush / Scout deployment field.** On a player's army tray, the near third is reserved and split
  **Ambush (left, amber) / Scout (right, cyan)** by a tray-border-coloured divider, each with a small flat
  label anchored bottom-left. Units carrying the Scout/Ambush rule are auto-placed into their half on
  import (the top 2/3 keeps the normal layout). Detection covers the rule listed directly, granted by an
  upgrade/equipment item, granted to a single model, or granted via another rule's free-text description.
  Representation only; positions persist + MP-sync via `import_position`.
- **Per-die colour tagging.** Click a die in the tray to cycle it through 4 colours (e.g. "red =
  Rending"); the colours persist through the roll. Cup composition and colours sync live, so the
  opponent sees the same dice.
- **One-click in-game updater.** The "Update available" prompt now **downloads and installs** the new
  version in place and restarts — no manual unzip. It stages the download under `user://` first, and
  falls back to opening the download page if the in-place update can't run, so it's never worse than the
  old manual flow. (Linux/macOS swap the files directly; Windows uses a helper that swaps the locked exe
  after exit.)
- **Live CDN asset manifest.** The game fetches the model manifest from the asset CDN at startup, so
  3D-model fixes published after a build reach players at their next launch — no game release needed.
  Any fetch failure keeps the bundled manifest (offline-safe).
- **Multiplayer load gate.** While one player imports an army, the other player's object move/edit is
  blocked (camera, pan, zoom and chat stay free) with a "waiting for … to finish loading" banner, so a
  move can't land mid-import.
- **Auto-face on move.** A moved model turns to face its own movement direction when you drop it.

### Fixed
- **Line of sight** is no longer blocked by **dead** models (they are hidden, not removed).
- **Status/activation markers** hand over to the lone survivor when a unit is reduced to one model,
  instead of clinging to a dead model's vacated spot.
- **Boundary status tokens** ride the terrain height per token, so they no longer sink under elevated props.
- **Formation keys** (1–9 / Shift+A) centre the block on the unit's current centre, not the cursor.
- **Rotation** works both ways — hold **Ctrl** while R (single) or Shift+R (group) to reverse.
- **Terrain effect labels** stay flat on the table but face the camera, so they read from any orbit angle.
- **Dice tray:** right-clicking it no longer crashes; clicking a die reliably colours the right one; and
  the colours survive a roll.
- **HUD version label** is now derived from `config/version` (it had a stale hardcoded version); the
  on-screen control hints were refreshed.

## [0.3.7-alpha] — 2026-06-25

Multiplayer-stability patch (the headline fix), plus a macOS build, per-biome terrain,
and the bug reports from the public Alpha.

### Added
- **macOS build.** Releases now ship an (unsigned) macOS app alongside Linux + Windows.
  First launch: right-click → Open, or clear Gatekeeper once with
  `xattr -dr com.apple.quarantine Niemandsland.app`.
- **Per-biome sandbox terrain.** Ruins are placeable in *every* biome with themed wall
  panels, and non-grassland forests crop their floor from a seed-based patch of the
  biome battlemap (grassland keeps its tuned tile).
- **Banner / Musician / Sergeant.** These upgrades are now imported from ArmyForge:
  each is listed on the unit card as a rule (its effect on hover) **and** marks its
  bearer model with a base ring.
- **itch.io auto-update channel** + **anonymous relay usage stats** (totals/peaks, no
  identities) queryable via `relay/relay_stats.py`.

### Fixed
- **Multiplayer reconnect storm / desync eliminated (the big one).** A live 2-player
  game collapsed into endless reconnects and went out of sync. Root cause: the relay
  serviced each socket in one coroutine that also awaited every broadcast inline, so a
  single slow consumer's back-pressure starved *everyone's* heartbeats → both sides
  false-dropped → a reconnect storm in which the host lost its authority (a guest could
  seize the host slot) → desync. Fixes: the relay now fans out broadcasts through
  per-peer send queues (a slow peer never blocks the shared loop); the client treats any
  inbound frame as proof-of-life; the host deterministically reclaims peer 1 by its
  identity token (a guest can no longer seize it); and a superseded peer id is never
  version-kicked. Backward-compatible with 0.3.6.0 clients during the rollout.
- **#70** reconnecting players can seize objectives again; deployment-zone/objective
  overlay draw-order corrected.
- **#71** deployment-zone + objective seize-ring no longer z-fight unit bases/tokens.
- **#72** blood/oil pools no longer z-fight terrain, and undo/redo of a model deletion
  correctly restores its stain at the current position.
- **#73** a unit's OPR weapon loadout now syncs to the other player.
- **#74** the rule hover popup now also shows depth rules granted by an aura/rule.
- **Bug-report export** writes to the real localized Desktop again.
- **Movement reach rings** stay world-anchored when the mini moves.
- **In-game update prompt reaches existing players.** The update checker compared only 3
  version fields, so `0.3.6.0` and `0.3.6.1` looked identical and no update was offered;
  it now compares all 4 fields (`MAJOR.MINOR.PATCH.BUILD`).

### Changed
- **In-game update prompt** scrolls long changelogs and offers a one-click,
  right-platform download — so future patches reach players faster.
- **Version → `0.3.7-alpha`** (a 3-field bump) across `project.godot`, README,
  PROJECT_STATUS, ROADMAP, and CLAUDE.md. The jump out of the `0.3.6.x` line is deliberate:
  the already-shipped `0.3.6.0` checker only sees the first three fields, so it can detect
  `0.3.7` but not a `0.3.6.1`. Future patches can resume the 4-field scheme (`0.3.7.1`, …),
  which the fixed checker handles.

## [0.3.6.0-alpha] — 2026-06-23

Version consolidation for the public Alpha release. All planned Alpha work is
complete; remaining roadmap items are driven by alpha feedback.

### Added
- **Aircraft flight-stand hover.** Flying aircraft now hover on a tall flight stand
  (~20 cm above the table), distinct from the standard Floating offset used for
  other Flying models.
- **Mount / vehicle base + model for hero mounts.** A hero mounted on a Combat Bike,
  dinosaur or similar mount inherits the mount's own base (Tough-scaled), and
  `opr_army_manager` fuzzy-matches a faction GLB for the mount model.

### Changed
- **Version consolidated to `0.3.6.0-alpha`** across `project.godot`, the in-game
  shortcut overlay, README, PROJECT_STATUS, and CLAUDE.md.
- **OPR unit-card overhaul.** The unit card now shows item-grant hover cascade,
  faction spell list + spell-range hover ring for casters, item-granted weapons
  surfaced as real weapons, and is fully in English.
- **Correct per-model loadout distribution.** A Sergeant's special gear groups on
  the leader model; a weapon-team's enlarged base aligns with its special-weapon ring.
- **Vehicles fit their base exactly.** Oval + Tough-derived vehicle bases fill the
  base footprint with no overhang, and the long-axis orientation is deterministic.
- **Export-presets manifest packing fix.** The built game now correctly packs the
  asset manifests, closing a gap where manifest entries were absent in shipped builds.

### Fixed
- **MP netcode replatform — reconnect cascade eliminated.** All game messaging moved
  off `@rpc` onto a hand-rolled command protocol below the RPC path-cache (the
  version-kick reconnect cascade is gone). A 20-minute headless soak with 24 guest
  reconnects stays fully converged, zero kicks, zero crashes, no leak.
- **MP relay-restart / idle self-heal.** When the scale-to-zero relay drops its
  in-memory room (idle stop), the host re-creates the room with the same code and
  guests auto-rejoin, recovering the session automatically (relay deployed v4).


## [0.3.5.11-alpha] — 2026-06-20

### Fixed
- **Multiplayer reconnect now works — the sporadic-disconnect cascade is gone.** A guest whose
  connection blipped used to be kicked by the host on a version-handshake timeout and re-loop, often
  losing or duplicating models. Root cause: Godot's high-level `@rpc` binds its path-cache to the
  transport and assumes stable peer ids, which a relay reconnect breaks. The multiplayer messaging
  was re-platformed onto a hand-rolled command protocol that runs below `@rpc` (reconnect-safe), with
  the relay reusing a returning guest's peer id and an idempotent full-state re-sync. A 20-minute
  headless soak with **24 guest reconnects** now stays fully converged (host 92 == guest 92), zero
  kicks, zero crashes, no leak.

### Changed
- Relay: the binary broadcast now iterates a snapshot, fixing a crash under churn ("dictionary
  changed size during iteration"); a returning guest reclaims its old peer id within a 20 s window.


## [0.3.5.10-alpha] — 2026-06-19

### Added
- **Two more factions of 3D models loadable: `change_disciples` (25) + `plague_disciples` (23).**
  Their GLBs were already live on R2 but the manifest entries hadn't been committed, so the built
  game couldn't reference them (they'd have shown as placeholders). Manifest now lists **682 models
  across 29 factions** — all verified retrievable on R2 (HTTP 200).


## [0.3.5.9-alpha] — 2026-06-19

### Fixed
- **The "Loading 3D model" overlay can no longer hang forever.** A model whose GLB download never
  completes (R2 hiccup / dead connection / a not-yet-uploaded model that stalls instead of returning
  404) used to strand the asset downloader — `HTTPRequest`'s timeout defaults to infinite — so the
  army-load progress bar stuck on the last model while the rest of the game stayed responsive. Model
  downloads now time out (120 s) and fail cleanly: the load finishes and the affected model falls
  back to its placeholder. (Reported from live play: importing a second army with not-yet-uploaded
  models hung on the last model.)


## [0.3.5.8-alpha] — 2026-06-19

### Added
- **Low-framerate online-stability advisory.** During a multiplayer session, a sustained low
  framerate (the regime that degrades heartbeat cadence + backs up the send queue) now raises a
  one-shot, non-blocking banner suggesting you lower Graphics Quality, with a one-click action to
  step it down. MP-only; shows at most once per session.

### Fixed
- **Concurrent army imports no longer lose models.** A local army import now serializes against an
  arriving remote army (shared restore-lock), so two near-simultaneous mid-session imports can't
  clobber each other's bookkeeping. Surfaced + guarded by the new headless MP stress soak.


## [0.3.5.7-alpha] — 2026-06-18

Go-public prep pulled forward (de-risks the `0.3.6` cut by exercising the new URLs/domain early).

### Added
- **In-app "Credits & Licenses"** dialog in the start menu — surfaces the model **CC-BY-SA 4.0**
  attribution (plus code MIT, fonts OFL, Phosphor MIT, Godot MIT) to players, not only in repo docs.
- **Getting Started** player quickstart (`docs/GETTING_STARTED.md`) + expanded **Known Issues**.

### Changed
- **Asset CDN host → `assets.niemandsland.xyz`.** `<legacy-cdn-host>` stays live in parallel
  (same R2 bucket) so builds already in the wild keep working.
- **Update-checker + clone URLs → the `Niemandsland` repo** (were `openTTS`; GitHub redirects
  covered the old name until now).
- **THIRD_PARTY**: declared the app icon + bundled terrain textures, and pinned the generated
  miniatures / terrain / icon to **CC-BY-SA 4.0** (closing the undeclared-asset gap).


## [0.3.5.6-alpha] — 2026-06-18

### Fixed
- **More base-anchored elements now follow the Tough-enlarged base** (follow-up to 0.3.5.5). The
  measuring **ruler's edge**, **status-token placement**, the **special-equipment ring**, the
  **coherency highlight ring** and **unit line-of-sight** all read the model's *actual* (enlarged)
  base via `effective_base_props`, not the unit-suggested size. Previously the ruler measured from —
  and tokens sat on — the smaller original base edge *inside* the visible base.


## [0.3.5.5-alpha] — 2026-06-18

### Fixed
- **Per-model Tough base no longer scale-creeps the model.** When a model's Tough(X) warranted a
  bigger base than the unit's suggested size, the model mesh was scaled up with it. The mesh is now
  fitted to the model's **natural** base; only the base (ring + collision) grows. Both spawn paths
  (import + save/MP restore).
- **Tokens & measuring now anchor to the enlarged base.** Range rings, the movement reach indicator
  and arrangement spacing read the model's **actual** (Tough-enlarged) base via a shared
  `OPRArmyManager.effective_base_props` helper, instead of the unit-suggested size — so the
  measuring edge matches the base you see. (The unit boundary outline already did this.)


## [0.3.5.4-alpha] — 2026-06-18

### Added
- **In-game bug report with screenshot (F12).** Pressing F12 grabs the current view and bundles
  it with the anonymised recent log into a single zip on the Desktop — so visual / behavioural
  glitches (a mini clipping terrain, wrong scale, a misplaced model) that raise no error and never
  reach the log can finally be reported. Player names, room code and OS username are scrubbed
  exactly as the menu's "Report a problem".

### Changed
- **New app icon** — the Niemandsland "N" monogram replaces the placeholder grid-on-green icon
  (window/taskbar + system launcher).
- **Window opens on the screen under the mouse cursor** (multi-monitor fix; previously always
  centred on the primary screen).


## [0.3.5.3-alpha] — 2026-06-18

Test-build delta over `0.3.5.2` (handed to the tester):

### Fixed
- **Generic-object radial "Info" now shows a popup** (object name + type) instead of only
  printing to the log — this also wires up the previously-unused model-info popup.

### Changed
- **Dead-code cleanup** — removed the long-hidden in-game import UI (direct 3D-model load,
  TTS save-file import), the superseded in-game table-size panel, the legacy TTS terrain
  browser + its empty `TerrainLibrary`, and the now-orphaned TTS save-file import path +
  parser. No user-facing feature lost (all were hidden / unreachable); the casual sandbox
  "Terrain Mode" toggle moved next to the map-layout button.
- **Test coverage** raised 558 → 614 (new regression suites for object_manager, OPR import,
  network state, map-editor grid math, and radial menus).


## [0.3.3-alpha – 0.3.5.2-alpha]

> Test builds `0.3.4.1`–`0.3.5.2` were handed to testers; the headline work of
> that run:

### Fixed
- **"Report a problem" now captures the actual game.** The engine rotates `niemandsland.log` on
  every launch, so the report — which only read the current log — missed the session the player was
  reporting (e.g. after restarting to reach the start-menu button). It now includes the most recent
  few log files (current + prior sessions, each tailed), chronologically. And because that pulls in
  earlier sessions, **room codes mentioned in the log are now scrubbed too** (discovered by pattern;
  player names never reach the log) — so the bundle stays anonymous as promised.
- **Multiplayer sync overhaul** — the reconnect / rate-limit / army-sync cascade, live-validated
  across two clients. A wall-clock send-rate cap (the old per-frame cap scaled with framerate and
  tripped the relay's rate limit → `4429` drops on a high-refresh host); `_disconnect_peer`
  implemented (the host kick was a no-op); the army-receive deserialize yields so a big spawn can't
  starve the relay heartbeat; a restore-lock + `network_id` idempotency so a host army delivered via
  **both** the join state-sync **and** the per-army broadcast no longer drops or duplicates models;
  **Sort Table** now mirrors to the other player; and special-rule **tooltips** sync on a mid-session
  import. The relay was redeployed with a higher rate limit (300 → 2000) and IP-connection cap (5 → 10).
- **Model orientation on oval bases** — vehicles align **along** the oval's long axis; **walkers**
  sit **crosswise** (deterministically — a biped's near-square footprint made the model-AABB long
  axis unreliable, so it is derived from the base geometry).

### Added
- **Auto buff-tokens from special rules.** On army import the special rules are scanned and the
  matching buff tokens are auto-created (a curated map plus an aura / buff / `+1`-`-1` / re-roll
  heuristic; passive rules skipped), synced so **both** players get them — no more creating them by
  hand each game.
- **Per-model base size from upgrades.** A weapon-team / Tough-raising upgrade puts that one model on
  a **bigger base** than its squadmates (derived from the per-model Tough; plain models unchanged).
- **Boot build identifier + send-rate diagnostics.** Every build's first log line is
  `[Boot] Niemandsland <version> build <git-short>`, and the relay peer logs its real outgoing
  msg/s — so a bug report pins exactly which binary ran and how fast it was sending.

### Added (earlier this cycle)
- **Battlefield stains on removal (issue #60).** Removing a model now leaves a persistent
  flat decal sized to its base: a **blood splatter** for infantry, and for **vehicles**
  (Tough 6+) an **oil slick with 1-3 small fires**. Generated splatter textures (R2,
  prefetched) laid on a flat quad. New `BattlefieldStains` node, hooked off model/unit
  removal (radial Delete, Delete key, wounds → 0) and the matching remote sync, so peers see
  the same stains; the fire scatter is seeded from the table position (multiplayer-parity).
  Stains live outside ObjectManager (survive model cleanup); decorative, not saved.
- **Alien-jungle dangerous terrain: carnivorous plants.** The `alien_jungle` biome's
  dangerous terrain now spawns a TRELLIS 3D **carnivorous-plant clump** (bioluminescent
  alien flytrap maws) — mirroring the volcanic lava crater, but with no glow light (the
  bioluminescence is in the model's texture). The per-biome dangerous-terrain prop is
  generalized (`BIOME_HAZARD_MODELS`:
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
  running `config/version` with SemVer precedence (prerelease-aware), skips web builds, and fails safe when offline. Inert until releases are
  published; see [`docs/UPDATE_CHECK.md`](docs/UPDATE_CHECK.md).
- Battlemap generation + R2 publishing were reworked in the private asset-pipeline repo
  (battlemaps uploaded together with their manifest).
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
  (freesound.org; fetched via the private asset-pipeline repo) delivered
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
  window + normal map + the 2 MB masonry source) is archived on **R2** (asset CDN), not
  bundled — only the runtime `ruins_wall.webp` ships. The reproducible recipe + reference
  renderer live in the private asset-pipeline repo.

## [0.3.1-alpha] — Alpha Release Candidate

Goal of this release: a playable, internet-multiplayer Alpha RC with all miniature
3D models delivered on demand from R2.

### Added
- **Multiplayer version handshake.** On join, the client announces its game version
  and the host gates state sync on a match — a 0.3.0 and a 0.3.1 player can no longer
  share a table. Mismatches are rejected host-side (kick) and refused client-side,
  with a clear message; a silent/old client is dropped after a grace timeout.
- **On-demand 3D model delivery (Cloudflare R2).** Miniature GLBs are content-addressed
  (`sha256.glb`) and fetched at runtime from the asset CDN, mapped by
  `assets/model_manifest.json`. Builds no longer bundle them.
- **IP-safe faction generation overhaul** in Model Forge: positive-only prompts,
  per-faction `ip_strict` / `bio_weapons` flags, per-unit `type:` (vehicle / walker /
  aircraft / titan), humanoid-only design cues — plus a **3-versions-per-unit "pick the
  best" review tool**.
- **Factions shipped to R2:** Alien Hives (41), Battle Brothers (23) and Robot Legions
  (29), joining the earlier Dao Union (19) and a Dark Brothers hero — `model_manifest.json`
  now resolves **113 models across 5 factions**, all verified live on the asset CDN.
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
