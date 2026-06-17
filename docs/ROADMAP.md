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
- Rules-reference overlays for more game systems.
- _Community feedback from the alpha lands here first._

## ✅ Recently shipped

See [`CHANGELOG.md`](../CHANGELOG.md). Highlights (0.3.5 round-up): the **multiplayer
two-client live test passed** — the reconnect / rate-limit / army-sync cascade was
live-validated across two real clients (wall-clock send-rate cap, host-kick fix, deserialize
yield, restore-lock + `network_id` idempotency, Sort-Table mirror, mid-session tooltip sync);
**anonymous diagnostics / bug-report export** (a scrubbed "Report a problem" bundle — recent
log files, room codes/player names stripped); **auto buff-tokens from special rules** (scanned
on import, synced to both players); **per-model base size from upgrades** (a weapon-team /
Tough-raising model gets a bigger base than its squadmates); and **model orientation on oval
bases** (vehicles along the long axis, walkers crosswise). Earlier (0.3.4 round-up): **casual
sandbox terrain** (grid-free free-placed multi-storey ruins + oval tree-group forests +
anti-tiling floor shader), **3 new factions** (blood / custodian / wolf_brothers — manifest now
527 models, live on R2), the **multiplayer sync + reconnect-hardening pass** (imported-army
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
