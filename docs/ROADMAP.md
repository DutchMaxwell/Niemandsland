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

- **`0.3.9.0-alpha` — release prep.** The next wave is **merged to `main` and awaiting the
  `v` tag** (see the unreleased CHANGELOG section): terrain-projected miniature bases
  ([#123](../../pull/123)), the versioned `.nml` save-migration chain ([#119](../../pull/119)),
  the guest army-import await timeout that completes the 3+ hardening ([#120](../../pull/120)),
  the relay usage-stats histogram fix ([#124](../../pull/124)), the Mummified Undead go-live
  **game-side integration** ([#117](../../pull/117)), the folded-in worker gotchas doc pass
  ([#118](../../pull/118)), and the loose-model **rotate-to-face-cursor** community fix
  ([#114](../../pull/114)). Cut the tag once the field-test items below have a maintainer
  verdict. _S_
- **Mummified Undead — root-manifest flip (blocks the faction going live).** The game-side
  integration merged ([#117](../../pull/117): slug-map lines, `snake`/`sphinx` mount keywords,
  whole-token mount specificity, composed `<hero>#<weapon>+<mountslug>` resolution). The faction's
  3D models are **not yet in the live root manifest** — the remaining step is the maintainer's QA
  pass via a staged manifest override and then the **root-manifest flip** on R2 (see
  [`MANIFEST_DELIVERY.md`](MANIFEST_DELIVERY.md)). Until the flip, the CHANGELOG must not claim the
  models are live. _M_

### Held back for a field-test verdict (NOT in 0.3.9)

These are built or in-progress on their own branches and are **held out of the release** until the
maintainer field-tests them and gives a go/no-go — the changelog deliberately does not claim them.

- **Solo / Co-Op AI — field test (`feat/solo-ai` stack, #122).** The in-game `SoloController` +
  headless self-play sim share OPR's official ruleset. Awaiting a maintainer play verdict before it
  ships; the remaining rule/wiring work is tracked under **Next** (Solo rules wave 5). _L_
- **Guided Tutorial — field test (#121 + T2).** A first-run guided tutorial; held for a maintainer
  pass on flow/coverage. The intended split into two tracks (tool tutorial vs OPR rules tutorial) is
  under **Next**. _M_
- **1″ separation hint (`feat/proximity-hint`).** A display-only nudge when two models sit closer
  than 1″ (OPR unit spacing). Pending a maintainer verdict on the visual. _S_

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
- **MP reconnect — 3+ player hardening — DONE.** Shipped across `0.3.8.0-alpha`
  ([#105](../../pull/105): host peer→slot-table mirror, shared wrapping `slot→palette`, serialized
  regiment `network_id`) and the 0.3.9 wave ([#120](../../pull/120): the **guest army-import await
  timeout** — a stalled import aborts on an inactivity budget, releases the restore lock, toasts the
  player, and recovers; the host can re-import). 2- and 3+-player reconnect are soak-validated. _done_
- **UX polish (feedback-driven)** — Measure-on-pickup → snap-back (live ghost preview, ESC to return)
  · Coherency visualizer (sharpen — highlight models outside X″ of a neighbour) · contextual control
  hints (hover an object → its hotkeys). Deeper post-Alpha resilience / accessibility / onboarding
  items live in **Ideas**. _S–M_
- **Solo / Co-Op AI — rules wave 5 (`feat/solo-ai` stack).** The in-game `SoloController` and the
  headless self-play sim share OPR's official ruleset; the module is in **field test** (see Now). The
  next rule/coverage wave: **Caster** (spend tokens, cast/counter), **Shred**, **Indirect**, and the
  remaining weapon-rule overlays (**AP** → target the best Defense, **Deadly**, **Takedown**,
  **Relentless**) + **Medics** + split-fire; then **P2** in-game auto-game (alternation + scoring).
  **Objective re-allocation** (units re-target when the holders of a second objective die) is a
  **difficulty/tuning layer**, not a correctness fix. _L_
- **Two-track tutorial split (`feat/tutorial-t2`).** Split the guided tutorial (in field test, see Now)
  into two independent tracks: a **Niemandsland tool tutorial** (camera, select/move, import, measure,
  dice, MP) and an **OPR rules tutorial** that walks a game system at a time — **GF → AoF → Skirmish →
  Regiments** — so a player learns the app and the rules separately. _M_
- **Game-system context + rules registry.** A first-class game-system selection
  (**GF / GFF / AoF / AoFS / AoFR**) carried through import and the table, wired to a **rules registry**
  (`feat/rules-registry`) so system-specific behaviour (coherency spread, base shapes, facing/arcs,
  the rules-reference overlays) is chosen by the active system instead of inferred per unit. Unblocks
  per-system tutorials and cleaner Skirmish/Regiments handling. _M_
- **CAS asset-library normalization (M1 migration).** The maintainer reviewed the whole model library
  and flagged normalization work — facing, shadow-disc removal, floater fix, and per-model triage —
  to bring the content-addressed asset library to a consistent M1 baseline (pipeline-side, in the
  separate private repository; the game consumes the re-published manifest). _L_
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
- ~~**Variant-aware mounting**~~ — **game-side resolution DONE (#117).** A mounted hero now resolves to
  a composed `<hero>#<weapon>+<mountslug>` bake (the mount folds a slug into the carrier's labels), with
  the old fuzzy faction-mount GLB as the fallback where no composed bake exists. What remains is
  **producer-side**: the composed mount bakes themselves per faction (pipeline, private repo). _partly done_
- **Per-part mount decimation fix** — a composed mount bake (rider + beast/cart) is decimated as one
  blob, so the rider's fine detail is thinned to the same budget as the bulky mount; a per-part budget
  (rider vs mount) would keep the rider crisp. Pipeline-side (the separate private repository). _M_
- **Tournament-training AI mode** — a stricter Solo/AI profile aimed at *practice*: it plays a clean,
  rules-correct game a human can drill against (list-legal target priority, no fog-of-war shortcuts),
  layered on the Solo/Co-Op AI ruleset once that ships. Distinct from the difficulty/tuning layer. _L_
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

See [`CHANGELOG.md`](../CHANGELOG.md). **`0.3.9.0-alpha` (merged to `main`, tag pending):**
terrain-projected miniature bases ([#123](../../pull/123)), versioned `.nml` save-migration chain
([#119](../../pull/119)), guest army-import await timeout completing the 3+ hardening
([#120](../../pull/120)), relay usage-stats histogram fix incl. shutdown flush
([#124](../../pull/124)), Mummified Undead go-live game-side integration ([#117](../../pull/117);
faction goes live on the pending root-manifest flip), worker-gotchas doc pass
([#118](../../pull/118)), and loose-model rotate-to-face-cursor ([#114](../../pull/114)). Solo mode
and the guided Tutorial are **held back** (field test — see Now), so 0.3.9 does not claim them.

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
