# Road to Alpha — 0.3.6

The plan and release-readiness checklist for cutting Niemandsland's first proper **Alpha
release, version `0.3.6`**. This is the single forward-looking release doc; the curated
feature backlog stays in [`ROADMAP.md`](ROADMAP.md), the honest done/in-progress map in
[`../PROJECT_STATUS.md`](../PROJECT_STATUS.md), and the change history in
[`../CHANGELOG.md`](../CHANGELOG.md).

## Version scheme

| Line | Meaning |
|---|---|
| **`0.3.5.x`** | **Road to Alpha** — iterative hardening, polish and release prep. Every step ships as a `0.3.5.x` bump (build-hash stamped, deployed to testers). |
| **`0.3.6`** | **The Alpha release** — the cut, made once the [exit criteria](#alpha-exit-criteria) are met. Tagged, release-noted, published. |

> Versions are `config/version` in `project.godot`. The save format (`SAVE_VERSION`) is
> versioned separately. Every exported build prints `[Boot] Niemandsland <ver> build <git-short>`
> as its first log line — that hash is the source of truth for "which build is this".

## What this Alpha is (and isn't)

- **It is** a 3D tabletop **sandbox** for OnePageRules: variable tables, Army Forge army
  import with real 3D models, **multiplayer**, physics dice, inch measuring, a map-layout
  editor, and unit tokens/markers. Design philosophy: **show, don't decide** — it presents
  ranges/coherency/state, it does not enforce rules.
- **It is not** a rules engine: no automated turn/combat resolution, no terrain gameplay
  effects. That is explicitly post-Alpha (a roadmap item, not an Alpha blocker).

## Release-readiness checklist

Legend: ✅ done · 🔧 in `0.3.5.x` · ⬜ to do · ❓ decision needed

### A. Gameplay & content
- ✅ MP sync overhaul, per-model base from upgrades, vehicle/walker oval orientation,
  auto-buff-tokens from special rules (shipped 0.3.4.1 → 0.3.5.0, live-validated).
- ⬜ Polish backlog (regiment block-move/wheel, measure-on-pickup → snap-back, coherency
  visualizer sharpen, contextual control hints, sandbox forests for other biomes) — **decide
  which, if any, are Alpha blockers** vs post-Alpha.
- ❓ AoF: Regiments — manual import verify vs a real `aofr` list.

### B. Multiplayer stability
- ✅ Reconnect / rate-limit / army-sync cascade fixed and live-confirmed across 2 clients
  (no 4429, no reconnect churn, tx ~20 msg/s, clean army + token sync). Relay redeployed
  (rate limit 300→2000, IP-conn 5→10).
- ⏭ **Graceful guest reconnect** — **post-Alpha** (2-player only is decided; the churn did not
  recur in the fixed builds). Relay reuses/increments the guest peer-id → stale SceneMultiplayer
  cache; designed, deferred. Revisit only if it reappears in a `0.3.5.x` soak test.
- ⏭ 3+ player hardening (slot→palette mirroring, import-await timeout, regiment network_id
  restore) — **post-Alpha** (decision 3: 2 players only).

### C. Distribution & channels
- ✅ Desktop exports configured for **Linux / Windows / macOS** (`export_presets.cfg`); test
  builds shipped via Bathöhle; boot build-hash on every build.
- ✅ Anonymous **diagnostics export** ("Report a problem") for player bug reports.
- ✅ `UpdateChecker` autoload checks **GitHub Releases** at startup.
- ❓ **Release channel** — GitHub Releases (desktop downloads) and/or the current direct
  Bathöhle hand-off (decision 1). **itch.io / web publishing is dropped — not pursued for now.**
- ⏭ **macOS** — **post-Alpha** (decision 4: Windows + Linux only). Preset exists but is
  untested/unsigned (Gatekeeper/notarisation work).

### D. Documentation
- ⬜ Refresh every version reference `0.3.2-alpha` → the release version (README status
  badge, `PROJECT_STATUS.md` header, `ROADMAP.md` intro).
- ⬜ **CHANGELOG**: fold the current `[Unreleased]` block + this session's work into versioned
  sections, and write the **`[0.3.6] — Alpha** release notes (the headline summary).
- ⬜ **Getting Started** (player-facing): install, host/join a game, import an army, the
  control list. README already lists controls + features; a short quickstart closes the gap.
- ⬜ **Known Issues / limitations** — an honest, player-facing list (no rules automation;
  guest-reconnect caveat; macOS status; etc.).
- ✅ THIRD-party licensing (`THIRD_PARTY.md`), `LICENSE` (MIT code), `CONTRIBUTING.md`,
  `SECURITY.md` — mature.

### E. Legal / licensing
- ✅ Code MIT; generated minis **CC-BY-SA**; fonts SIL OFL; **no OPR data bundled** (loaded
  at runtime via the Army Forge API). Covered by `THIRD_PARTY.md`.
- ⬜ Verify the **CC-BY-SA attribution** for the models is surfaced where players can see it
  (in-app credits / about screen), not only in repo docs.

### F. Go-public (only if the Alpha is a PUBLIC release — decision 2)
- ⬜ **PR #51**: drop `tools/model_forge/` from the public repo (the pipeline now lives in the
  private `model-forge` repo). Rebase onto current `main` and merge.
- ⬜ Verify the **git-history scrub** is complete and the **CDN domain** (`assets.akesberg.de`)
  is stable for on-demand model delivery.
- ⬜ GitHub **issue templates** (Bug / Feedback) + `CONTRIBUTING.md` confirmed as the intake.
- ⬜ Repo visibility flip + a published release tag.

## Alpha exit criteria

`0.3.6` is cut only when **all** of these hold:

1. A clean 2-client multiplayer game (start → both import armies → play) with **no desync,
   no reconnect death** — live-confirmed on a high-refresh host.
2. Desktop builds for the in-scope platforms **launch**, and the boot build-hash matches the
   release tag.
3. Docs refreshed: version bumped everywhere, **`[0.3.6]` release notes**, and a **Known
   Issues** list.
4. The chosen **release channel is live** and `UpdateChecker` points at it.
5. Licensing + model **attribution correct** for the chosen distribution.
6. **No P0 bugs** open (crash on launch, save corruption, MP session death).

## Decisions (locked 2026-06-17)

1. **Audience: PUBLIC.** `0.3.6` is a public release → the **go-public block (F) is in scope**:
   open the repo, PR #51 (drop `model_forge`), verify the history scrub, publish a GitHub Release.
2. **Channel: GitHub Releases** (desktop downloads), plus the direct Bathöhle hand-off for
   testers during `0.3.5.x`. **itch.io / web are dropped — not pursued for now.**
3. **Player count: 2 players only.** 3+ player hardening **and** graceful guest reconnect are
   **post-Alpha** — not `0.3.6` blockers (the 2-player path is live-validated).
4. **Platforms: Windows + Linux.** macOS (and web) are **post-Alpha** (preset exists, untested,
   Gatekeeper/notarisation work).
5. **Feature scope: ship the current state.** No polish items are `0.3.6` blockers — the
   sandbox + multiplayer as they stand. Regiment handling, measure-on-pickup, coherency sharpen
   and contextual control hints are all **post-Alpha**. `0.3.6` work = **docs + go-public only**.

## Remaining `0.3.5.x` work (proposed order)

1. Documentation refresh + CHANGELOG reconciliation + Getting Started + Known Issues *(low risk,
   do early — most of "prepare the docs")*.
2. Decision-gated items from sections C/F (channel wiring, go-public prep).
3. Any agreed Alpha-blocker gameplay/MP items (decisions 3 & 5).
4. macOS test pass if in scope (decision 4).
5. Final 2-client MP soak test → meet the exit criteria → cut **`0.3.6`**.
