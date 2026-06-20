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

- **🐞 BUG: guest reconnect with a NEW peer id → version-kick cascade (the sporadic-reconnect root
  cause)** — reproduced deterministically by the `--fault churn` soak (2026-06-20). When a guest's
  own connection drops and the relay hands it a **fresh** peer id on rejoin, Godot's
  `connected_to_server` does not re-fire on the reused `MultiplayerPeer`, and even when we re-announce
  explicitly (now wired via `relay_reconnected` → `_on_guest_reconnected`), the announce RPC never
  reaches the host because SceneMultiplayer's unique-id / RPC routing for the new id is stale → the
  host kicks the peer on the 8 s version-handshake timeout → it rejoins → kicked again (cascade). No
  phantom players are created (kicked before a slot is assigned), and the model COUNT stays converged
  (which is why earlier count-based tests passed). **Landed so far:** (1) re-announce on guest reconnect
  (`relay_reconnected` → `_on_guest_reconnected`); (2) the **relay now reuses the guest's old peer_id**
  within a rejoin window keyed by its identity token (client sends `token` in `join_room`), so the
  transport id is STABLE across a drop. **TRUE remaining blocker (precisely diagnosed):** Godot's RPC
  **path-cache** — even with a stable id the guest re-sends its announce to the host (peer 1) using the
  path id cached on the OLD connection; the host on the new socket doesn't have it → RPC dropped ("ID not
  found in cache") → no announce → kick. Peer 1's cache can't be flushed the normal way
  (`peer_disconnected(1)` on a client triggers `server_disconnected` = teardown). **Next:** force the guest
  to re-negotiate the RPC path to peer 1 on reconnect (a guarded `peer_disconnected(1)`+`peer_connected(1)`
  that suppresses the teardown, or a controlled multiplayer-peer reset). Regression guard:
  `churn`/`chaos`/`blip` soaks assert "no version-kick" + "remap fired" (fail by design until fixed).
  Likely affects real 2-player play. _M_
- **MP reconnect — 3+ player hardening (follow-ups)** — review-surfaced items not needed for
  the 2-player case: mirror the host's peer→slot table to guests (3+-player avatar/cursor
  colour agreement after a reconnect), a shared `slot→palette` helper so army bases match
  presence colour at slot ≥ 5, an import-await timeout, and restoring a regiment tray's
  serialized `network_id` instead of re-allocating. _S_
- **AoF: Regiments — verify import vs a real list** — manually confirm base sizes / frontage
  from Army Forge against an actual `aofr` army (manual QA; no automated checker planned). _S_

## 📋 Next (accepted, queued)
- **Regiments — handling polish** — move a unit as one block, axis-locked drag (straight),
  frontage cycle (5-wide ↔ other), and wheel/pivot about the front corner. Community-validated
  (bulk-move + wheeling is a top TTS friction). `regiment_tray.gd` has `frontage`/`reform`,
  but no block-move/cycle/wheel yet. _M_
  **⛔ Prerequisite: generate the Age of Fantasy faction 3D models first (pipeline).** Until the AoF
  factions exist on R2 there is nothing to rank in the trays, so the handling polish is sequenced
  AFTER AoF model generation. (Maintainer decision 2026-06-19.)
- **Measure-on-pickup → snap-back** — grabbing a model starts a live measurement with a ghost
  preview; release to commit, ESC to return to the pickup point. TTS later shipped exactly this.
  Extends `object_manager` drag + the height-aware LoS measuring. _M_
- **Coherency visualizer (sharpen)** — highlight models outside X″ of their nearest neighbour
  (TTS doesn't solve this; guides say "ignore coherency"). Builds on `coherency_checker.gd` /
  `coherency_visualizer.gd`. Show, never correct. _S_
- **Contextual control hints** — hover an object → its hotkeys appear. Tabletop Playground's
  most-praised onboarding feature; onboarding is the key UX battleground for digital wargaming. _S_
- **Sandbox forests for the other biomes** — extend the shipped grassland forest pads to
  desert / tundra / volcanic / jungle / urban (per-biome forest-floor textures + `biome_prefix`
  wiring; the biome tree GLBs are already on R2). _S_

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

See [`CHANGELOG.md`](../CHANGELOG.md). Highlights (0.3.5 round-up): **in-game F12 bug report
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
