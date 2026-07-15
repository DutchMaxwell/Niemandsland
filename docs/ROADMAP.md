# Roadmap

Niemandsland is an early alpha. This is the **living, prioritized view** of what's
planned and where ideas go. For what already works see
[`PROJECT_STATUS.md`](../PROJECT_STATUS.md); for shipped history see
[`CHANGELOG.md`](../CHANGELOG.md).

## How a request flows

```
💡 Idea  →  🔍 Triage  →  📋 Next  →  🔨 In progress  →  ✅ Shipped
            (maintainer
             accepts / declines)
```

- **Submit** ideas and bugs as [GitHub issues](../../issues/new/choose) (Bug report /
  Feedback templates) — that's the intake.
- The **maintainer triages**: accepted items move to **Next**, raw ideas to **Ideas**.
  Nothing is owed an outcome; this is a hobby project (see
  [`CONTRIBUTING.md`](../CONTRIBUTING.md)).
- Each item stays short: **title · why · size (S/M/L) · status · link**.

## 🔨 Now (in progress)

- **`0.3.9.0-alpha` shipped (2026-07-15) — the movement/UX update.** One tag: **Path Painting**
  (paint your move; base-width chalk trails; arc-truth distance in ruler + battle log; MP-synced
  ledger; opt-in dry-brush movement cap), **1″ spacing** protection, the **Deployment → Start Game →
  Playing** phase gate (MP ready-sync), **Mummified Undead** live on R2 with 3D models
  ([#117](../../pull/117) + root-manifest flip — 44 factions / 1,185 models now live), the
  guided-tutorial foundation ([#121](../../pull/121), below), terrain-projected "perfectly based"
  bases (#123), versioned `.nml` save migration (#119), anonymous relay usage stats (#115),
  rotate-to-face-cursor (#114), and an English-only UI pass ([#134](../../pull/134)). Full detail
  under **Recently shipped**. Next: **feedback-driven toward the MP-first Beta** (see Next), with the
  **Solo / Co-Op AI** (OPR's official ruleset) field-testing on `feat/solo-ai` and **autosave** the
  leading follow-up. _S_
- **Guided tutorial — foundation shipped in `0.3.9.0-alpha` ([#121](../../pull/121)).** Event-gated guided play on the real table (coach-mark spotlight overlay; steps advance
  on real signals, never a "Next" button): T0 walking skeleton + T1 **tool track W1–W7** (camera ·
  import · select/move/rotate/undo · dice & measuring · card dock & activation · wounds/park/revive ·
  movement & trails)
  with a bundled real board (`assets/tutorial/tutorial_board.nml`, offline — no Army Forge
  dependency), the two-question self-assessment (sim-experienced may skip W1/W3), and per-lesson
  persistence + resume/replay chapter picker (`user://tutorial.cfg`). **Remaining:** T2 rule track
  (R1–R3) + context first-time tips + MP guest toast track; T3 relay step instrumentation
  (design: maintainer's tutorial plan, 2026-07-09). _M_

## 📋 Next (post-Alpha — Beta + alpha-feedback driven)

Deferred out of Alpha by maintainer decision (2026-06-23): the 2-player game is shipped + soak-
validated, so the rest waits for **alpha feedback** or the **Beta** cycle.

- **Age of Fantasy — factions + Regiments** — generate the AoF faction 3D models via **Model Forge
  V2** (→ R2; this also resolves the `saurians` ↔ `saurian_starhost` faction-folder mismatch).
  Live Regiments import vs a real `aofr` list is **verified** (2026-06-29). **Regiments handling polish — SHIPPED:** auto-face-on-drop
  facing fix (P0); frontage cycle (Shift+F), axis-locked drag (Shift+drag), pivot snap (Ctrl+R),
  mouse-driven rotation (R-hold, AoF:R p.8 "Pivoting"); pooled-wound counter with back-rank casualty
  removal + standard WoundsDialog (p.9, Tough(1) pooled / Tough(X>1) classic), regiment radial menu,
  45° arc quadrants on the selected unit (p.5), live rotation-degrees readout, unit-card for trays.
  **Remaining:** display-only melee aids (two-front-rows highlight, full-rows counter,
  flank/rear morale modifier hint) — not yet built. Beta. _L_
- **MP reconnect — 3+ player hardening** — **mostly shipped in `0.3.8.0-alpha`
  ([#105](../../pull/105)):** the host peer→slot-table mirror (3+-player avatar/cursor colour agreement
  after a reconnect), the shared wrapping `slot→palette` helper (army bases match presence colour at
  slot ≥ 5), and the regiment tray's serialized `network_id` all landed. The last piece — a
  **guest army-import await timeout** (a stalled import aborts, releases the restore lock, toasts
  the player, and recovers; host can re-import) — is now **code-complete ([#120](../../pull/120)),
  pending live 2-instance verification**. 2-player reconnect is shipped + soak-validated. _S_
- **UX polish (feedback-driven)** — Measure-on-pickup → snap-back (live ghost preview, ESC to return)
  · Coherency visualizer (sharpen — highlight models outside X″ of a neighbour) · contextual control
  hints (hover an object → its hotkeys). Deeper post-Alpha resilience / accessibility / onboarding
  items live in **Ideas**. _S–M_
- **Solo / Co-Op AI — to merge-ready (`feat/solo-ai`)** — the in-game `SoloController` and the headless
  self-play sim share OPR's official ruleset; remaining rule/wiring work before merge: melee "only
  models **within 2″** strike"; **split-fire** + the weapon-rule overlays (**AP** → target the best
  Defense, **Deadly**, **Takedown**, **Relentless**) + **Medics**; **P3** — wire the sim's
  `AiDecision` / `TerrainRules` / 1″-spacing modules into the real `SoloController` (and fix the
  `_solo_attack_groups` dead-models-still-attack bug there — already fixed in the sim); **P2** in-game
  auto-game (in-game alternation + scoring). **Objective re-allocation** (units re-target when the
  holders of a second objective die) is a **difficulty/tuning layer**, not a correctness fix. _L_
- **Solo movement overhaul (design pending — planned with the coordinator)** — (a) treat walls as
  **Impassable movement blockers**, reusing `terrain_overlay.gd`'s wall segments (`_wall_cells` /
  `_last_wall_segments`); (b) replace the rigid-grid formation move with **individual models moving in
  coherency**, reusing `coherency_checker.gd` (1″ / 9″). Approach (steering-first vs full grid-A*)
  undecided. _L_

### Alpha-feedback batch (accepted 2026-07-01) — sorted Now vs soon

> **✅ Shipped in `0.3.7.2-alpha`:** dice-log live-scroll, deployment-zone colour flip, cursor/avatar
> label sizes + avatar fade-on-zoom, movement cap (opt-in), and return/revive units & models.
> **✅ Shipped in `0.3.8.0-alpha`:** the bottom army unit-card dock (D-series + card-UX rounds). The
> items below remain queued (avatar/cursor full rework, background-world toggle, Change-Daemons cascade).

**📋 Soon (medium — next):**
- **Avatar transparency on zoom** — as a player zooms in (closer to the table), fade *their* avatar
  for the others so it stops hiding the detail they're inspecting; at max zoom only a faint ghost
  remains. Needs the remote camera zoom/distance synced. _M_
- **Movement cap (opt-in enforcement)** — a "Movement" area docked ABOVE the dice interface: pick a
  cap (Advance / Rush-Charge) and the selected model/unit can then only be dragged that far. Reuses
  the movement-reach math (`MovementRangeController`) + the Solo-AI `MoveIntent` clamp. _M_
- **Avatar + MP cursor rework** — beyond the label sizes: redesign the two-ring cursor + the avatar
  presentation (the transparency-on-zoom and label-size items fold in here). _M_
- **Background world toggle** — switch the table backdrop between the current hobby-den/starfield and
  a **fantasy world** environment. Needs a fantasy skybox/environment asset. _M_

**🧊 Larger (coming weeks — design/UI/rules):**
- **Change Daemons death-cascade** — Change Horrors spawn a new (smaller) unit when destroyed, which
  can itself cascade on death. Faction-specific, builds on the shipped Return/revive (#87–#91). Example
  list: `army-forge.onepagerules.com/share?id=JqJOxSFl4ooA` (Wormhole — Daemons of Change). _L_

> _(The **bottom army unit-card dock** (#84–#103) and **Return / revive units & models** (#87–#91)
> that used to head this list shipped in `0.3.8.0-alpha` — see **Recently shipped**.)_

## 🧊 Ideas (icebox — captured, not committed)

- **MP resilience hardening (Beta) — research-backed** — post-Alpha netcode hardening from a deep-
  research pass (the 2-player Alpha path is already validated + soak/fault-tested; these are Beta-grade,
  NOT Alpha blockers). All must be hand-rolled: Godot's `MultiplayerSynchronizer`/`MultiplayerSpawner`
  do **not** work over our custom WebSocket relay (verified). Each is verifiable via the headless
  soak/fault harness (`test/mp/`). In priority order:
  - **Periodic / on-demand authoritative full-state resync** — a host-triggered (or guest-requestable)
    clean full snapshot as a desync-recovery net, alongside the current event sync (Source delta-vs-ACK
    model). The army-import burst is the natural full-snapshot path. _M_
  - **Reconnect session-token + sequence-numbered delta replay** — issue a session token (TTL ~2–5 min);
    on reconnect replay only the events missed since the guest's last sequence number (in-memory host
    event log — a relay restart drops everyone anyway), instead of a full restore. Closes the
    graceful-guest-reconnect gap. _M_
  - **Bounded retry-with-backoff reconnect** — today reconnect is a single 25 s attempt, so a transient
    relay hiccup ends the session; add a few randomized-exponential-backoff retries within a total cap
    (no storm risk at 2 players). _S_
  - **Additive tag-numbered message-schema versioning** — evolve the wire protocol forward/backward-
    compatibly (protobuf model, on Godot's `var_to_bytes`) so minor changes interoperate across builds;
    reserve the hard exact-version refuse for genuine breaking changes. _M_
  - **Periodic state-hash desync check** — host hashes authoritative state, guests compare + request a
    full resync on mismatch (no Godot recipe exists; needs prototyping). _S_
- **Map packs** — bundle / share / load curated board layouts (own Niemandsland-authored first, IP-safe).
  The editor's layout JSON currently drops biome + free-placed sandbox terrain; a pack also needs those +
  a header + a preset picker. Deferred indefinitely (maintainer, 2026-06-25). _M_
- **Dice tray — mid-session join sync** — a late joiner sees the current cup only after the other player
  next changes it or rolls; add a host push of the current cup composition + colour tags on join. _S_
- **In-game self-updater — write-permission handling** — the one-click updater ships with a browser-
  download fallback, but a real Linux test (2026-06-26) showed it **fails when the install dir isn't
  writable** (system/read-only locations would need elevation). Cheap win: detect an un-writable install
  up front and go straight to the download page (never "fail" mid-update). A true self-update for *any*
  location is a known-hard problem (deferred — maintainer); itch.io's butler channel already auto-updates
  that install. Win/macOS in-place swap also still untested. _S_
- ~~**Repo `.git` bloat cleanup (~2.3 GB)**~~ — **DONE 2026-06-29.** Diagnosis (`count-objects -vH`)
  showed the *packed* history was only 70 MiB; the 2.22 GiB was **loose unreachable objects** (dangling
  leftovers from the earlier filter-repo rewrites + GLB imports), not large blobs in real history. So no
  rewrite / force-push was needed — a local `git reflog expire --expire=now --all && git gc --prune=now`
  brought `.git` to **70 MB** (`fsck` clean, `origin` untouched). Re-bloat recurs after history rewrites
  or large GLB imports → periodic `gc --prune=now` is the maintenance. _resolved_
- **Multi-level terrain** — per-cell elevation and ramps. (Walkable multi-storey ruin
  floors already shipped via the sandbox terrain; this is the grid-editor / per-cell
  elevation side.) The surface-aware placement raycast (models rest on terrain tops) is
  the groundwork. _L_
- **Symmetric PvP hidden info** — manual hidden deployment, per-unit hide/reveal (reveal when a
  unit acts), and face-down secret objectives. The unowned niche: VTTs only do GM-vs-player fog;
  symmetric PvP hidden deploy + secret missions is unclaimed. Purely human-driven (a toggle, no
  auto-reveal engine). _L_
- **Manual tracker widget** — VP / round / command-point / objective counters the players
  increment themselves (optional stream overlay). State-tracking, not score automation. _M_
- **Colorblind mode + accessibility** — patterns/labels (not colour alone), safe UI scaling, and
  Steam Deck / controller support. Clean gaps TTS leaves to modders. _M_
- **Camera comfort options** — fixed-speed / instant-stop camera (anti motion-sickness), a
  top-down toggle, and snap/alignment helpers on placement. _M_
- **Per-object physics toggle + large-army perf** — a per-object collision/clipping toggle and a
  performance pass for high model counts (our minis are already collision-free on layer 2). _M_
- **Godot 4.7 — upgrade & feature opportunities** _(prerequisite for the sub-items below)_ — bump the
  engine from 4.6. Revalidate the scaled-SubViewport dice physics + default physics, the custom shaders
  (anti-tiling floor, flames) and the Vulkan/NVIDIA MAILBOX swap-chain workarounds; run gdUnit4 + pytest.
  The 4.7 BlendSpace compat-break is N/A (no AnimationTree in the project). Also de-risks the post-Alpha
  macOS port (refactored Metal renderer). _M_
  - **AreaLight3D mood lights** — soft rectangular area light(s) for indoor / showcase moods in the
    ATMOSPHERE presets; today `lighting_controller.gd` is sun + fill `DirectionalLight3D` + `Environment`
    only. A genuinely new light type → wire into the preset table + 2 s blend, gate behind the quality
    tiers (area lights are costlier). _M_
  - **HDR output toggle** — OLED / HDR-display output as a persisted option in `graphics_settings.gd`,
    AgX-tonemap-aware; mind the same swap-chain-recreation caution we already document for the
    fullscreen / MAILBOX path. _S_
  - **Control offset transforms for HUD polish** — `offset_transform_*` animates / rotates / scales
    container-bound Controls without the parent re-layout wiping it: the floating unit-card rule popup
    (`unit_card.gd`) and the planned "Contextual control hints". (Not the radial menu — it is
    immediate-mode `_draw`.) _S_
  - **3D particle scale / rotation in the process material** — directional rain streaks + varied
    smoke / embers via the new scale-3D / rotation-3D process params (`rain_effect.gd`, `fire_prop.gd`).
    Minor polish. _S_
  - **DrawableTexture2D for HUD / icon textures** — pre-bake glow / gradient textures (the radial-menu
    glow halo is faked with three stacked arcs because `_draw` has no blur) and procedural die-face /
    token icons, instead of per-frame `_draw`. Optional, low value. _S_
- Rules-reference overlays for more game systems.
- **Game replay (event journal → auto playback)** — record a session as an initial `.nml` snapshot plus a
  timestamped EVENT JOURNAL (unit/model moves with exact from→to table coordinates, dice results, wounds,
  activations, rounds) and play it back automatically — "watch this game" files. The central Battle-Log
  seams are already replay-grade: `object_manager.selection_dropped` carries per-model from→to positions
  (#106); the journal is a separate persistent recorder on those seams (the display log stays a capped
  ring buffer). MP-safe: both clients observe the same central events. (Maintainer, 2026-07-06.) _L_
  - **Cinematic replay** (far future) — a camera director on top of the journal: framing the active unit,
    dice moments, charges — instead of the static top view. _XL, after the base replay_
- **Variant-aware mounting** — a mounted leader currently swaps to the mount GLB and loses his weapon-
  variant visual (`opr_army_manager` replaces model 0); a later game-side change could resolve composed
  `<unit>#<mount>+<slug>` variants instead. _M, after the mounts chapter ships_
- **Persistent room / async play** — a long-running hosted table (or a turn-based save-file relay flow)
  so players take turns asynchronously; today's answer is save-file exchange + the battle log. We are
  host-authoritative with a dumb relay, so a "persistent room" means either a headless host client or
  relay-side state — both heavy. Community-requested (DE Discord, 2026-07-05). _XL, far future_
- **"Bake-Ladder" — high→low bake + normal-map re-optimization (experiment)** — bake each on-table
  GLB's high-poly detail into a low-poly mesh + normal map: a candidate **3–4× on-table geometry
  reduction** with no visible quality loss. Pipeline-side (Model-Forge) experiment, not yet validated. _M_
- **Runtime LOD for CDN-loaded GLBs** — Godot's automatic mesh LOD is generated at *import* time, so it
  does **not** apply to GLBs loaded at runtime from the CDN; a hand-rolled distance-based LOD (or a
  pre-baked LOD chain carried in the manifest) would cut the draw cost of large armies. Depends on the
  asset pipeline emitting the LOD levels. _M_
- _Community feedback from the alpha lands here first._

## ✅ Recently shipped

See [`CHANGELOG.md`](../CHANGELOG.md). **`0.3.9.0-alpha` (2026-07-15):** the movement/UX bundle (#131) —
**Path Painting** (base-width chalk trails, arc-truth distance in ruler + battle log, click-to-measure,
MP-synced move ledger, trail toggle + deployment auto-suppress, backtrack-erase), **1″ spacing**
protection (proximity walls, base-contact snap, no-overlap drops), a **game-phase gate** (Deployment →
Start Game → Playing with an MP ready-sync + save/load), and an opt-in **"dry-brush" movement cap**
(action-band-aware, Advance/Rush-Charge); the **guided tutorial** foundation (T0 + T1 tool track W1–W7,
#121); **Mummified Undead** live on R2 (#117); "perfectly based" terrain-projected bases (#123);
versioned `.nml` save migration (#119); privacy-preserving relay usage stats (#115); rotate-to-cursor
(#114); guest-import timeout + relay-shutdown-stats fixes (#120/#124); repo-hygiene CI hardening
(#128–#130).

**`0.3.8.0-alpha` (2026-07-08):** unit-card dock rework
(#84–#103), Battle Log incl. remote moves (#99/#101/#106/#112), ctex runtime assets (#85–#93),
dead-model parking (#87–#91), MP 3+ hardening + shared palette (#105), session-wide free-move (#107),
offline-peer singleplayer fix (#108), permanent room-code readout (#110), variant/ctex restore fix
(#111), CDN honest UA (#104), body-AABB model fit (#96).

**`0.3.7.2-alpha` (2026-07-01):** Age of Fantasy: Regiments
handling — frontage cycle, axis-locked drag, pivot snap, pooled-wound counter, radial menu, 45° arc
quadrants, mouse rotation, facing-on-drop; plus dice-by-colour (#77), Swift movement bands (#79),
table-scaled auto-deploy terrain (#83), Ambush/Scout on every tray (#76), type-aware base sizing,
biome dangerous terrain, playtest quick-wins (#78/#80/#81/#82), the Linux self-updater ETXTBSY fix,
and macOS ad-hoc signing; plus the accepted alpha-feedback quick-wins — dice-log scroll, deployment-
zone flip, cursor/avatar labels + avatar fade-on-zoom, movement cap, return/revive units & models,
#79 granted-rule/aura movement, dead-model base fix. **`0.3.7.1-alpha` (2026-06-26):** playtest-feedback patch — 8
playtest fixes (LoS / markers / tokens / formation / rotation / labels / auto-face / load-gate), per-die
colour tagging + live MP sync, a one-click in-game self-updater, a live CDN asset manifest, and the
Ambush/Scout deployment field. **`0.3.7-alpha` (2026-06-25):** the MP reconnect-storm / desync
fix (relay head-of-line block + token host-slot reclaim, diagnosed from a real 2-PC game), the first
**macOS build**, **per-biome terrain**, the Alpha bug reports (#70–74, Banner/Musician/Sergeant), and a
fix to the in-game update checker (it now compares all four version fields — it had been blind to
`0.3.6.x` patches). **0.3.6 round-up (Alpha release):** **MP reconnect fully
solved** — the netcode replatform moved all game messaging off `@rpc` onto a command protocol below
the RPC path-cache (the version-kick reconnect cascade is gone), plus a **relay-restart / idle
self-heal** (the host re-creates its room with the SAME code and guests auto-rejoin, recovering when
the scale-to-zero relay drops its in-memory room; relay deployed v4); a big **OPR unit-card overhaul**
(item-grant hover cascade, faction spell list + spell-range hover ring for casters, item-granted
weapons surfaced as real weapons, fully English card); **correct per-model loadout distribution** (a
Sergeant's gear groups on one model; a weapon-team's enlarged base aligns with its special-weapon
ring); **mount / vehicle base + model** (a Combat Bike / dinosaur brings its own base, scaled from
the larger Tough, plus a fuzzy-matched faction mount GLB); **aircraft flight-stand hover** (~20 cm,
distinct from Flying); and **vehicles fit their base** (oval + Tough-derived bases fill exactly with
no overhang, deterministic long-axis orientation). Earlier highlights (0.3.5 round-up): **in-game F12 bug report
with screenshot** (capture a visual glitch + bundle it with the anonymised log into a zip on the
Desktop — the natural capture for the bugs the text log can't see); the **multiplayer
two-client live test passed** — the reconnect / rate-limit / army-sync cascade was
live-validated across two real clients (wall-clock send-rate cap, host-kick fix, deserialize
yield, restore-lock + `network_id` idempotency, Sort-Table mirror, mid-session tooltip sync);
**anonymous diagnostics / bug-report export** (a scrubbed "Report a problem" bundle — recent
log files, room codes/player names stripped); **auto buff-tokens from special rules** (scanned
on import, synced to both players); **per-model base size from upgrades** (a weapon-team /
Tough-raising model gets a bigger base than its squadmates); and **model orientation on oval
bases** (vehicles along the long axis, walkers crosswise). Earlier (0.3.4 round-up): **casual
sandbox terrain** (grid-free free-placed multi-storey ruins + oval tree-group forests +
anti-tiling floor shader), **3 new factions** (blood / custodian / wolf_brothers), with four more
since (havoc_brothers / knight_brothers / rebel_guerrillas / war_disciples + dark_brothers built
out) — the manifest is now **634 models across 27 factions**, all live on R2, the **multiplayer
sync + reconnect-hardening pass** (imported-army
models + biome sync to peers and late-joiners, paste/delete/arrange replication, own-only
mini movement, import-slot default, phantom-player + abort hardening), and **stable player
identity across reconnect** ([PR #66](../../pull/66) — a per-install token → canonical slot remap so a
reconnecting player returns to their exact slot/colour/army with no phantom; `network_id`
namespaced by owner so two armies never collide; adversarially reviewed), **persistent
shared rulers** ([PR #64](../../pull/64) — pin a measurement with P; it stays on the table in the owner's
colour and replicates to everyone, including late-joiners; K clears yours, Shift+K all), and
**base-anchored range rings / auras** ([PR #65](../../pull/65) — G cycles a per-model radius 3″/6″/…/24″ from
the base edge, Shift+G clears; local display aid), and the **movement reach indicator** ([PR #67](../../pull/67)
— M toggles per-model Advance + Rush/Charge bands in the player's colour, OPR Fast/Slow aware;
display-only, local). Earlier: **Age of
Fantasy: Regiments**
(movement-tray blocks, square bases, casualty re-rank, save/load, **facing &
front-arc display**), **units as line-of-sight blockers** (`LosRules.units_block_line`,
Asgard standard, display-only), the **UI audio bus** (`UiFeedback` autoload on a
dedicated, independently mutable "UI" bus + hover/click/focus ticks and a volume slider
— shipped as `UiFeedback`, not the originally-planned `UiSound`), **skirmish 6″
coherency** (Firefight / AoF: Skirmish), the asset-CDN decoupling, and the go-public
preparation.

---

<sub>Maintainer/agent note: this file is the curated backlog and the single
forward-looking source. The agent reads it at the start of a session, implements the
top **Now / Next** item, and moves it to **Shipped** with a PR link on merge.</sub>
