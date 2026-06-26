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

- **Alpha is live; `0.3.7.1-alpha` shipped (2026-06-26) on all three platforms.** The playtest-feedback
  patch on top of `0.3.7-alpha`: 8 playtest fixes (formations centre on the unit, both-way
  rotation, readable terrain labels, per-token terrain height, auto-face-on-move, lone-survivor markers,
  dead-model line of sight, an MP load-gate), plus **per-die colour tagging** (+ live MP sync), a
  **one-click in-game self-updater** (dormant until the next release — Win/macOS in-place swap still
  wants a real-machine test), the **live CDN asset manifest** (reworks reach players with no game
  release), and the **Ambush / Scout deployment field**. Next work is **feedback-driven** toward the
  **MP-first Beta** (see Next); a **Solo / Co-Op AI** (OPR's official ruleset) is being scoped. _S_

## 📋 Next (post-Alpha — Beta + alpha-feedback driven)

Deferred out of Alpha by maintainer decision (2026-06-23): the 2-player game is shipped + soak-
validated, so the rest waits for **alpha feedback** or the **Beta** cycle.

- **Age of Fantasy — factions + Regiments** — generate the AoF faction 3D models via **Model Forge
  V2** (→ R2; this also resolves the `saurians` ↔ `saurian_starhost` faction-folder mismatch). Then
  verify Regiments import vs a real `aofr` list and add the Regiments **handling polish** (move as one
  block, axis-locked straight drag, frontage cycle 5-wide ↔ other, wheel/pivot about the front
  corner — `regiment_tray.gd` has `frontage`/`reform` but no block-move/cycle/wheel yet). Beta. _L_
- **MP reconnect — 3+ player hardening** — mirror the host's peer→slot table to guests (3+-player
  avatar/cursor colour agreement after a reconnect), a shared `slot→palette` helper (army bases match
  presence colour at slot ≥ 5), an import-await timeout, and restoring a regiment tray's serialized
  `network_id`. 2-player reconnect is shipped + soak-validated; this is feedback-driven. _S_
- **UX polish (feedback-driven)** — Measure-on-pickup → snap-back (live ghost preview, ESC to return)
  · Coherency visualizer (sharpen — highlight models outside X″ of a neighbour) · contextual control
  hints (hover an object → its hotkeys). Deeper post-Alpha resilience / accessibility / onboarding
  items live in **Ideas**. _S–M_

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
- **In-game self-updater — Windows/macOS live test** — the one-click updater shipped Linux-tested (with a
  browser-download fallback); the Win/macOS in-place swap needs a real-machine test before it first
  activates (the release after 0.3.7.1). _S_
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
- _Community feedback from the alpha lands here first._

## ✅ Recently shipped

See [`CHANGELOG.md`](../CHANGELOG.md). **`0.3.7.1-alpha` (2026-06-26):** playtest-feedback patch — 8
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
